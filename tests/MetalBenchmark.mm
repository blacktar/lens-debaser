#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "LDBOpticsEngine.h"

struct Result { double gpuMs = 0; double wallMs = 0; };

static Result benchmark(const char* name, LDBOpticsEngine& engine, id<MTLDevice> device,
                        id<MTLCommandQueue> queue, id<MTLBuffer> source, id<MTLBuffer> destination,
                        uint32_t width, uint32_t height, const LDBOpticsParameters& p, int frames) {
    Result result;
    for (int i = -1; i < frames; ++i) {
        @autoreleasepool {
            auto begin = std::chrono::steady_clock::now();
            id<MTLCommandBuffer> command = [queue commandBuffer];
            engine.encode(command, source, destination, width, height, p);
            [command commit];
            [command waitUntilCompleted];
            auto end = std::chrono::steady_clock::now();
            if (command.status != MTLCommandBufferStatusCompleted) {
                std::fprintf(stderr, "FAIL: benchmark command failed\n");
                std::exit(2);
            }
            if (i >= 0) {
                result.wallMs += std::chrono::duration<double, std::milli>(end - begin).count();
                result.gpuMs += (command.GPUEndTime - command.GPUStartTime) * 1000.0;
            }
        }
    }
    result.wallMs /= frames; result.gpuMs /= frames;
    std::printf("%-12s GPU %7.3f ms  wall %7.3f ms  (%d frames, %ux%u)\n",
                name, result.gpuMs, result.wallMs, frames, width, height);
    return result;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc != 2 && argc != 3) {
            std::fprintf(stderr, "usage: ldb-optics-benchmark baseline.metallib [candidate.metallib]\n");
            return 1;
        }
        constexpr uint32_t width = 1920, height = 1080;
        constexpr int frames = 8;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return 2;
        id<MTLCommandQueue> queue = [device newCommandQueue];
        LDBOpticsEngine engine(device, [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]);
        if (!engine.valid()) return 3;
        std::unique_ptr<LDBOpticsEngine> candidate;
        if(argc==3) {
            candidate=std::make_unique<LDBOpticsEngine>(device,
                [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]);
            if(!candidate->valid())return 3;
        }
        NSUInteger bytes = NSUInteger(width) * height * sizeof(simd_float4);
        id<MTLBuffer> source = [device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
        id<MTLBuffer> destination = [device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
        simd_float4* pixels = static_cast<simd_float4*>(source.contents);
        for (uint32_t y = 0; y < height; ++y) for (uint32_t x = 0; x < width; ++x) {
            float v = .02f + .6f * float(x) / float(width - 1);
            if ((x % 401) < 3 && (y % 271) < 3) v = 8.0f;
            pixels[y * width + x] = {v, v * .8f, v * .55f, 1};
        }
        auto neutral = LDBNeutralOpticsParameters(width, height);
        auto geometry = neutral;
        geometry.distortionK1 = -.06f; geometry.vignetteNatural = .35f;
        geometry.cornerSharpnessLoss = .55f; geometry.fieldCurvature = .35f;
        auto warpOnly = neutral;
        warpOnly.distortionK1 = -.06f;
        auto vintage = neutral;
        vintage.distortionK1 = -.06f; vintage.vignetteNatural = .35f;
        vintage.cornerSharpnessLoss = .50f; vintage.fieldCurvature = .35f;
        vintage.bloomThreshold = 1; vintage.bloomEnergy = .25f; vintage.bloomRadius = 18;
        vintage.glareEnergy = .12f; vintage.glareThreshold = 1; vintage.glareRadius = 42;
        auto anamorphic = vintage;
        anamorphic.anamorphicSqueeze = 2; anamorphic.bloomHorizontalStretch = 4;
        auto detail = neutral;
        detail.microContrast=.35f; detail.fineDetail=.25f; detail.detailEdgeFalloff=.4f;
        detail.sagittalDetail=-.2f; detail.tangentialDetail=-.35f; detail.detailScale=1.5f;
        auto aberration = neutral;
        aberration.coma=.80f; aberration.sphericalHalo=.65f;
        auto aperture = neutral;
        aperture.apertureResponse=1;aperture.apertureRadius=24;aperture.apertureShape=1;
        aperture.apertureBladeCurvature=.25f;aperture.apertureCatEye=.8f;
        auto depthAperture=aperture;
        depthAperture.depthMode=2;depthAperture.depthChannel=4;depthAperture.depthFocus=.5f;
        auto bokehSwirl=aperture;
        bokehSwirl.apertureRadius=40.0f;bokehSwirl.apertureBokehSwirl=10.0f;
        bokehSwirl.apertureCatEye=.80f;
        bokehSwirl.responseFieldOnset=.22f;bokehSwirl.responseFieldFalloff=.82f;
        auto opticalDrift=bokehSwirl;
        opticalDrift.opticalDriftAmount=.75f;
        opticalDrift.opticalDriftMode=LDBOpticalDriftTangential;
        auto petzval=bokehSwirl;
        petzval.apertureShape=1;petzval.apertureBladeCount=8;
        petzval.apertureBladeCurvature=.72f;petzval.apertureAspect=1.10f;
        petzval.apertureBokehSwirl=3.2f;petzval.apertureCatEye=.52f;
        petzval.cornerSharpnessLoss=.82f;petzval.fieldCurvature=.82f;
        petzval.astigmatism=.30f;petzval.tangentialSmear=.24f;
        petzval.responseFieldOnset=.16f;petzval.responseFieldFalloff=1.16f;
        auto extremeField=neutral;
        extremeField.cornerSharpnessLoss=1.85f;extremeField.fieldCurvature=1.7f;
        extremeField.astigmatism=1.45f;extremeField.radialSmear=.48f;
        extremeField.tangentialSmear=1.35f;extremeField.responseFieldOnset=.13f;
        extremeField.responseFieldFalloff=1.4f;
        auto internalFieldEdge=neutral;
        internalFieldEdge.apertureResponse=1.0f;
        internalFieldEdge.apertureRadius=27.0f;
        internalFieldEdge.apertureSoftness=.38f;
        internalFieldEdge.astigmatism=.20f;
        internalFieldEdge.cornerSharpnessLoss=1.42f;
        internalFieldEdge.fieldAspect=1.58f;
        internalFieldEdge.fieldCurvature=.72f;
        internalFieldEdge.responseFieldOnset=.24f;
        internalFieldEdge.responseFieldFalloff=.82f;
        internalFieldEdge.tangentialSmear=.28f;
        auto depthBloom=vintage;
        depthBloom.depthMode=2;depthBloom.depthChannel=4;depthBloom.depthFocus=.5f;
        auto depthHalo=aberration;
        depthHalo.coma=0;depthHalo.depthMode=2;depthHalo.depthChannel=4;depthHalo.depthFocus=.5f;
        auto axialCA = neutral;
        axialCA.longitudinalCA=1;axialCA.longitudinalCARadius=8;
        auto anamorphicFlare=neutral;
        anamorphicFlare.anamorphicFlareAmount=.7f;
        anamorphicFlare.anamorphicFlareRadius=120;
        anamorphicFlare.anamorphicFlareThreshold=1;
        auto verticalRays=anamorphicFlare;
        verticalRays.diffractionRayAmount=.7f;
        verticalRays.diffractionRayLength=260.0f;
        auto hawkFlare=neutral;
        hawkFlare.anamorphicSqueeze=2.0f;
        hawkFlare.anamorphicFlareAmount=1.30f;
        hawkFlare.anamorphicFlareRadius=2200.0f;
        hawkFlare.anamorphicFlareThreshold=.42f;
        hawkFlare.anamorphicFlareCoreAmount=.38f;
        hawkFlare.anamorphicFlareAsymmetry=.08f;
        hawkFlare.anamorphicFlareGhostAmount=.075f;
        hawkFlare.anamorphicFlareGhostPosition=-.70f;
        hawkFlare.anamorphicFlareGhostScale=.72f;
        hawkFlare.anamorphicFlareColor={.22f,.52f,1.0f};
        hawkFlare.anamorphicFlareGhostColor={.30f,.18f,.68f};
        hawkFlare.glareEnergy=1.28f;
        hawkFlare.glareThreshold=.44f;
        hawkFlare.glareRadius=900.0f;
        hawkFlare.glareColorAmount=.82f;
        hawkFlare.glareColor={.18f,.42f,1.0f};
        hawkFlare.bloomEnergy=.10f;
        hawkFlare.bloomThreshold=.44f;
        hawkFlare.bloomRadius=58.0f;
        auto refractive=neutral;
        refractive.refractiveIrregularity=1.0f;
        refractive.refractiveScale=1.0f;
        refractive.refractiveEdgeBias=.65f;
        refractive.refractiveAnisotropy=.4f;
        refractive.refractiveRotation=27;
        refractive.refractiveDispersion=.7f;
        refractive.refractiveSeed=12345;
        auto prism=neutral;
        prism.prismAmount=1.0f;
        prism.prismDirection=18.0f;
        prism.prismDispersion=.75f;
        prism.prismEdgeBias=.55f;
        prism.prismSoftness=.35f;
        auto prismRadial=prism;
        prismRadial.prismDistribution=LDBPrismRadialField;
        prismRadial.fieldAspect=1.55f;
        prismRadial.responseFieldOnset=.2f;
        prismRadial.responseFieldFalloff=.9f;
        auto frontWear=neutral;
        auto chromaticDefocus=neutral;
        chromaticDefocus.lateralCARed=6.0f;
        chromaticDefocus.lateralCABlue=-7.0f;
        chromaticDefocus.cornerSharpnessLoss=2.0f;
        chromaticDefocus.fieldCurvature=1.75f;
        chromaticDefocus.radialSmear=1.25f;
        chromaticDefocus.tangentialSmear=1.55f;
        chromaticDefocus.responseFieldOnset=.10f;
        chromaticDefocus.responseFieldFalloff=.92f;
        chromaticDefocus.apertureResponse=1.0f;
        chromaticDefocus.apertureRadius=24.0f;
        frontWear.frontHaze=1.15f;frontWear.cleaningMarks=1.6f;
        frontWear.scratchAmount=1.35f;frontWear.scratchDirection=28;
        frontWear.damageScale=1.25f;frontWear.coatingWear=1.25f;
        frontWear.coatingWearScale=1.4f;frontWear.damageSeed=31415;
        auto internalDirt=neutral;
        internalDirt.internalDirtAmount=1.25f;internalDirt.internalDirtScale=1.5f;
        internalDirt.internalDirtSmear=.45f;internalDirt.internalDirtScatter=1.35f;
        internalDirt.internalDirtSeed=16180;
        std::printf("Metal device: %s\n", device.name.UTF8String);
        if(candidate) {
            struct ABCase { const char* name; const LDBOpticsParameters* p; } cases[]={
                {"geometry",&geometry},{"ca+defocus",&chromaticDefocus},
                {"bokeh-swirl",&bokehSwirl},{"petzval",&petzval},
                {"extreme-field",&extremeField},{"internal-edge",&internalFieldEdge}};
            std::printf("\nOptical blur A/B (interleaved baseline then candidate)\n");
            for(const auto& c:cases) {
                std::string baseName=std::string(c.name)+"-base";
                std::string testName=std::string(c.name)+"-test";
                auto base=benchmark(baseName.c_str(),engine,device,queue,source,destination,width,height,*c.p,frames);
                auto test=benchmark(testName.c_str(),*candidate,device,queue,source,destination,width,height,*c.p,frames);
                std::printf("  %-12s GPU %+6.1f%%  wall %+6.1f%%\n",c.name,
                    (test.gpuMs/base.gpuMs-1.0)*100.0,(test.wallMs/base.wallMs-1.0)*100.0);
            }
            return 0;
        }
        benchmark("neutral", engine, device, queue, source, destination, width, height, neutral, frames);
        benchmark("warp-only", engine, device, queue, source, destination, width, height, warpOnly, frames);
        benchmark("geometry", engine, device, queue, source, destination, width, height, geometry, frames);
        benchmark("refractive", engine, device, queue, source, destination, width, height, refractive, frames);
        benchmark("prism", engine, device, queue, source, destination, width, height, prism, frames);
        benchmark("prism-radial", engine, device, queue, source, destination, width, height, prismRadial, frames);
        benchmark("front-wear", engine, device, queue, source, destination, width, height, frontWear, frames);
        benchmark("internal-dirt", engine, device, queue, source, destination, width, height, internalDirt, frames);
        benchmark("ca+defocus", engine, device, queue, source, destination, width, height, chromaticDefocus, frames);
        benchmark("detail", engine, device, queue, source, destination, width, height, detail, frames);
        benchmark("coma+halo", engine, device, queue, source, destination, width, height, aberration, frames);
        benchmark("aperture", engine, device, queue, source, destination, width, height, aperture, frames);
        benchmark("bokeh-swirl", engine, device, queue, source, destination, width, height, bokehSwirl, frames);
        benchmark("optical-drift", engine, device, queue, source, destination, width, height, opticalDrift, frames);
        benchmark("petzval", engine, device, queue, source, destination, width, height, petzval, frames);
        benchmark("aperture-z", engine, device, queue, source, destination, width, height, depthAperture, frames);
        benchmark("bloom-z", engine, device, queue, source, destination, width, height, depthBloom, frames);
        benchmark("halo-z", engine, device, queue, source, destination, width, height, depthHalo, frames);
        benchmark("axial-ca", engine, device, queue, source, destination, width, height, axialCA, frames);
        benchmark("ana-flare", engine, device, queue, source, destination, width, height, anamorphicFlare, frames);
        benchmark("vertical-rays", engine, device, queue, source, destination, width, height, verticalRays, frames);
        benchmark("hawk-flare", engine, device, queue, source, destination, width, height, hawkFlare, frames);
        benchmark("vintage", engine, device, queue, source, destination, width, height, vintage, frames);
        benchmark("anamorphic", engine, device, queue, source, destination, width, height, anamorphic, frames);
        // Repeat representative cases at the end of the same run. A large
        // within-run change flags device clock, thermal or competing-workload
        // drift instead of attributing it to one optical stage.
        benchmark("neutral-end", engine, device, queue, source, destination, width, height, neutral, frames);
        benchmark("aperture-end", engine, device, queue, source, destination, width, height, aperture, frames);
        benchmark("petzval-end", engine, device, queue, source, destination, width, height, petzval, frames);
        benchmark("ca+defoc-end", engine, device, queue, source, destination, width, height, chromaticDefocus, frames);
        // Repeat the flare family after all scratch allocations are resident.
        // The first flare case can otherwise absorb unified-memory page setup
        // and misleadingly report that transition cost as steady-state work.
        benchmark("ana-flare-end", engine, device, queue, source, destination, width, height, anamorphicFlare, frames);
        benchmark("rays-end", engine, device, queue, source, destination, width, height, verticalRays, frames);
        benchmark("hawk-end", engine, device, queue, source, destination, width, height, hawkFlare, frames);
        benchmark("internal-end", engine, device, queue, source, destination, width, height, internalDirt, frames);
        benchmark("prism-end", engine, device, queue, source, destination, width, height, prism, frames);
    }
    return 0;
}
