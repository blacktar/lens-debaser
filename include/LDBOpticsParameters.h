#pragma once

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
typedef float2 LDBFloat2;
typedef float3 LDBFloat3;
#else
#include <simd/simd.h>
#include <cstddef>
#include <type_traits>
typedef simd_float2 LDBFloat2;
typedef simd_float3 LDBFloat3;
#endif

enum : uint32_t { LDBOpticsParameterABIVersion = 3 };

enum LDBWorkingColorSpace : uint32_t {
    LDBWorkingColorSpaceACEScg = 0,
    LDBWorkingColorSpaceACEScct = 1,
    LDBWorkingColorSpaceDaVinciIntermediate = 2,
    LDBWorkingColorSpaceARRILogC3EI800 = 3,
    LDBWorkingColorSpaceARRILogC4 = 4,
};

enum LDBProcessingFlags : uint32_t {
    LDBProcessingQualityBalanced = 0u,
    LDBProcessingQualityFast = 1u,
    LDBProcessingQualityHigh = 2u,
    LDBProcessingQualityMask = 3u,
    LDBDiagnosticDifference = 1u << 8,
    LDBDiagnosticScatter = 2u << 8,
    LDBDiagnosticDirectOptics = 3u << 8,
    LDBDiagnosticDepth = 4u << 8,
    LDBDiagnosticMask = 7u << 8,
};

// Keep this structure 16-byte aligned and shared verbatim by Metal and host code.
struct alignas(16) LDBOpticsParameters {
    LDBFloat2 imageSize;
    LDBFloat2 opticalCenter;

    float distortionK1;
    float distortionK2;
    float moustacheK3;
    float anamorphicSqueeze;

    float lateralCARed;
    float lateralCABlue;
    float vignetteNatural;
    float vignetteOptical;

    float vignetteMechanical;
    float imageCircleSize;
    float imageCircleAspect;
    float imageCircleSoftness;

    float cornerSharpnessLoss;
    float astigmatism;
    float coma;
    float sphericalHalo;

    float fieldCurvature;
    float swirl;
    float radialSmear;
    float tangentialSmear;

    float microContrast;
    float fineDetail;
    float detailEdgeFalloff;
    float sagittalDetail;

    float tangentialDetail;
    float detailScale;
    float comaThreshold;
    float reservedDetail1;

    float bloomEnergy;
    float bloomThreshold;
    float bloomRadius;
    float bloomHorizontalStretch;

    float glareEnergy;
    float glareRadius;
    float effectBlend;
    uint32_t workingColorSpace;

    LDBFloat3 transmissionColor;
    float transmissionColorAmount;

    LDBFloat3 glareColor;
    float glareColorAmount;

    uint32_t processingFlags;
    uint32_t apertureShape;
    uint32_t apertureBladeCount;
    float apertureResponse;

    float apertureRadius;
    float apertureBladeCurvature;
    float apertureRotation;
    float apertureSoftness;

    float apertureCatEye;
    float apertureAspect;
    uint32_t reserved2;
    uint32_t reserved3;

    float longitudinalCA;
    float longitudinalCARadius;
    float depthFocus;
    uint32_t reserved5;

    LDBFloat3 nearFocusColor;
    float reserved6;

    LDBFloat3 farFocusColor;
    float reserved7;

    uint32_t depthMode;
    uint32_t depthChannel;
    float depthNear;
    float depthFar;
};

struct alignas(16) LDBScatterParameters {
    LDBFloat2 imageSize;
    float radiusX;
    float radiusY;
    uint32_t scale;
    float threshold;
    float axisX;
    float axisY;
};

#ifndef __METAL_VERSION__
static_assert(std::is_standard_layout_v<LDBOpticsParameters>);
static_assert(sizeof(LDBOpticsParameters) == 368, "LDB optics ABI v3 size changed");
static_assert(alignof(LDBOpticsParameters) == 16, "LDB optics ABI v2 alignment changed");
static_assert(offsetof(LDBOpticsParameters, distortionK1) == 16);
static_assert(offsetof(LDBOpticsParameters, cornerSharpnessLoss) == 64);
static_assert(offsetof(LDBOpticsParameters, fieldCurvature) == 80);
static_assert(offsetof(LDBOpticsParameters, microContrast) == 96);
static_assert(offsetof(LDBOpticsParameters, bloomEnergy) == 128);
static_assert(offsetof(LDBOpticsParameters, glareEnergy) == 144);
static_assert(offsetof(LDBOpticsParameters, transmissionColor) == 160);
static_assert(offsetof(LDBOpticsParameters, glareColor) == 192);
static_assert(offsetof(LDBOpticsParameters, processingFlags) == 212);
static_assert(offsetof(LDBOpticsParameters, apertureResponse) == 224);
static_assert(offsetof(LDBOpticsParameters, apertureRadius) == 228);
static_assert(offsetof(LDBOpticsParameters, longitudinalCA) == 260);
static_assert(offsetof(LDBOpticsParameters, nearFocusColor) == 288);
static_assert(offsetof(LDBOpticsParameters, farFocusColor) == 320);
static_assert(offsetof(LDBOpticsParameters, depthMode) == 340);
static_assert(sizeof(LDBScatterParameters) == 32, "LDB scatter ABI v1 size changed");
#endif

static inline LDBOpticsParameters LDBNeutralOpticsParameters(float width, float height) {
    LDBOpticsParameters p{};
    p.imageSize = {width, height};
    p.opticalCenter = {0.5f, 0.5f};
    p.anamorphicSqueeze = 1.0f;
    p.imageCircleSize = 1.2f;
    p.imageCircleAspect = 1.0f;
    p.imageCircleSoftness = 0.1f;
    p.detailScale = 1.0f;
    p.comaThreshold = 0.6f;
    p.effectBlend = 1.0f;
    p.workingColorSpace = LDBWorkingColorSpaceACEScg;
    p.transmissionColor = {1.0f, 1.0f, 1.0f};
    p.glareColor = {1.0f, 1.0f, 1.0f};
    p.apertureShape = 0;
    p.apertureBladeCount = 6;
    p.apertureRadius = 6.0f;
    p.apertureBladeCurvature = 0.5f;
    p.apertureSoftness = 0.5f;
    p.apertureAspect = 1.0f;
    p.longitudinalCARadius = 4.0f;
    p.depthFocus = 0.5f;
    p.nearFocusColor = {1.0f, 0.35f, 0.75f};
    p.farFocusColor = {0.35f, 1.0f, 0.65f};
    p.depthNear = 0.0f;
    p.depthFar = 1.0f;
    p.depthChannel = 4;
    return p;
}
