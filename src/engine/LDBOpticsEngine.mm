#include "LDBResolveParameterAudit.h"
#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
#include "LDBProjectionCandidateParameters.h"
#endif
#include "LDBOpticsEngine.h"
#include <algorithm>
#include <atomic>
#include <cstring>
#include <cmath>
#include <dispatch/dispatch.h>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

struct LDBBufferPool {
  explicit LDBBufferPool(id<MTLDevice> d) : device(d) {}

  static constexpr NSUInteger kMaximumPooledBufferBytes = 32u * 1024u * 1024u;
  static constexpr NSUInteger kMaximumPoolBytes = 128u * 1024u * 1024u;

  id<MTLBuffer> acquire(NSUInteger length) {
    std::lock_guard<std::mutex> lock(mutex);
    auto &buffers = available[length];
    if (!buffers.empty()) {
      id<MTLBuffer> result = buffers.back();
      buffers.pop_back();
      cachedBytes -= result.length;
      return result;
    }
    return [device newBufferWithLength:length
                               options:MTLResourceStorageModePrivate];
  }

  void release(const std::vector<id<MTLBuffer>> &buffers) {
    std::lock_guard<std::mutex> lock(mutex);
    for (id<MTLBuffer> buffer : buffers) {
      if (buffer.length > kMaximumPooledBufferBytes ||
          cachedBytes + buffer.length > kMaximumPoolBytes)
        continue;
      auto &destination = available[buffer.length];
      if (destination.size() < 3) {
        destination.push_back(buffer);
        cachedBytes += buffer.length;
      }
    }
  }

  id<MTLDevice> device = nil;
  std::mutex mutex;
  std::unordered_map<NSUInteger, std::vector<id<MTLBuffer>>> available;
  NSUInteger cachedBytes = 0;
};

#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
struct LDBFinalFramingCache {
  id<MTLBuffer> buffer=nil;
  LDBOpticsParameters key{};
  std::atomic<bool> valid{false};
};
#endif
struct LDBOpticsEngine::Impl {
  id<MTLDevice> device = nil;
  id<MTLComputePipelineState> opticsPipeline = nil;
  id<MTLComputePipelineState> chromaticPipeline = nil;
  id<MTLComputePipelineState> packDepthPipeline = nil;
  id<MTLComputePipelineState> decodePipeline = nil;
  id<MTLComputePipelineState> downsamplePipeline = nil;
  id<MTLComputePipelineState> horizontalBlurPipeline = nil;
  id<MTLComputePipelineState> verticalBlurPipeline = nil;
  id<MTLComputePipelineState> flareReconstructionPipeline = nil;
  id<MTLComputePipelineState> flareSourceDetectionPipeline = nil;
  id<MTLComputePipelineState> apertureBlurPipeline = nil;
  id<MTLComputePipelineState> compositePipeline = nil;
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
  id<MTLComputePipelineState> finalFindPipeline=nil,finalApplyPipeline=nil;
  bool finalCacheEnabled=false,finalDirectOutput=false;
  std::shared_ptr<LDBFinalFramingCache> finalCache=std::make_shared<LDBFinalFramingCache>();
#endif
  id<MTLComputePipelineState> encodePipeline = nil;
  id<MTLBuffer> zeroScatterBuffer = nil;
  std::shared_ptr<LDBBufferPool> bufferPool;
  dispatch_semaphore_t renderGate = dispatch_semaphore_create(1);
  std::string error;
};

struct LDBRenderGateLease {
  explicit LDBRenderGateLease(dispatch_semaphore_t gate) : gate(gate) {
    dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
  }
  ~LDBRenderGateLease() {
    if (active)
      dispatch_semaphore_signal(gate);
  }
  void releaseWhenCompleted(id<MTLCommandBuffer> commandBuffer) {
    dispatch_semaphore_t retainedGate = gate;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
      dispatch_semaphore_signal(retainedGate);
    }];
    active = false;
  }
  dispatch_semaphore_t gate;
  bool active = true;
};

static id<MTLComputePipelineState> makePipeline(id<MTLDevice> device,
                                                id<MTLLibrary> library,
                                                NSString *name,
                                                std::string &errorText) {
  id<MTLFunction> function = [library newFunctionWithName:name];
  if (!function) {
    errorText = std::string("Metal function not found: ") + name.UTF8String;
    return nil;
  }
  NSError *error = nil;
  id<MTLComputePipelineState> pipeline =
      [device newComputePipelineStateWithFunction:function error:&error];
  if (!pipeline)
    errorText = error ? error.localizedDescription.UTF8String
                      : "Unable to create Metal pipeline";
  return pipeline;
}

static MTLSize threadgroupSizeForPipeline(id<MTLComputePipelineState> pipeline) {
  // Match the scheduled SIMD width and use the largest legal two-dimensional
  // group for this particular kernel. A fixed 16x16 group underfilled the
  // 32-wide SIMD groups used by Apple Silicon and ignored the fact that heavy
  // and light kernels can report different occupancy limits.
  const NSUInteger width = std::max<NSUInteger>(1, pipeline.threadExecutionWidth);
  const NSUInteger height = std::max<NSUInteger>(
      1, pipeline.maxTotalThreadsPerThreadgroup / width);
  return MTLSizeMake(width, height, 1);
}

static void dispatchImage(id<MTLComputeCommandEncoder> encoder,
                          id<MTLComputePipelineState> pipeline,
                          NSUInteger width, NSUInteger height) {
  [encoder dispatchThreads:MTLSizeMake(width, height, 1)
      threadsPerThreadgroup:threadgroupSizeForPipeline(pipeline)];
}

