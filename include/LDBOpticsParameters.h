#pragma once

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
typedef float2 LDBFloat2;
typedef float3 LDBFloat3;
typedef float4 LDBFloat4;
#else
#include <simd/simd.h>
#include <cstddef>
#include <type_traits>
typedef simd_float2 LDBFloat2;
typedef simd_float3 LDBFloat3;
typedef simd_float4 LDBFloat4;
#endif

enum : uint32_t { LDBOpticsParameterABIVersion = 19 };

enum LDBOpticalDriftMode : uint32_t {
    LDBOpticalDriftRadial = 0,
    LDBOpticalDriftTangential = 1,
    LDBOpticalDriftDirected = 2,
};

enum LDBPrismDistribution : uint32_t {
    LDBPrismLinearEdge = 0,
    LDBPrismUniform = 1,
    LDBPrismBilateral = 2,
    LDBPrismRadialField = 3,
    LDBPrismInverseField = 4,
};

enum LDBWorkingColorSpace : uint32_t {
    LDBWorkingColorSpaceACEScg = 0,
    LDBWorkingColorSpaceACEScct = 1,
    LDBWorkingColorSpaceDaVinciIntermediate = 2,
    LDBWorkingColorSpaceARRILogC3EI800 = 3,
    LDBWorkingColorSpaceARRILogC4 = 4,
};

enum LDBProcessingFlags : uint32_t {
    LDBDiagnosticDifference = 1u << 8,
    LDBDiagnosticScatter = 2u << 8,
    LDBDiagnosticDirectOptics = 3u << 8,
    LDBDiagnosticDepth = 4u << 8,
    LDBDiagnosticDefocus = 5u << 8,
    LDBDiagnosticDepthRejection = 6u << 8,
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
    // Host render scale for pixel-sized kernels. Resolve thumbnails and proxy
    // renders must preserve the same proportional optical footprint.
    float renderPixelScale;

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
    float aperturePupilShift;
    float aperturePupilClip;

    float longitudinalCA;
    float longitudinalCARadius;
    float depthFocus;
    float apertureRimWeight;

    LDBFloat3 nearFocusColor;
    float reserved6;

    LDBFloat3 farFocusColor;
    float reserved7;

    uint32_t depthMode;
    uint32_t depthChannel;
    float depthNear;
    float depthFar;

    // ABI v4: an independently positionable and shaped off-axis response
    // field, followed by perceptual transmission response controls.
    LDBFloat2 fieldCenter;
    float fieldAspect;
    float fieldRotation;

    float transmissionDensity;
    float transmissionContrast;
    float transmissionHighlightSoftness;
    float anamorphicDistortion;

    float anamorphicAberration;
    // ABI v19: translates the energy centre of a growing aperture PSF without
    // moving the sharp base image. These reuse established reserved slots so
    // the constant-buffer size and every later offset remain unchanged.
    float opticalDriftAmount;
    uint32_t opticalDriftMode;
    float opticalDriftAngle;

    float anamorphicFlareAmount;
    float anamorphicFlareRadius;
    float anamorphicFlareThreshold;
    float reservedV4_3;

    LDBFloat3 anamorphicFlareColor;

    float variationAmount;
    uint32_t variationSeed;
    float variationFieldAsymmetry;
    float variationPupilIrregularity;

    float variationChromaticAsymmetry;
    float variationTransmissionUnevenness;
    float reservedV4_4;
    float reservedV4_5;

    float responseHighlightKnee;
    float responseFieldOnset;
    float responseFieldFalloff;
    float responseDefocusOnset;

    float responseDefocusFalloff;
    float responseScatterEdgeProtection;
    float depthEdgeSoftness;
    float reservedV4_7;

    float captureFocalLength;
    float captureAperture;
    float captureFocusDistance;
    float captureGateWidth;

    float captureGateHeight;
    float captureInfluence;
    float lookCharacter;
    float lookVintageBias;

    float lookExoticBias;
    float lookInfluence;
    float lookAnamorphicBias;
    float lookVintageCaricatureBias;

