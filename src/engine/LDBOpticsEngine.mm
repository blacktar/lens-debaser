#include "LDBOpticsEngine.h"
#include <algorithm>
#include <cmath>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

struct LDBBufferPool {
    explicit LDBBufferPool(id<MTLDevice> d) : device(d) {}

    id<MTLBuffer> acquire(NSUInteger length) {
        std::lock_guard<std::mutex> lock(mutex);
        auto& buffers = available[length];
        if (!buffers.empty()) {
            id<MTLBuffer> result = buffers.back();
            buffers.pop_back();
            return result;
        }
        return [device newBufferWithLength:length options:MTLResourceStorageModePrivate];
    }

    void release(const std::vector<id<MTLBuffer>>& buffers) {
        std::lock_guard<std::mutex> lock(mutex);
        for (id<MTLBuffer> buffer : buffers) {
            auto& destination = available[buffer.length];
            if (destination.size() < 3) destination.push_back(buffer);
        }
    }

    id<MTLDevice> device = nil;
    std::mutex mutex;
    std::unordered_map<NSUInteger, std::vector<id<MTLBuffer>>> available;
};

struct LDBOpticsEngine::Impl {
    id<MTLDevice> device = nil;
    id<MTLComputePipelineState> opticsPipeline = nil;
    id<MTLComputePipelineState> decodePipeline = nil;
    id<MTLComputePipelineState> downsamplePipeline = nil;
    id<MTLComputePipelineState> horizontalBlurPipeline = nil;
    id<MTLComputePipelineState> verticalBlurPipeline = nil;
    id<MTLComputePipelineState> apertureBlurPipeline = nil;
    id<MTLComputePipelineState> compositePipeline = nil;
    id<MTLComputePipelineState> encodePipeline = nil;
    id<MTLBuffer> zeroScatterBuffer = nil;
    std::shared_ptr<LDBBufferPool> bufferPool;
    std::string error;
};

static id<MTLComputePipelineState> makePipeline(id<MTLDevice> device,
                                                id<MTLLibrary> library,
                                                NSString* name,
                                                std::string& errorText) {
    id<MTLFunction> function = [library newFunctionWithName:name];
    if (!function) {
        errorText = std::string("Metal function not found: ") + name.UTF8String;
        return nil;
    }
    NSError* error = nil;
    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
    if (!pipeline) errorText = error ? error.localizedDescription.UTF8String : "Unable to create Metal pipeline";
    return pipeline;
}

LDBOpticsEngine::LDBOpticsEngine(id<MTLDevice> device, NSURL* metallibURL) : impl_(new Impl) {
    impl_->device = device;
    impl_->bufferPool = std::make_shared<LDBBufferPool>(device);
    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithURL:metallibURL error:&error];
    if (!library) {
        impl_->error = error ? error.localizedDescription.UTF8String : "Unable to load Metal library";
        return;
    }
    impl_->opticsPipeline = makePipeline(device, library, @"ldbOpticsMain", impl_->error);
    impl_->decodePipeline = makePipeline(device, library, @"ldbDecodeToLinearAP1", impl_->error);
    impl_->downsamplePipeline = makePipeline(device, library, @"ldbDownsampleHighlights", impl_->error);
    impl_->horizontalBlurPipeline = makePipeline(device, library, @"ldbBlurHorizontal", impl_->error);
    impl_->verticalBlurPipeline = makePipeline(device, library, @"ldbBlurVertical", impl_->error);
    impl_->apertureBlurPipeline = makePipeline(device, library, @"ldbBlurAperture", impl_->error);
    impl_->compositePipeline = makePipeline(device, library, @"ldbComposite", impl_->error);
    impl_->encodePipeline = makePipeline(device, library, @"ldbEncodeFromLinearAP1", impl_->error);
    simd_float4 zero = {0, 0, 0, 0};
    impl_->zeroScatterBuffer = [device newBufferWithBytes:&zero length:sizeof(zero)
                                                   options:MTLResourceStorageModeShared];
}

LDBOpticsEngine::~LDBOpticsEngine() { delete impl_; }
bool LDBOpticsEngine::valid() const {
    return impl_->decodePipeline && impl_->opticsPipeline && impl_->downsamplePipeline && impl_->horizontalBlurPipeline
        && impl_->verticalBlurPipeline && impl_->apertureBlurPipeline && impl_->compositePipeline && impl_->encodePipeline
        && impl_->zeroScatterBuffer;
}
const char* LDBOpticsEngine::errorMessage() const { return impl_->error.c_str(); }