static void applyCaptureAndLookMappings(LDBOpticsParameters &p) {
  const float capture = std::clamp(p.captureInfluence, 0.0f, 1.0f);
  if (capture > 0.0f) {
    const float focal = std::clamp(p.captureFocalLength, 8.0f, 300.0f);
    const float gateWidth = std::clamp(p.captureGateWidth, 4.0f, 80.0f);
    const float gateHeight = std::clamp(p.captureGateHeight, 3.0f, 60.0f);
    const float gateDiagonal = std::hypot(gateWidth, gateHeight);
    const float equivalentFocal =
        focal * std::hypot(36.0f, 24.0f) / gateDiagonal;
    const float fieldScale = std::clamp(50.0f / equivalentFocal, 0.35f, 3.0f);
    const float apertureScale = std::clamp(
        2.8f / std::clamp(p.captureAperture, .7f, 32.0f), .25f, 3.0f);
    const float focusDistance =
        std::clamp(p.captureFocusDistance, .01f, 1000.0f);
    // A shallow power curve preserves useful differentiation from macro
    // distances through 10 m while the UI's maximum acts as infinity.
    const float closeScale =
        std::clamp(std::pow(3.0f / focusDistance, .35f), .35f, 3.0f);
    const float offAxis = std::lerp(1.0f, fieldScale, capture);
    const float pupil = std::lerp(1.0f, std::sqrt(apertureScale), capture);
    const float closeFocus = std::lerp(1.0f, std::sqrt(closeScale), capture);

    p.distortionK1 *= offAxis;
    p.distortionK2 *= offAxis;
    p.moustacheK3 *= offAxis;
    p.lateralCARed *= offAxis;
    p.lateralCABlue *= offAxis;
    p.cornerSharpnessLoss *= offAxis;
    p.fieldCurvature *= offAxis;
    p.astigmatism *= offAxis;
    p.radialSmear *= offAxis;
    p.tangentialSmear *= offAxis;
    p.coma *= offAxis * pupil;
    p.sphericalHalo *= pupil * closeFocus;
    p.vignetteNatural *= offAxis;
    p.vignetteOptical *= pupil;
    p.detailEdgeFalloff *= offAxis;
    p.apertureResponse *= pupil * closeFocus;
    p.longitudinalCA *= pupil * closeFocus;
    p.anamorphicDistortion *= offAxis;
    p.anamorphicAberration *= offAxis;
    p.anamorphicFlareAmount *= pupil;
  }

  const float influence = std::clamp(p.lookInfluence, 0.0f, 1.0f);
  if (influence <= 0.0f)
    return;
  const float character = std::clamp(p.lookCharacter, 0.0f, 1.0f) * influence;
  const float vintage = std::clamp(p.lookVintageBias, 0.0f, 1.0f) * influence;
  const float vintageCaricature =
      std::clamp(p.lookVintageCaricatureBias, 0.0f, 1.0f) * influence;
  const float exotic = std::clamp(p.lookExoticBias, 0.0f, 1.0f) * influence;
  const float anamorphic =
      std::clamp(p.lookAnamorphicBias, 0.0f, 1.0f) * influence;

  // Coordinated chromatic character remains deliberately restrained. The
  // opposing lateral offsets create edge colour without detached RGB copies;
  // Vintage favours soft axial colour, while Exotic adds decentered and
  // cylindrical separation through its variation/anamorphic contributions.
  p.lateralCARed += .08f * character + .16f * vintage +
                    .32f * vintageCaricature + .24f * exotic +
                    .18f * anamorphic;
  p.lateralCABlue -= .06f * character + .12f * vintage +
                     .25f * vintageCaricature + .20f * exotic +
                     .15f * anamorphic;
  p.longitudinalCA += .08f * vintage + .22f * vintageCaricature +
                      .12f * exotic + .08f * anamorphic;

  p.cornerSharpnessLoss +=
      .34f * character + .28f * vintage + .55f * vintageCaricature;
  p.fieldCurvature += .12f * character + .22f * vintageCaricature;
  p.astigmatism += .07f * character + .16f * vintageCaricature;
  p.coma += .14f * vintageCaricature;
  p.microContrast -=
      .20f * character + .18f * vintage + .34f * vintageCaricature;
  p.fineDetail -= .15f * character + .20f * vintage + .38f * vintageCaricature;
  p.vignetteOptical +=
      .05f * character + .18f * vintage + .30f * vintageCaricature;
  p.bloomEnergy += .06f * character + .10f * vintage + .22f * vintageCaricature;
  p.glareEnergy +=
      .035f * character + .07f * vintage + .13f * vintageCaricature;
  p.sphericalHalo +=
      .08f * character + .18f * vintage + .30f * vintageCaricature;
  p.transmissionContrast -= .10f * vintage + .24f * vintageCaricature;
  p.transmissionHighlightSoftness += .18f * vintage + .38f * vintageCaricature;
  p.transmissionColorAmount = std::clamp(
      p.transmissionColorAmount + .12f * vintage + .28f * vintageCaricature,
      0.0f, 1.0f);
  const float vintageWarmth =
      std::clamp(.35f * vintage + .65f * vintageCaricature, 0.0f, 1.0f);
  p.transmissionColor +=
      (simd_float3{1.0f, .88f, .70f} - p.transmissionColor) * vintageWarmth;

  p.fieldCurvature += .30f * exotic;
  p.astigmatism += .28f * exotic;
  p.radialSmear += .12f * exotic;
  p.tangentialSmear += .20f * exotic;
  p.coma += .22f * exotic;
  p.swirl += .025f * exotic;
  p.apertureCatEye += .25f * exotic;
  p.anamorphicAberration += .20f * exotic;
  p.anamorphicFlareAmount += .08f * exotic;
  p.variationAmount = std::clamp(p.variationAmount + .35f * exotic, 0.0f, 1.0f);
  p.variationFieldAsymmetry += .25f * exotic;
  p.variationPupilIrregularity += .20f * exotic;
  p.variationChromaticAsymmetry += .18f * exotic;

  // A visibly stylised classic 2x anamorphic macro. This shapes the optical
  // field rather than desqueezing the image, and keeps direct controls
  // independently editable on top.
  p.anamorphicSqueeze *= std::lerp(1.0f, 2.0f, anamorphic);
  p.anamorphicAberration += .42f * anamorphic;
  p.anamorphicFlareAmount += .85f * anamorphic;
  p.anamorphicFlareRadius += 150.0f * anamorphic;
  p.anamorphicFlareThreshold =
      std::lerp(p.anamorphicFlareThreshold, .65f, .65f * anamorphic);
  p.anamorphicFlareColor +=
      (simd_float3{.24f, .42f, 1.0f} - p.anamorphicFlareColor) *
      (.7f * anamorphic);
  p.bloomEnergy += .11f * anamorphic;
  p.bloomHorizontalStretch =
      std::max(p.bloomHorizontalStretch, 1.0f + 8.0f * anamorphic);
  p.glareEnergy += .08f * anamorphic;
  p.fieldCurvature += .08f * anamorphic;
  p.astigmatism += .14f * anamorphic;
  p.tangentialSmear += .10f * anamorphic;
  p.apertureCatEye += .28f * anamorphic;
  p.apertureAspect *= std::lerp(1.0f, 2.4f, anamorphic);
}

