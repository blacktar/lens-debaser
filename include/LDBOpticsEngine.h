#pragma once

#import <Metal/Metal.h>
#include "LDBOpticsParameters.h"

class LDBOpticsEngine {
public:
    explicit LDBOpticsEngine(id<MTLDevice> device, NSURL* metallibURL);
    ~LDBOpticsEngine();

    bool valid() const;
    const char* errorMessage() const;

    void encode(id<MTLCommandBuffer> commandBuffer,
                id<MTLBuffer> source,
                id<MTLBuffer> destination,
                uint32_t width,
                uint32_t height,
                const LDBOpticsParameters& parameters,
                id<MTLBuffer> depthSource = nil);

private:
    struct Impl;
    Impl* impl_;
};