    // ABI v5: spatially varying pupil response. Zero retains the established
    // uniform aperture response; one progressively introduces the configured
    // off-axis field envelope and tangential pupil deformation.
    float apertureBokehSwirl;
    // Geometry extension using formerly reserved ABI-v5 slots. Existing
    // offsets and total structure size remain unchanged.
    float geometryFieldAmount;
    float peripheralStretch;
    float peripheralWarp;

    // ABI v6: deterministic, lens-space front-element wear. These control
    // illumination-responsive scatter and transmission, never an overlay.
    float frontHaze;
    float cleaningMarks;
    float scratchAmount;
    float scratchDirection;

    float damageScale;
    float coatingWear;
    float coatingWearScale;
    uint32_t damageSeed;

    // ABI v7: low-cost stable refractive-index/thickness irregularity.
    float refractiveIrregularity;
    float refractiveScale;
    float refractiveEdgeBias;
    float refractiveAnisotropy;

    float refractiveRotation;
    float refractiveDispersion;
    uint32_t refractiveSeed;
    uint32_t reservedV7_0;

    // ABI v8: -1 onset links chromatic response to the shared Field envelope.
    // Nonnegative onset uses an independent radial chromatic envelope.
    float chromaticFieldOnset;
    float chromaticFieldFalloff;
    // ABI v17: independent glare extraction. This reuses an established
    // reserved slot, preserving the 784-byte constant-buffer layout.
    float glareThreshold;
    // ABI v18: selects how the coherent prism response is distributed. Zero
    // preserves the released one-sided Linear Edge response exactly.
    uint32_t prismDistribution;

    // ABI v16: coherent directional prism refraction. These reuse the five
    // slots retained from an unreleased front-dirt experiment, preserving the
    // established 784-byte layout. Zero amount is exactly neutral.
    float prismAmount;
    float prismDirection;
    float prismDispersion;
    float prismEdgeBias;

    float prismSoftness;
    float internalDirtAmount;
    float internalDirtScale;
    float internalDirtSmear;

    float internalDirtScatter;
    uint32_t internalDirtSeed;
    float internalDirtSoftness;
    float internalDirtComplexity;

    // ABI v10: structured anamorphic flare. These refine the existing flare
    // buffer in the composite stage, so legacy presets remain bit-identical
    // while new looks can add a hot core, asymmetric tail and optical ghost.
    LDBFloat3 anamorphicFlareGhostColor;
    float anamorphicFlareGhostAmount;

    float anamorphicFlareCoreAmount;
    float anamorphicFlareAsymmetry;
    float anamorphicFlareGhostPosition;
    float anamorphicFlareGhostScale;

    // ABI v11: layered anamorphic flare structure. Amount controls remain
    // neutral at zero so every v10 look retains its established rendering.
    float anamorphicFlareBandAmount;
    float anamorphicFlareBandSeparation;
    float anamorphicFlareSecondaryAmount;
    float anamorphicFlareSecondaryOffset;

    // ABI v12: independent vertical thickness for the primary, layered and
    // secondary streaks. One preserves the v11 rendering exactly.
    float anamorphicFlareThickness;

