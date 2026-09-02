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
}

void RunLensDebaserMetal(void* commandQueue, int width, int height,
                         const LDBOpticsParameters& parameters,
                         const float* input, float* output) {
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
    static_assert(sizeof(source) == sizeof(input));
    std::memcpy(&source, &input, sizeof(source));
    std::memcpy(&destination, &output, sizeof(destination));
    id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
    commandBuffer.label = @"Lens Debaser";
    engine->encode(commandBuffer, source, destination, uint32_t(width), uint32_t(height), parameters);
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