LDBOpticsEngine::LDBOpticsEngine(id<MTLDevice> device, NSURL *metallibURL)
    : impl_(new Impl) {
  impl_->device = device;
  impl_->bufferPool = std::make_shared<LDBBufferPool>(device);
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithURL:metallibURL error:&error];
  if (!library) {
    impl_->error = error ? error.localizedDescription.UTF8String
                         : "Unable to load Metal library";
    return;
  }
  impl_->opticsPipeline =
      makePipeline(device, library, @"ldbOpticsMain", impl_->error);
  impl_->chromaticPipeline =
      makePipeline(device, library, @"ldbChromaticPSF", impl_->error);
  impl_->packDepthPipeline =
      makePipeline(device, library, @"ldbPackDepthLuminance", impl_->error);
  impl_->decodePipeline =
      makePipeline(device, library, @"ldbDecodeToLinearAP1", impl_->error);
  impl_->downsamplePipeline =
      makePipeline(device, library, @"ldbDownsampleHighlights", impl_->error);
  impl_->horizontalBlurPipeline =
      makePipeline(device, library, @"ldbBlurHorizontal", impl_->error);
  impl_->verticalBlurPipeline =
      makePipeline(device, library, @"ldbBlurVertical", impl_->error);
  impl_->flareReconstructionPipeline =
      makePipeline(device, library, @"ldbReconstructAnamorphicFlare", impl_->error);
  impl_->flareSourceDetectionPipeline =
      makePipeline(device, library, @"ldbDetectFlareSources", impl_->error);
  impl_->apertureBlurPipeline =
      makePipeline(device, library, @"ldbBlurAperture", impl_->error);
  impl_->compositePipeline =
      makePipeline(device, library, @"ldbComposite", impl_->error);
  impl_->encodePipeline =
      makePipeline(device, library, @"ldbEncodeFromLinearAP1", impl_->error);
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
  impl_->finalFindPipeline=makePipeline(device,library,@"ldbFindFinalFraming",impl_->error);
  impl_->finalApplyPipeline=makePipeline(device,library,@"ldbApplyFinalFraming",impl_->error);
  impl_->finalCacheEnabled=[library newFunctionWithName:@"ldbFinalFramingCacheVersion"]!=nil;
  impl_->finalDirectOutput=[library newFunctionWithName:@"ldbFinalFramingDirectOutputVersion"]!=nil;
#endif
  simd_float4 zero = {0, 0, 0, 0};
  impl_->zeroScatterBuffer =
      [device newBufferWithBytes:&zero
                          length:sizeof(zero)
                         options:MTLResourceStorageModeShared];
}

LDBOpticsEngine::~LDBOpticsEngine() { delete impl_; }
bool LDBOpticsEngine::valid() const {
  return impl_->decodePipeline && impl_->opticsPipeline &&
         impl_->packDepthPipeline &&
         impl_->downsamplePipeline && impl_->horizontalBlurPipeline &&
         impl_->verticalBlurPipeline && impl_->flareReconstructionPipeline &&
         impl_->flareSourceDetectionPipeline &&
         impl_->apertureBlurPipeline &&
         impl_->compositePipeline && impl_->encodePipeline &&
         impl_->zeroScatterBuffer;
}
const char *LDBOpticsEngine::errorMessage() const {
  return impl_->error.c_str();
}

