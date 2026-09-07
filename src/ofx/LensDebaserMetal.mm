#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <unordered_map>
#include "LDBOpticsEngine.h"
#include "LensDebaserMetal.h"

namespace {
std::mutex gEngineMutex;
std::unordered_map<void*, std::shared_ptr<LDBOpticsEngine>> gEngines;

NSURL* metallibURL() {
    Dl_info info{};
    if (!dladdr(reinterpret_cast<const void*>(&RunLensDebaserMetal), &info) || !info.dli_fname)
        return nil;
    NSString* executable = [NSString stringWithUTF8String:info.dli_fname];
    NSString* contents = [[executable stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    return [NSURL fileURLWithPath:[contents stringByAppendingPathComponent:@"Resources/LDBOptics.metallib"]];
}

void reportMetalFailure(id<MTLCommandBuffer> commandBuffer) {
    if (commandBuffer.status != MTLCommandBufferStatusError) return;
    NSError* error = commandBuffer.error;
    NSLog(@"Lens Debaser Metal failure: domain=%@ code=%ld description=%@ reason=%@",
          error.domain, (long)error.code, error.localizedDescription,
          error.localizedFailureReason ?: @"(none)");
}
}

void RunLensDebaserMetal(void* commandQueue, int width, int height,
                         const LDBOpticsParameters& parameters,
                         const float* input, float* output,
                         const float* depthInput) {
    id<MTLCommandQueue> queue = static_cast<id<MTLCommandQueue>>(commandQueue);
    if (!queue || width <= 0 || height <= 0) throw std::runtime_error("Resolve did not provide a valid Metal queue or image size");

    std::shared_ptr<LDBOpticsEngine> engine;
    {
        std::lock_guard<std::mutex> lock(gEngineMutex);
        void* key = static_cast<void*>(queue.device);
        auto& cached = gEngines[key];
        if (!cached) cached = std::make_shared<LDBOpticsEngine>(queue.device, metallibURL());
        engine = cached;
    }
    if (!engine->valid()) throw std::runtime_error(engine->errorMessage());

    id<MTLBuffer> source = nil;
    id<MTLBuffer> destination = nil;
    id<MTLBuffer> depth = nil;
    static_assert(sizeof(source) == sizeof(input));
    std::memcpy(&source, &input, sizeof(source));
    std::memcpy(&destination, &output, sizeof(destination));
    if (depthInput) std::memcpy(&depth, &depthInput, sizeof(depth));
    if (!source || !destination)
        throw std::runtime_error("Resolve supplied a null Metal image buffer");
    if (source.device != queue.device || destination.device != queue.device)
        throw std::runtime_error("Resolve supplied an image buffer from a different Metal device");
    if (depth && depth.device != queue.device)
        throw std::runtime_error("Resolve supplied a depth buffer from a different Metal device");
    const NSUInteger pixels = NSUInteger(width) * NSUInteger(height);
    if (pixels > NSUIntegerMax / (sizeof(float) * 4u))
        throw std::runtime_error("Resolve supplied invalid Metal image dimensions");
    const NSUInteger requiredBytes = pixels * sizeof(float) * 4u;
    if (source.length < requiredBytes || destination.length < requiredBytes) {
        NSLog(@"Lens Debaser rejected undersized Metal buffers: %dx%d requires %llu bytes; source=%llu destination=%llu",
              width, height, (unsigned long long)requiredBytes,
              (unsigned long long)source.length, (unsigned long long)destination.length);
        throw std::runtime_error("Resolve supplied an undersized Metal image buffer");
    }
    if (depth && depth.length < requiredBytes)
        throw std::runtime_error("Resolve supplied an undersized Metal depth buffer");
    id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
    if (!commandBuffer)
        throw std::runtime_error("Resolve's Metal queue could not create a command buffer");
    commandBuffer.label = @"Lens Debaser";
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        reportMetalFailure(completed);
    }];
    engine->encode(commandBuffer, source, destination, uint32_t(width), uint32_t(height), parameters, depth);
    [commandBuffer commit];
}

std::string ChooseLensDebaserPresetToLoad() {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[@"ldbpreset"];
    if ([panel runModal] != NSModalResponseOK) return {};
    return panel.URL.path.UTF8String ?: "";
}

std::string ChooseLensDebaserPresetToSave() {
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"ldbpreset"];
    panel.allowsOtherFileTypes = NO;
    panel.nameFieldStringValue = @"Untitled.ldbpreset";
    if ([panel runModal] != NSModalResponseOK) return {};
    return panel.URL.path.UTF8String ?: "";
}