void LDBOpticsEngine::encode(id<MTLCommandBuffer> commandBuffer,
                             id<MTLBuffer> source,
                             id<MTLBuffer> destination,
                             uint32_t width,
                             uint32_t height,
                             const LDBOpticsParameters& parameters) {
    if (!valid()) throw std::runtime_error(impl_->error);
    LDBOpticsParameters p = parameters;
    p.imageSize = {float(width), float(height)};
    NSUInteger byteCount = NSUInteger(width) * NSUInteger(height) * sizeof(simd_float4);
    std::vector<id<MTLBuffer>> pooledBuffers;
    auto scratch = [&](NSUInteger length) -> id<MTLBuffer> {
        id<MTLBuffer> buffer = impl_->bufferPool->acquire(length);
        if (buffer) pooledBuffers.push_back(buffer);
        return buffer;
    };

    auto copySource = [&] {
        if (source == destination) return;
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit copyFromBuffer:source sourceOffset:0 toBuffer:destination destinationOffset:0 size:byteCount];
        [blit endEncoding];
    };
    if (p.effectBlend <= 0.0f) {
        copySource();
        return;
    }
    const bool noOpticalEffect =
        p.distortionK1 == 0 && p.distortionK2 == 0 && p.moustacheK3 == 0
        && p.lateralCARed == 0 && p.lateralCABlue == 0
        && p.longitudinalCA == 0
        && p.vignetteNatural == 0 && p.vignetteOptical == 0 && p.vignetteMechanical == 0
        && p.cornerSharpnessLoss == 0 && p.astigmatism == 0 && p.coma == 0
        && p.sphericalHalo == 0 && p.fieldCurvature == 0 && p.swirl == 0
        && p.radialSmear == 0 && p.tangentialSmear == 0
        && p.microContrast == 0 && p.fineDetail == 0 && p.detailEdgeFalloff == 0
        && p.sagittalDetail == 0 && p.tangentialDetail == 0
        && p.bloomEnergy == 0 && p.glareEnergy == 0 && p.transmissionColorAmount == 0
        && p.apertureResponse == 0;
    bool diagnosticActive = (p.processingFlags & LDBDiagnosticMask) != 0;
    if (noOpticalEffect && !diagnosticActive) {
        copySource();
        return;
    }
    bool linearAP1Input = p.workingColorSpace == LDBWorkingColorSpaceACEScg;
    bool scatterActive[3] = {p.bloomEnergy > 0.0f, p.glareEnergy > 0.0f, p.sphericalHalo > 0.0f};
    bool apertureActive = p.apertureResponse > 0.0f && p.apertureRadius > 0.0f;
    bool anyScatter = scatterActive[0] || scatterActive[1] || scatterActive[2];
    id<MTLBuffer> linearSource = linearAP1Input ? source
        : scratch(byteCount);
    id<MTLBuffer> direct = scratch(byteCount);
    id<MTLBuffer> highlights = impl_->zeroScatterBuffer;
    auto scatterScale = [](float radius) -> uint32_t {
        if (radius > 48.0f) return 8;
        if (radius > 20.0f) return 4;
        if (radius > 9.0f) return 2;
        return 1;
    };
    uint32_t quality = p.processingFlags & LDBProcessingQualityMask;
    auto qualityScale = [quality](uint32_t scale) -> uint32_t {
        if (quality == LDBProcessingQualityHigh) return 1;
        if (quality == LDBProcessingQualityFast) return std::min(8u, scale * 2u);
        return scale;
    };
    float bloomRadiusX = p.bloomRadius * std::max(1.0f, p.bloomHorizontalStretch);
    uint32_t bloomScale = qualityScale(scatterScale(std::max(bloomRadiusX, p.bloomRadius)));
    uint32_t glareScale = qualityScale(scatterScale(p.glareRadius));
    float haloRadius = 2.0f + std::clamp(p.sphericalHalo, 0.0f, 2.0f) * 16.0f;
    uint32_t haloScale = qualityScale(scatterScale(haloRadius));
    uint32_t bloomWidth = scatterActive[0] ? (width + bloomScale - 1) / bloomScale : 1;
    uint32_t bloomHeight = scatterActive[0] ? (height + bloomScale - 1) / bloomScale : 1;
    uint32_t glareWidth = scatterActive[1] ? (width + glareScale - 1) / glareScale : 1;
    uint32_t glareHeight = scatterActive[1] ? (height + glareScale - 1) / glareScale : 1;
    uint32_t haloWidth = scatterActive[2] ? (width + haloScale - 1) / haloScale : 1;
    uint32_t haloHeight = scatterActive[2] ? (height + haloScale - 1) / haloScale : 1;
    if (!scatterActive[0]) bloomScale = 1;
    if (!scatterActive[1]) glareScale = 1;
    if (!scatterActive[2]) haloScale = 1;
    LDBScatterParameters scatterParameters[3] = {
        {{float(bloomWidth), float(bloomHeight)}, bloomRadiusX / bloomScale,
         p.bloomRadius / bloomScale, bloomScale, p.bloomThreshold, 1, 0},
        {{float(glareWidth), float(glareHeight)}, p.glareRadius / glareScale,
         p.glareRadius / glareScale, glareScale, p.bloomThreshold, 1, 0},
        {{float(haloWidth), float(haloHeight)}, haloRadius / haloScale,
         haloRadius / haloScale, haloScale, 0.45f, 0, 0}
    };
    NSUInteger bloomBytes = NSUInteger(bloomWidth) * NSUInteger(bloomHeight) * sizeof(simd_float4);
    NSUInteger glareBytes = NSUInteger(glareWidth) * NSUInteger(glareHeight) * sizeof(simd_float4);
    NSUInteger haloBytes = NSUInteger(haloWidth) * NSUInteger(haloHeight) * sizeof(simd_float4);
    id<MTLBuffer> bloomSource = scatterActive[0] ? scratch(bloomBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> bloomTemporary = scatterActive[0] ? scratch(bloomBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> bloomScattered = scatterActive[0] ? scratch(bloomBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> glareSource = scatterActive[1] ? scratch(glareBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> glareTemporary = scatterActive[1] ? scratch(glareBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> glareScattered = scatterActive[1] ? scratch(glareBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> haloSource = scatterActive[2] ? scratch(haloBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> haloTemporary = scatterActive[2] ? scratch(haloBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> haloScattered = scatterActive[2] ? scratch(haloBytes) : impl_->zeroScatterBuffer;
    id<MTLBuffer> apertureTemporary1 = apertureActive ? scratch(byteCount) : impl_->zeroScatterBuffer;
    id<MTLBuffer> apertureTemporary2 = apertureActive ? scratch(byteCount) : impl_->zeroScatterBuffer;
    id<MTLBuffer> apertureScattered = apertureActive ? scratch(byteCount) : direct;
    id<MTLBuffer> linearResult = linearAP1Input ? destination
        : scratch(byteCount);
    if (!linearSource || !direct || !highlights || !bloomSource || !bloomTemporary || !bloomScattered
        || !glareSource || !glareTemporary || !glareScattered
        || !haloSource || !haloTemporary || !haloScattered
        || !apertureTemporary1 || !apertureTemporary2 || !apertureScattered || !linearResult)
        throw std::runtime_error("Unable to allocate Metal scratch buffers");

    MTLSize threads = MTLSizeMake(16, 16, 1);
    MTLSize groups = MTLSizeMake((width + 15) / 16, (height + 15) / 16, 1);

    id<MTLComputeCommandEncoder> encoder = nil;
    if (!linearAP1Input) {
        encoder = [commandBuffer computeCommandEncoder];
        [encoder setComputePipelineState:impl_->decodePipeline];
        [encoder setBuffer:source offset:0 atIndex:0];
        [encoder setBuffer:linearSource offset:0 atIndex:1];
        [encoder setBytes:&p length:sizeof(p) atIndex:2];
        [encoder dispatchThreadgroups:groups threadsPerThreadgroup:threads];
        [encoder endEncoding];
    }

    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->opticsPipeline];
    [encoder setBuffer:linearSource offset:0 atIndex:0];
    [encoder setBuffer:direct offset:0 atIndex:1];
    [encoder setBuffer:highlights offset:0 atIndex:2];
    [encoder setBytes:&p length:sizeof(p) atIndex:3];
    [encoder dispatchThreadgroups:groups threadsPerThreadgroup:threads];
    [encoder endEncoding];

    for (uint32_t scatterKind = 0; scatterKind < 3; ++scatterKind) {
        if (!scatterActive[scatterKind]) continue;
        LDBScatterParameters& scatter = scatterParameters[scatterKind];
        id<MTLBuffer> scatterSource = scatterKind == 0 ? bloomSource : (scatterKind == 1 ? glareSource : haloSource);
        id<MTLBuffer> temporary = scatterKind == 0 ? bloomTemporary : (scatterKind == 1 ? glareTemporary : haloTemporary);
        id<MTLBuffer> scattered = scatterKind == 0 ? bloomScattered : (scatterKind == 1 ? glareScattered : haloScattered);
        MTLSize scatterGroups = MTLSizeMake((uint32_t(scatter.imageSize.x) + 15) / 16,
                                             (uint32_t(scatter.imageSize.y) + 15) / 16, 1);
        encoder = [commandBuffer computeCommandEncoder];
        [encoder setComputePipelineState:impl_->downsamplePipeline];
        // Scatter from the geometrically processed direct image. Sampling the
        // original frame here misregisters bloom/glare/halo whenever distortion
        // is active and produces a visible secondary image near the frame edge.
        [encoder setBuffer:direct offset:0 atIndex:0];
        [encoder setBuffer:scatterSource offset:0 atIndex:1];
        [encoder setBytes:&p length:sizeof(p) atIndex:2];
        [encoder setBytes:&scatter length:sizeof(scatter) atIndex:3];
        [encoder dispatchThreadgroups:scatterGroups threadsPerThreadgroup:threads];
        [encoder endEncoding];

        encoder = [commandBuffer computeCommandEncoder];
        [encoder setComputePipelineState:impl_->horizontalBlurPipeline];
        [encoder setBuffer:scatterSource offset:0 atIndex:0];
        [encoder setBuffer:temporary offset:0 atIndex:1];
        [encoder setBytes:&scatter length:sizeof(scatter) atIndex:2];
        [encoder setBytes:&p length:sizeof(p) atIndex:3];
        [encoder dispatchThreadgroups:scatterGroups threadsPerThreadgroup:threads];
        [encoder endEncoding];

        encoder = [commandBuffer computeCommandEncoder];
        [encoder setComputePipelineState:impl_->verticalBlurPipeline];
        [encoder setBuffer:temporary offset:0 atIndex:0];
        [encoder setBuffer:scattered offset:0 atIndex:1];
        [encoder setBytes:&scatter length:sizeof(scatter) atIndex:2];
        [encoder setBytes:&p length:sizeof(p) atIndex:3];
        [encoder dispatchThreadgroups:scatterGroups threadsPerThreadgroup:threads];
        [encoder endEncoding];
    }

    if (apertureActive) {
        constexpr float pi = 3.14159265358979323846f;
        float rotation = p.apertureRotation * pi / 180.0f;
        float radius = std::clamp(p.apertureRadius, 0.0f, 24.0f);
        id<MTLBuffer> passSources[3] = {direct, apertureTemporary1, apertureTemporary2};
        id<MTLBuffer> passDestinations[3] = {apertureTemporary1, apertureTemporary2, apertureScattered};
        for(uint32_t pass=0;pass<3;++pass) {
            LDBScatterParameters aperturePass = {{float(width), float(height)}, radius, 0.0f,
                pass, std::clamp(p.apertureSoftness, 0.0f, 1.0f), std::cos(rotation), std::sin(rotation)};
            encoder = [commandBuffer computeCommandEncoder];
            [encoder setComputePipelineState:impl_->apertureBlurPipeline];
            [encoder setBuffer:passSources[pass] offset:0 atIndex:0];
            [encoder setBuffer:passDestinations[pass] offset:0 atIndex:1];
            [encoder setBytes:&aperturePass length:sizeof(aperturePass) atIndex:2];
            [encoder setBytes:&p length:sizeof(p) atIndex:3];
            [encoder dispatchThreadgroups:groups threadsPerThreadgroup:threads];
            [encoder endEncoding];
        }
    }

    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->compositePipeline];
    [encoder setBuffer:linearSource offset:0 atIndex:0];
    [encoder setBuffer:direct offset:0 atIndex:1];
    [encoder setBuffer:bloomScattered offset:0 atIndex:2];
    [encoder setBuffer:glareScattered offset:0 atIndex:3];
    [encoder setBuffer:haloScattered offset:0 atIndex:4];
    [encoder setBuffer:apertureScattered offset:0 atIndex:5];
    [encoder setBuffer:linearResult offset:0 atIndex:6];
    [encoder setBytes:&p length:sizeof(p) atIndex:7];
    [encoder setBytes:&scatterParameters[0] length:sizeof(LDBScatterParameters) atIndex:8];
    [encoder setBytes:&scatterParameters[1] length:sizeof(LDBScatterParameters) atIndex:9];
    [encoder setBytes:&scatterParameters[2] length:sizeof(LDBScatterParameters) atIndex:10];
    [encoder dispatchThreadgroups:groups threadsPerThreadgroup:threads];
    [encoder endEncoding];

    if (!linearAP1Input) {
        encoder = [commandBuffer computeCommandEncoder];
        [encoder setComputePipelineState:impl_->encodePipeline];
        [encoder setBuffer:source offset:0 atIndex:0];
        [encoder setBuffer:linearResult offset:0 atIndex:1];
        [encoder setBuffer:destination offset:0 atIndex:2];
        [encoder setBytes:&p length:sizeof(p) atIndex:3];
        [encoder dispatchThreadgroups:groups threadsPerThreadgroup:threads];
        [encoder endEncoding];
    }

    auto pool = impl_->bufferPool;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
        pool->release(pooledBuffers);
    }];
}