void LDBOpticsEngine::encode(id<MTLCommandBuffer> commandBuffer,
                             id<MTLBuffer> source, id<MTLBuffer> destination,
                             uint32_t width, uint32_t height,
                             const LDBOpticsParameters &parameters,
                             id<MTLBuffer> depthSource) {
  if (!valid())
    throw std::runtime_error(impl_->error);
  LDBOpticsParameters p = parameters;
  p.imageSize = {float(width), float(height)};
  applyCaptureAndLookMappings(p);
  // Capture and Look can add pixel-radius contributions, so host render
  // scaling must happen only after those macros have resolved.
  #if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
  // The actual render height already incorporates host/proxy render scaling.
  // Reference units are pixels in a 960 x 540 render, independent of host scale.
  if(!(p.processingFlags & (1u<<30)))p.renderPixelScale = float(height) / 540.0f;
#endif
  LDBApplyRenderPixelScale(p);
#ifdef LDB_RESOLVE_PARAMETER_AUDIT
  LDBRecordResolveParameters("engine-effective",p,width,height);
#endif
  NSUInteger byteCount =
      NSUInteger(width) * NSUInteger(height) * sizeof(simd_float4);
  std::vector<id<MTLBuffer>> pooledBuffers;
  auto scratch = [&](NSUInteger length) -> id<MTLBuffer> {
    id<MTLBuffer> buffer = impl_->bufferPool->acquire(length);
    if (buffer)
      pooledBuffers.push_back(buffer);
    return buffer;
  };

  id<MTLBuffer> finishedOutput=destination;
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
  if(impl_->finalDirectOutput && (p.finalFramingMode!=0 || p.finalFramingZoom!=100)) {
    finishedOutput=scratch(byteCount);
    if(!finishedOutput)throw std::runtime_error("Unable to allocate finished crop input");
  }
#endif
  id<MTLBuffer> opticalSource = source;
  if (depthSource && p.depthMode > 0u) {
    opticalSource = scratch(byteCount);
    if (!opticalSource)
      throw std::runtime_error("Unable to allocate depth-carrier buffer");
    id<MTLComputeCommandEncoder> depthEncoder =
        [commandBuffer computeCommandEncoder];
    [depthEncoder setComputePipelineState:impl_->packDepthPipeline];
    [depthEncoder setBuffer:source offset:0 atIndex:0];
    [depthEncoder setBuffer:depthSource offset:0 atIndex:1];
    [depthEncoder setBuffer:opticalSource offset:0 atIndex:2];
    [depthEncoder setBytes:&p length:sizeof(p) atIndex:3];
    dispatchImage(depthEncoder, impl_->packDepthPipeline, width, height);
    [depthEncoder endEncoding];
    // All downstream depth sampling reads the packed alpha carrier.
    p.depthChannel = 4u;
  }

  auto copySource = [&] {
    if (source == destination)
      return;
    id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
    [blit copyFromBuffer:source
             sourceOffset:0
                 toBuffer:destination
        destinationOffset:0
                     size:byteCount];
    [blit endEncoding];
  };
  if (p.effectBlend <= 0.0f
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
      && p.finalFramingMode==0 && p.finalFramingZoom==100
#endif
      ) {
    copySource();
    return;
  }
  const bool noOpticalEffect =
      p.distortionK1 == 0 && p.distortionK2 == 0 && p.moustacheK3 == 0 &&
      p.geometryFieldAmount == 0 && p.peripheralStretch == 0 &&
      p.peripheralWarp == 0 &&
      p.lateralCARed == 0 && p.lateralCABlue == 0 && p.longitudinalCA == 0 &&
      p.vignetteNatural == 0 && p.vignetteOptical == 0 &&
      p.vignetteMechanical == 0 && p.cornerSharpnessLoss == 0 &&
      p.astigmatism == 0 && p.coma == 0 && p.sphericalHalo == 0 &&
      p.fieldCurvature == 0 && p.swirl == 0 && p.radialSmear == 0 &&
      p.tangentialSmear == 0 && p.microContrast == 0 && p.fineDetail == 0 &&
      p.detailEdgeFalloff == 0 && p.sagittalDetail == 0 &&
      p.tangentialDetail == 0 && p.bloomEnergy == 0 && p.glareEnergy == 0 &&
      p.transmissionColorAmount == 0 && p.apertureResponse == 0 &&
      p.fieldCenter.x == .5f && p.fieldCenter.y == .5f &&
      p.fieldAspect == 1.0f && p.fieldRotation == 0.0f &&
      p.transmissionDensity == 0.0f && p.transmissionContrast == 0.0f &&
      p.transmissionHighlightSoftness == 0.0f &&
      p.anamorphicDistortion == 0.0f && p.anamorphicAberration == 0.0f &&
      p.anamorphicFlareAmount == 0.0f && p.variationAmount == 0.0f &&
      p.frontHaze == 0.0f && p.cleaningMarks == 0.0f &&
      p.scratchAmount == 0.0f && p.coatingWear == 0.0f &&
      p.internalDirtAmount == 0.0f &&
      p.refractiveIrregularity == 0.0f && p.prismAmount == 0.0f;
  bool diagnosticActive = (p.processingFlags & LDBDiagnosticMask) != 0;
  if (noOpticalEffect && !diagnosticActive
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
      && p.finalFramingMode==0 && p.finalFramingZoom==100
#endif
#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
      && !LDBProjectionCandidateActive(p)
#endif
      ) {
    copySource();
    return;
  }
  // Resolve can request new renders faster than a large aperture/scatter graph
  // completes while parameters change. Keep one Lens Debaser graph in flight
  // per Metal device so those graphs cannot multiply unified-memory pressure.
  LDBRenderGateLease renderLease(impl_->renderGate);
  bool linearAP1Input = p.workingColorSpace == LDBWorkingColorSpaceACEScg;
  const bool wearScatterActive = p.frontHaze > 0.0f || p.cleaningMarks > 0.0f ||
                                 p.scratchAmount > 0.0f || p.coatingWear > 0.0f;
  const bool internalScatterActive =
      p.internalDirtAmount > 0.0f && p.internalDirtScatter > 0.0f;
  const bool opticalScatterActive = wearScatterActive || internalScatterActive;
  bool scatterActive[5] = {p.bloomEnergy > 0.0f,
                           p.glareEnergy > 0.0f,
                           p.sphericalHalo > 0.0f,
                           p.anamorphicFlareAmount > 0.0f,
                           opticalScatterActive};
  bool apertureActive = p.apertureResponse > 0.0f && p.apertureRadius > 0.0f;
  bool anyScatter = scatterActive[0] || scatterActive[1] || scatterActive[2] ||
                    scatterActive[3] || scatterActive[4];
  const bool chromaticActive =
      impl_->chromaticPipeline &&
      (p.lateralCARed != 0.0f || p.lateralCABlue != 0.0f ||
       p.anamorphicAberration != 0.0f ||
       (p.refractiveIrregularity != 0.0f && p.refractiveDispersion != 0.0f) ||
       (p.prismAmount != 0.0f && p.prismDispersion != 0.0f) ||
       (p.variationAmount != 0.0f &&
        p.variationChromaticAsymmetry != 0.0f));
  id<MTLBuffer> linearSource =
      linearAP1Input ? opticalSource : scratch(byteCount);
  id<MTLBuffer> direct = scratch(byteCount);
  id<MTLBuffer> achromaticDirect = chromaticActive
      ? scratch(byteCount) : direct;
  auto scatterScale = [](float radius) -> uint32_t {
    if (radius > 48.0f)
      return 8;
    if (radius > 20.0f)
      return 4;
    if (radius > 9.0f)
      return 2;
    return 1;
  };
  // Scatter buffers use one stable, high-quality sizing policy. Runtime
  // switching of allocation geometry is intentionally unsupported.
  // Resolve may have several parameter-change renders in flight. Bounding the
  // aggregate scratch footprint is essential on unified-memory Apple Silicon:
  // four full-resolution float scatter families would otherwise exceed 1.5 GiB
  // at UHD before direct, aperture, colour-space and host buffers are counted.
  uint32_t activeScatterCount = 0;
  for (bool active : scatterActive)
    activeScatterCount += active ? 1u : 0u;
  uint32_t memoryScale = 1;
  constexpr NSUInteger maximumScatterScratchBytes = 192u * 1024u * 1024u;
  while (activeScatterCount > 0 && memoryScale < 8) {
    const NSUInteger scaledPixels =
        NSUInteger((width + memoryScale - 1) / memoryScale) *
        NSUInteger((height + memoryScale - 1) / memoryScale);
    const NSUInteger estimatedBytes = scaledPixels * sizeof(simd_float4) * 3u *
                                      NSUInteger(activeScatterCount);
    if (estimatedBytes <= maximumScatterScratchBytes)
      break;
    memoryScale *= 2;
  }
  const float pixelScale = std::max(p.renderPixelScale, 0.0001f);
  const float wearRadius = wearScatterActive
      ? (8.0f + std::clamp(p.damageScale, .25f, 4.0f) * 8.0f) * pixelScale
      : 0.0f;
  const float internalRadius = internalScatterActive
      ? (12.0f + std::clamp(p.internalDirtScatter, 0.0f, 2.0f) * 18.0f) * pixelScale
      : 0.0f;
  const float opticalScatterRadius = std::max(wearRadius, internalRadius);
  const float effectiveBloomRadius = p.bloomRadius;
  float bloomRadiusX = effectiveBloomRadius *
                       std::max(1.0f, p.bloomHorizontalStretch);
  uint32_t bloomScale = std::max(
      memoryScale,
      scatterScale(std::max(bloomRadiusX, effectiveBloomRadius)));
  uint32_t opticalScatterScale =
      std::max(memoryScale, scatterScale(opticalScatterRadius));
  // Internal-element diffusion is often judged from very small practicals.
  // Radius-based quarter-resolution processing turned those weak sources into
  // visible bilinear blocks, while full-resolution reconstruction made the
  // 1080p path roughly five times slower.  Cap this isolated family at 2x:
  // enough samples to remove the former 4x lattice without sacrificing the
  // responsive operating target. The aggregate memory guard may still select
  // a coarser scale for very large frames or concurrent scatter families.
  if (internalScatterActive && !wearScatterActive)
    opticalScatterScale = std::max(memoryScale, 2u);
  uint32_t glareScale =
      std::max(memoryScale, scatterScale(p.glareRadius));
  // Broad glare still needs a smoothly circular footprint around compact
  // practicals. At ordinary cinematic radii an eighth-resolution source can
  // expose its reconstruction cell as a rounded square. Keep those cases at
  // quarter resolution; reserve 8x for genuinely long glare fields.
  if (p.glareRadius <= 160.0f)
    glareScale = std::max(memoryScale, std::min(glareScale, 4u));
  float haloRadius =
      (2.0f + std::clamp(p.sphericalHalo, 0.0f, 2.0f) * 16.0f) * pixelScale;
  uint32_t haloScale =
      std::max(memoryScale, scatterScale(haloRadius));
  // Long anamorphic streaks can span most of a 2K/4K gate.  The former
  // 400-pixel ceiling forced physically long flares into a short glow patch.
  // Scatter processing is already downsampled for radii above 48 pixels, so
  // extending the optical reach does not allocate a larger working image.
  float flareRadius = std::clamp(p.anamorphicFlareRadius, 0.0f, 2400.0f
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
      * ((p.processingFlags & (1u<<30))?1.0f:pixelScale)
#endif
    );
  uint32_t flareScale =
      std::max(memoryScale, scatterScale(flareRadius));
  uint32_t bloomWidth =
      scatterActive[0] ? (width + bloomScale - 1) / bloomScale : 1;
  uint32_t bloomHeight =
      scatterActive[0] ? (height + bloomScale - 1) / bloomScale : 1;
  uint32_t glareWidth =
      scatterActive[1] ? (width + glareScale - 1) / glareScale : 1;
  uint32_t glareHeight =
      scatterActive[1] ? (height + glareScale - 1) / glareScale : 1;
  uint32_t haloWidth =
      scatterActive[2] ? (width + haloScale - 1) / haloScale : 1;
  uint32_t haloHeight =
      scatterActive[2] ? (height + haloScale - 1) / haloScale : 1;
  uint32_t flareWidth =
      scatterActive[3] ? (width + flareScale - 1) / flareScale : 1;
  uint32_t flareHeight =
      scatterActive[3] ? (height + flareScale - 1) / flareScale : 1;
  uint32_t opticalScatterWidth =
      scatterActive[4] ? (width + opticalScatterScale - 1) / opticalScatterScale : 1;
  uint32_t opticalScatterHeight =
      scatterActive[4] ? (height + opticalScatterScale - 1) / opticalScatterScale : 1;
  if (!scatterActive[0])
    bloomScale = 1;
  if (!scatterActive[1])
    glareScale = 1;
  if (!scatterActive[2])
    haloScale = 1;
  if (!scatterActive[3])
    flareScale = 1;
  if (!scatterActive[4])
    opticalScatterScale = 1;
  LDBScatterParameters scatterParameters[5] = {
      {{float(bloomWidth), float(bloomHeight)},
       bloomRadiusX / bloomScale,
       effectiveBloomRadius / bloomScale,
       bloomScale,
       p.bloomThreshold,
       1,
       0},
      {{float(glareWidth), float(glareHeight)},
       p.glareRadius / glareScale,
       p.glareRadius / glareScale,
       glareScale,
       p.glareThreshold,
       1,
       1},
      {{float(haloWidth), float(haloHeight)},
       haloRadius / haloScale,
       haloRadius / haloScale,
       haloScale,
       0.45f,
       2,
       0},
      {{float(flareWidth), float(flareHeight)},
       flareRadius / flareScale,
       std::max(1.0f, flareRadius * .018f *
                          std::clamp(p.anamorphicFlareThickness, .1f, 4.0f)) /
           flareScale,
       flareScale,
       std::clamp(p.anamorphicFlareThreshold, 0.0f, 16.0f),
       3,
       3},
      {{float(opticalScatterWidth), float(opticalScatterHeight)},
       opticalScatterRadius / opticalScatterScale,
       opticalScatterRadius / opticalScatterScale,
       opticalScatterScale,
       // Internal residue responds to broad illumination; front wear remains
       // highlight-led. This source is deliberately independent of Bloom.
       internalScatterActive ? .18f : .55f,
       1,
       0}};
  NSUInteger bloomBytes =
      NSUInteger(bloomWidth) * NSUInteger(bloomHeight) * sizeof(simd_float4);
  NSUInteger glareBytes =
      NSUInteger(glareWidth) * NSUInteger(glareHeight) * sizeof(simd_float4);
  NSUInteger haloBytes =
      NSUInteger(haloWidth) * NSUInteger(haloHeight) * sizeof(simd_float4);
  NSUInteger flareBytes =
      NSUInteger(flareWidth) * NSUInteger(flareHeight) * sizeof(simd_float4);
  NSUInteger opticalScatterBytes = NSUInteger(opticalScatterWidth) *
      NSUInteger(opticalScatterHeight) * sizeof(simd_float4);
  id<MTLBuffer> bloomSource =
      scatterActive[0] ? scratch(bloomBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> bloomTemporary =
      scatterActive[0] ? scratch(bloomBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> bloomScattered =
      scatterActive[0] ? scratch(bloomBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> glareSource =
      scatterActive[1] ? scratch(glareBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> glareTemporary =
      scatterActive[1] ? scratch(glareBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> glareScattered =
      scatterActive[1] ? scratch(glareBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> haloSource =
      scatterActive[2] ? scratch(haloBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> haloTemporary =
      scatterActive[2] ? scratch(haloBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> haloScattered =
      scatterActive[2] ? scratch(haloBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> flareSource =
      scatterActive[3] ? scratch(flareBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> flareTemporary =
      scatterActive[3] ? scratch(flareBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> flareScattered =
      scatterActive[3] ? scratch(flareBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> flareReconstructed =
      scatterActive[3] ? scratch(flareBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> opticalScatterSource =
      scatterActive[4] ? scratch(opticalScatterBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> opticalScatterTemporary =
      scatterActive[4] ? scratch(opticalScatterBytes) : impl_->zeroScatterBuffer;
  id<MTLBuffer> opticalScatterScattered =
      scatterActive[4] ? scratch(opticalScatterBytes) : impl_->zeroScatterBuffer;
  constexpr uint32_t maximumFlareSources = 4u;
  id<MTLBuffer> flareSources = scatterActive[3]
      ? scratch(sizeof(LDBFlareSource) * maximumFlareSources)
      : impl_->zeroScatterBuffer;
  id<MTLBuffer> apertureTemporary1 =
      apertureActive ? scratch(byteCount) : impl_->zeroScatterBuffer;
  id<MTLBuffer> apertureTemporary2 =
      apertureActive ? scratch(byteCount) : impl_->zeroScatterBuffer;
  // Three aperture passes ping-pong through two buffers. Pass three returns to
  // Temporary1, which remains alive for the composite pass.
  id<MTLBuffer> apertureScattered =
      apertureActive ? apertureTemporary1 : direct;
  id<MTLBuffer> linearResult =
      linearAP1Input ? finishedOutput : scratch(byteCount);
  if (!linearSource || !direct || !achromaticDirect || !bloomSource ||
      !bloomTemporary || !bloomScattered || !glareSource || !glareTemporary ||
      !glareScattered || !haloSource || !haloTemporary || !haloScattered ||
      !flareSource || !flareTemporary || !flareScattered || !flareReconstructed ||
      !opticalScatterSource || !opticalScatterTemporary || !opticalScatterScattered ||
      !flareSources ||
      !apertureTemporary1 || !apertureTemporary2 || !apertureScattered ||
      !linearResult)
    throw std::runtime_error("Unable to allocate Metal scratch buffers");

  id<MTLComputeCommandEncoder> encoder = nil;
  if (!linearAP1Input) {
    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->decodePipeline];
    [encoder setBuffer:opticalSource offset:0 atIndex:0];
    [encoder setBuffer:linearSource offset:0 atIndex:1];
    [encoder setBytes:&p length:sizeof(p) atIndex:2];
    dispatchImage(encoder, impl_->decodePipeline, width, height);
    [encoder endEncoding];
  }

  encoder = [commandBuffer computeCommandEncoder];
  [encoder setComputePipelineState:impl_->opticsPipeline];
  [encoder setBuffer:linearSource offset:0 atIndex:0];
  [encoder setBuffer:achromaticDirect offset:0 atIndex:1];
  [encoder setBytes:&p length:sizeof(p) atIndex:2];
  dispatchImage(encoder, impl_->opticsPipeline, width, height);
  [encoder endEncoding];

  if (chromaticActive) {
    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->chromaticPipeline];
    [encoder setBuffer:achromaticDirect offset:0 atIndex:0];
    [encoder setBuffer:direct offset:0 atIndex:1];
    [encoder setBytes:&p length:sizeof(p) atIndex:2];
    dispatchImage(encoder, impl_->chromaticPipeline, width, height);
    [encoder endEncoding];
  }

  for (uint32_t scatterKind = 0; scatterKind < 5; ++scatterKind) {
    if (!scatterActive[scatterKind])
      continue;
    LDBScatterParameters &scatter = scatterParameters[scatterKind];
    id<MTLBuffer> scatterSource =
        scatterKind == 0
            ? bloomSource
            : (scatterKind == 1
                   ? glareSource
                   : (scatterKind == 2 ? haloSource
                      : (scatterKind == 3 ? flareSource : opticalScatterSource)));
    id<MTLBuffer> temporary =
        scatterKind == 0
            ? bloomTemporary
            : (scatterKind == 1
                   ? glareTemporary
                   : (scatterKind == 2 ? haloTemporary
                      : (scatterKind == 3 ? flareTemporary : opticalScatterTemporary)));
    id<MTLBuffer> scattered =
        scatterKind == 0
            ? bloomScattered
            : (scatterKind == 1
                   ? glareScattered
                   : (scatterKind == 2 ? haloScattered
                      : (scatterKind == 3 ? flareScattered : opticalScatterScattered)));
    const uint32_t scatterWidth = uint32_t(scatter.imageSize.x);
    const uint32_t scatterHeight = uint32_t(scatter.imageSize.y);
    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->downsamplePipeline];
    // Scatter from the geometrically processed direct image. Sampling the
    // original frame here misregisters bloom/glare/halo whenever distortion
    // is active and produces a visible secondary image near the frame edge.
    [encoder setBuffer:direct offset:0 atIndex:0];
    [encoder setBuffer:scatterSource offset:0 atIndex:1];
    [encoder setBytes:&p length:sizeof(p) atIndex:2];
    [encoder setBytes:&scatter length:sizeof(scatter) atIndex:3];
    dispatchImage(encoder, impl_->downsamplePipeline,
                  scatterWidth, scatterHeight);
    [encoder endEncoding];

    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->horizontalBlurPipeline];
    [encoder setBuffer:scatterSource offset:0 atIndex:0];
    [encoder setBuffer:temporary offset:0 atIndex:1];
    [encoder setBytes:&scatter length:sizeof(scatter) atIndex:2];
    [encoder setBytes:&p length:sizeof(p) atIndex:3];
    dispatchImage(encoder, impl_->horizontalBlurPipeline,
                  scatterWidth, scatterHeight);
    [encoder endEncoding];

    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->verticalBlurPipeline];
    [encoder setBuffer:temporary offset:0 atIndex:0];
    [encoder setBuffer:scattered offset:0 atIndex:1];
    [encoder setBytes:&scatter length:sizeof(scatter) atIndex:2];
    [encoder setBytes:&p length:sizeof(p) atIndex:3];
    dispatchImage(encoder, impl_->verticalBlurPipeline,
                  scatterWidth, scatterHeight);
    [encoder endEncoding];
  }

  if (scatterActive[3]) {
    const LDBScatterParameters &flareScatter = scatterParameters[3];
    const uint32_t flareWidth = uint32_t(flareScatter.imageSize.x);
    const uint32_t flareHeight = uint32_t(flareScatter.imageSize.y);
    // A tiny deterministic reduction identifies coherent practical sources.
    // The reduced flare buffer is used only for detection; shaped elements are
    // evaluated analytically at full output resolution in the composite pass.
    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->flareSourceDetectionPipeline];
    [encoder setBuffer:flareSource offset:0 atIndex:0];
    [encoder setBuffer:flareSources offset:0 atIndex:1];
    [encoder setBytes:&flareScatter length:sizeof(flareScatter) atIndex:2];
    [encoder dispatchThreads:MTLSizeMake(1, 1, 1)
       threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
    [encoder endEncoding];

    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->flareReconstructionPipeline];
    [encoder setBuffer:flareSource offset:0 atIndex:0];
    [encoder setBuffer:flareScattered offset:0 atIndex:1];
    [encoder setBuffer:flareReconstructed offset:0 atIndex:2];
    [encoder setBytes:&p length:sizeof(p) atIndex:3];
    [encoder setBytes:&flareScatter length:sizeof(flareScatter) atIndex:4];
    dispatchImage(encoder, impl_->flareReconstructionPipeline,
                  flareWidth, flareHeight);
    [encoder endEncoding];
  }

  if (apertureActive) {
    constexpr float pi = 3.14159265358979323846f;
    float rotation = p.apertureRotation * pi / 180.0f;
    float radius = std::clamp(p.apertureRadius, 0.0f, 48.0f
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
      * ((p.processingFlags & (1u<<30))?1.0f:pixelScale)
#endif
    );
    id<MTLBuffer> passSources[3] = {direct, apertureTemporary1,
                                    apertureTemporary2};
    id<MTLBuffer> passDestinations[3] = {apertureTemporary1, apertureTemporary2,
                                         apertureTemporary1};
    for (uint32_t pass = 0; pass < 3; ++pass) {
      LDBScatterParameters aperturePass = {
          {float(width), float(height)},
          radius,
          0.0f,
          pass,
          std::clamp(p.apertureSoftness, 0.0f, 1.0f),
          std::cos(rotation),
          std::sin(rotation)};
      encoder = [commandBuffer computeCommandEncoder];
      [encoder setComputePipelineState:impl_->apertureBlurPipeline];
      [encoder setBuffer:passSources[pass] offset:0 atIndex:0];
      [encoder setBuffer:passDestinations[pass] offset:0 atIndex:1];
      [encoder setBytes:&aperturePass length:sizeof(aperturePass) atIndex:2];
      [encoder setBytes:&p length:sizeof(p) atIndex:3];
      dispatchImage(encoder, impl_->apertureBlurPipeline, width, height);
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
  [encoder setBuffer:flareReconstructed offset:0 atIndex:6];
  [encoder setBuffer:linearResult offset:0 atIndex:7];
  [encoder setBytes:&p length:sizeof(p) atIndex:8];
  [encoder setBytes:&scatterParameters[0]
             length:sizeof(LDBScatterParameters)
            atIndex:9];
  [encoder setBytes:&scatterParameters[1]
             length:sizeof(LDBScatterParameters)
            atIndex:10];
  [encoder setBytes:&scatterParameters[2]
             length:sizeof(LDBScatterParameters)
            atIndex:11];
  [encoder setBytes:&scatterParameters[3]
             length:sizeof(LDBScatterParameters)
            atIndex:12];
  [encoder setBuffer:flareSources offset:0 atIndex:13];
  [encoder setBuffer:opticalScatterScattered offset:0 atIndex:14];
  [encoder setBytes:&scatterParameters[4]
             length:sizeof(LDBScatterParameters)
            atIndex:15];
  dispatchImage(encoder, impl_->compositePipeline, width, height);
  [encoder endEncoding];

  if (!linearAP1Input) {
    encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:impl_->encodePipeline];
    [encoder setBuffer:source offset:0 atIndex:0];
    [encoder setBuffer:linearResult offset:0 atIndex:1];
    [encoder setBuffer:finishedOutput offset:0 atIndex:2];
    [encoder setBytes:&p length:sizeof(p) atIndex:3];
    dispatchImage(encoder, impl_->encodePipeline, width, height);
    [encoder endEncoding];
  }

#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
  if(p.finalFramingMode!=0 || p.finalFramingZoom!=100) {
    if(!impl_->finalFindPipeline||!impl_->finalApplyPipeline)throw std::runtime_error("Final framing kernels unavailable");
    auto completed=impl_->finalDirectOutput?finishedOutput:scratch(byteCount);
    auto cache=impl_->finalCache;
    bool reuse=false;
    id<MTLBuffer> framing=nil;
    if(impl_->finalCacheEnabled) {
      if(!cache->buffer)cache->buffer=[impl_->device newBufferWithLength:sizeof(simd_float4) options:MTLResourceStorageModePrivate];
      framing=cache->buffer;
      // The engine render gate serializes command completion and cache access.
      // Full effective parameter packet is conservative: any settings change
      // invalidates, independent of image contents. Failed commands never cache.
      reuse=cache->valid.load() && std::memcmp(&cache->key,&p,sizeof(p))==0;
      if(!reuse){cache->valid.store(false);cache->key=p;}
    } else framing=scratch(sizeof(simd_float4));
    if(!completed||!framing)throw std::runtime_error("Unable to allocate final framing buffers");
    if(!impl_->finalDirectOutput) {
      auto blit=[commandBuffer blitCommandEncoder];
      [blit copyFromBuffer:destination sourceOffset:0 toBuffer:completed destinationOffset:0 size:byteCount];[blit endEncoding];
    }
    id<MTLComputeCommandEncoder> finalEncoder=nil;
    if(!reuse) {
      finalEncoder=[commandBuffer computeCommandEncoder];
      [finalEncoder setComputePipelineState:impl_->finalFindPipeline];
      [finalEncoder setBytes:&p length:sizeof(p) atIndex:0];[finalEncoder setBuffer:framing offset:0 atIndex:1];
      [finalEncoder dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(256,1,1)];[finalEncoder endEncoding];
      if(impl_->finalCacheEnabled)[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb){cache->valid.store(cb.status==MTLCommandBufferStatusCompleted);}];
    }
    finalEncoder=[commandBuffer computeCommandEncoder];[finalEncoder setComputePipelineState:impl_->finalApplyPipeline];
    [finalEncoder setBuffer:completed offset:0 atIndex:0];[finalEncoder setBuffer:destination offset:0 atIndex:1];
    [finalEncoder setBytes:&p length:sizeof(p) atIndex:2];[finalEncoder setBuffer:framing offset:0 atIndex:3];
    if(impl_->finalDirectOutput)[finalEncoder dispatchThreads:MTLSizeMake(width,height,1) threadsPerThreadgroup:MTLSizeMake(32,8,1)];
    else dispatchImage(finalEncoder,impl_->finalApplyPipeline,width,height);
    [finalEncoder endEncoding];
  }
#endif
  auto pool = impl_->bufferPool;
  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
    pool->release(pooledBuffers);
  }];
  renderLease.releaseWhenCompleted(commandBuffer);
}
