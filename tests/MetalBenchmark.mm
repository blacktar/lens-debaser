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
        if (argc != 2) {
            std::fprintf(stderr, "usage: ldb-optics-benchmark LDBOptics.metallib\n");
            return 1;
        }
        constexpr uint32_t width = 1920, height = 1080;
        constexpr int frames = 8;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return 2;
        id<MTLCommandQueue> queue = [device newCommandQueue];
        LDBOpticsEngine engine(device, [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]);
        if (!engine.valid()) return 3;
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
        auto vintage = neutral;
        vintage.distortionK1 = -.06f; vintage.vignetteNatural = .35f;
        vintage.cornerSharpnessLoss = .50f; vintage.fieldCurvature = .35f;
        vintage.bloomThreshold = 1; vintage.bloomEnergy = .25f; vintage.bloomRadius = 18;
        vintage.glareEnergy = .12f; vintage.glareRadius = 42;
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
        std::printf("Metal device: %s\n", device.name.UTF8String);
        benchmark("neutral", engine, device, queue, source, destination, width, height, neutral, frames);
        benchmark("geometry", engine, device, queue, source, destination, width, height, geometry, frames);
        benchmark("detail", engine, device, queue, source, destination, width, height, detail, frames);
        benchmark("coma+halo", engine, device, queue, source, destination, width, height, aberration, frames);
        benchmark("aperture", engine, device, queue, source, destination, width, height, aperture, frames);
        benchmark("aperture-z", engine, device, queue, source, destination, width, height, depthAperture, frames);
        benchmark("bloom-z", engine, device, queue, source, destination, width, height, depthBloom, frames);
        benchmark("halo-z", engine, device, queue, source, destination, width, height, depthHalo, frames);
        benchmark("axial-ca", engine, device, queue, source, destination, width, height, axialCA, frames);
        benchmark("ana-flare", engine, device, queue, source, destination, width, height, anamorphicFlare, frames);
        benchmark("vintage", engine, device, queue, source, destination, width, height, vintage, frames);
        benchmark("anamorphic", engine, device, queue, source, destination, width, height, anamorphic, frames);
    }
    return 0;
}