    // ABI v13: source-derived vertical diffraction rays. These occupy two
    // previously reserved v12 slots, preserving the 784-byte buffer layout.
    float diffractionRayAmount;
    float diffractionRayLength;
    // ABI v14: bounded analytic internal-reflection train. Count 1 preserves
    // the v13 single-ellipse model; higher values add smooth optical paths.
    float anamorphicFlareGhostCount;
    float anamorphicFlareGhostSpacing;
    float anamorphicFlareGhostScaleDecay;
    float anamorphicFlareGhostEnergyDecay;
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
    float finalFramingMode, finalFramingZoom, finalFramingX, finalFramingY;
    float finalFramingMargin;
#endif
    // ABI v15 reuses established reserved slots for general pupil clipping,
    // rim energy and multi-scale internal optical-density fields. The buffer
    // layout and size remain stable; zero values retain the v14 response.
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

// Internal GPU exchange record for the bounded analytic-flare source list.
// positionEnergyRadius = full-resolution x/y, source energy, source radius.
// colorActive = energy-normalized linear AP1 source color and active flag.
struct alignas(16) LDBFlareSource {
    LDBFloat4 positionEnergyRadius;
    LDBFloat4 colorActive;
};

#ifndef __METAL_VERSION__
static_assert(std::is_standard_layout_v<LDBOpticsParameters>);
#if !defined(LDB_FINAL_FRAMING_EXPERIMENT) && !defined(LDB_ENABLE_FINAL_FRAMING)
static_assert(sizeof(LDBOpticsParameters) == 784, "LDB optics ABI v19 size changed");
#else
static_assert(sizeof(LDBOpticsParameters) == 816);
#endif
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
static_assert(offsetof(LDBOpticsParameters, fieldCenter) == 360);
static_assert(offsetof(LDBOpticsParameters, fieldAspect) == 368);
static_assert(offsetof(LDBOpticsParameters, transmissionDensity) == 376);
static_assert(offsetof(LDBOpticsParameters, anamorphicDistortion) == 388);
static_assert(offsetof(LDBOpticsParameters, anamorphicAberration) == 392);
static_assert(offsetof(LDBOpticsParameters, opticalDriftAmount) == 396);
static_assert(offsetof(LDBOpticsParameters, opticalDriftMode) == 400);
static_assert(offsetof(LDBOpticsParameters, opticalDriftAngle) == 404);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareAmount) == 408);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareColor) == 432);
static_assert(offsetof(LDBOpticsParameters, variationAmount) == 448);
static_assert(offsetof(LDBOpticsParameters, variationChromaticAsymmetry) == 464);
static_assert(offsetof(LDBOpticsParameters, responseHighlightKnee) == 480);
static_assert(offsetof(LDBOpticsParameters, responseDefocusFalloff) == 496);
static_assert(offsetof(LDBOpticsParameters, depthEdgeSoftness) == 504);
static_assert(offsetof(LDBOpticsParameters, captureFocalLength) == 512);
static_assert(offsetof(LDBOpticsParameters, lookExoticBias) == 544);
static_assert(offsetof(LDBOpticsParameters, lookAnamorphicBias) == 552);
static_assert(offsetof(LDBOpticsParameters, lookVintageCaricatureBias) == 556);
static_assert(offsetof(LDBOpticsParameters, apertureBokehSwirl) == 560);
static_assert(offsetof(LDBOpticsParameters, frontHaze) == 576);
static_assert(offsetof(LDBOpticsParameters, damageScale) == 592);
static_assert(offsetof(LDBOpticsParameters, refractiveIrregularity) == 608);
static_assert(offsetof(LDBOpticsParameters, refractiveRotation) == 624);
static_assert(offsetof(LDBOpticsParameters, chromaticFieldOnset) == 640);
static_assert(offsetof(LDBOpticsParameters, glareThreshold) == 648);
static_assert(offsetof(LDBOpticsParameters, prismDistribution) == 652);
static_assert(offsetof(LDBOpticsParameters, prismAmount) == 656);
static_assert(offsetof(LDBOpticsParameters, prismSoftness) == 672);
static_assert(offsetof(LDBOpticsParameters, internalDirtAmount) == 676);
static_assert(offsetof(LDBOpticsParameters, internalDirtScatter) == 688);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareGhostColor) == 704);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareCoreAmount) == 724);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareBandAmount) == 740);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareThickness) == 756);
static_assert(offsetof(LDBOpticsParameters, diffractionRayAmount) == 760);
static_assert(offsetof(LDBOpticsParameters, diffractionRayLength) == 764);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareGhostCount) == 768);
static_assert(offsetof(LDBOpticsParameters, anamorphicFlareGhostEnergyDecay) == 780);
static_assert(sizeof(LDBScatterParameters) == 32, "LDB scatter ABI v1 size changed");
static_assert(sizeof(LDBFlareSource) == 32, "LDB flare-source layout changed");
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
    p.renderPixelScale = 1.0f;
    p.comaThreshold = 0.6f;
    p.effectBlend = 1.0f;
    p.workingColorSpace = LDBWorkingColorSpaceACEScg;
    p.transmissionColor = {1.0f, 1.0f, 1.0f};
    p.glareColor = {1.0f, 1.0f, 1.0f};
    p.glareThreshold = 0.45f;
    p.apertureShape = 0;
    p.apertureBladeCount = 6;
    p.apertureRadius = 6.0f;
    p.apertureBladeCurvature = 0.5f;
    p.apertureSoftness = 0.5f;
    p.apertureAspect = 1.0f;
    p.internalDirtSoftness = 0.5f;
    p.internalDirtComplexity = 0.5f;
    p.prismEdgeBias = 0.65f;
    p.prismSoftness = 0.3f;
    p.longitudinalCARadius = 4.0f;
    p.depthFocus = 0.5f;
    p.nearFocusColor = {1.0f, 0.35f, 0.75f};
    p.farFocusColor = {0.35f, 1.0f, 0.65f};
    p.depthNear = 0.0f;
    p.depthFar = 1.0f;
    p.depthChannel = 4;
    p.fieldCenter = {0.5f, 0.5f};
    p.fieldAspect = 1.0f;
    p.anamorphicFlareRadius = 80.0f;
    p.anamorphicFlareThreshold = 1.0f;
    p.anamorphicFlareColor = {0.35f, 0.55f, 1.0f};
    p.anamorphicFlareGhostColor = {0.55f, 0.25f, 1.0f};
    p.anamorphicFlareGhostPosition = -0.72f;
    p.anamorphicFlareGhostScale = 1.0f;
    p.anamorphicFlareBandSeparation = 48.0f;
    p.anamorphicFlareSecondaryOffset = 180.0f;
    p.anamorphicFlareThickness = 1.0f;
    p.diffractionRayLength = 180.0f;
    p.anamorphicFlareGhostCount = 1.0f;
    p.anamorphicFlareGhostSpacing = 90.0f;
    p.anamorphicFlareGhostScaleDecay = 0.82f;
    p.anamorphicFlareGhostEnergyDecay = 0.62f;
    p.responseFieldOnset = 0.0f;
    p.chromaticFieldOnset = -1.0f;
    p.chromaticFieldFalloff = 1.0f;
    p.responseFieldFalloff = 1.0f;
    p.responseDefocusOnset = 0.018f;
    p.responseDefocusFalloff = 0.36f;
    p.responseScatterEdgeProtection = 1.0f;
    p.depthEdgeSoftness = 0.5f;
    p.captureFocalLength = 50.0f;
    p.captureAperture = 2.8f;
    p.captureFocusDistance = 3.0f;
    p.captureGateWidth = 36.0f;
    p.captureGateHeight = 24.0f;
    p.damageScale = 1.0f;
    p.coatingWearScale = 1.0f;
    p.refractiveScale = 1.0f;
    p.internalDirtScale = 1.0f;
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
    p.finalFramingZoom=100.0f;
#endif
    return p;
}

#ifndef __METAL_VERSION__
static inline void LDBApplyRenderPixelScale(LDBOpticsParameters &p) {
    const float scale = p.renderPixelScale > 0.0001f ? p.renderPixelScale : 1.0f;
    p.longitudinalCARadius *= scale;
    p.detailScale *= scale;
    p.bloomRadius *= scale;
    p.glareRadius *= scale;
    p.apertureRadius *= scale;
    p.anamorphicFlareRadius *= scale;
    p.anamorphicFlareGhostSpacing *= scale;
    p.anamorphicFlareBandSeparation *= scale;
    p.anamorphicFlareSecondaryOffset *= scale;
    p.diffractionRayLength *= scale;
}
#endif
