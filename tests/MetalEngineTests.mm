#include "LDBColorReference.h"
#include "LDBOpticsEngine.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

static void require(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}

static std::vector<simd_float4>
render(LDBOpticsEngine &engine, id<MTLDevice> device, id<MTLCommandQueue> queue,
       const std::vector<simd_float4> &input, uint32_t width, uint32_t height,
       const LDBOpticsParameters &parameters) {
  @autoreleasepool {
    NSUInteger bytes = input.size() * sizeof(simd_float4);
    id<MTLBuffer> src = [device newBufferWithBytes:input.data()
                                            length:bytes
                                           options:MTLResourceStorageModeShared];
    id<MTLBuffer> dst = [device newBufferWithLength:bytes
                                            options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    engine.encode(command, src, dst, width, height, parameters);
    [command commit];
    [command waitUntilCompleted];
    require(command.status == MTLCommandBufferStatusCompleted,
            "Metal command did not complete");
    simd_float4 *values = static_cast<simd_float4 *>(dst.contents);
    return std::vector<simd_float4>(values, values + input.size());
  }
}

static std::vector<simd_float4> renderWithDepth(
    LDBOpticsEngine &engine, id<MTLDevice> device, id<MTLCommandQueue> queue,
    const std::vector<simd_float4> &input,
    const std::vector<simd_float4> &depth, uint32_t width, uint32_t height,
    const LDBOpticsParameters &parameters) {
  @autoreleasepool {
    require(input.size() == depth.size(),
            "Depth input dimensions must match RGB");
    NSUInteger bytes = input.size() * sizeof(simd_float4);
    id<MTLBuffer> src = [device newBufferWithBytes:input.data()
                                            length:bytes
                                           options:MTLResourceStorageModeShared];
    id<MTLBuffer> z = [device newBufferWithBytes:depth.data()
                                          length:bytes
                                         options:MTLResourceStorageModeShared];
    id<MTLBuffer> dst = [device newBufferWithLength:bytes
                                            options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    engine.encode(command, src, dst, width, height, parameters, z);
    [command commit];
    [command waitUntilCompleted];
    require(command.status == MTLCommandBufferStatusCompleted,
            "Metal depth-input command did not complete");
    simd_float4 *values = static_cast<simd_float4 *>(dst.contents);
    return std::vector<simd_float4>(values, values + input.size());
  }
}

static float maxDifference(const std::vector<simd_float4> &a,
                           const std::vector<simd_float4> &b) {
  float result = 0.0f;
  for (size_t i = 0; i < a.size(); ++i) {
    simd_float4 d = simd_abs(a[i] - b[i]);
    result = std::max(result, std::max(std::max(d.x, d.y), std::max(d.z, d.w)));
  }
  return result;
}

static float maxAlphaDifference(const std::vector<simd_float4> &a,
                                const std::vector<simd_float4> &b) {
  float result = 0.0f;
  for (size_t i = 0; i < a.size(); ++i)
    result = std::max(result, std::abs(a[i].w - b[i].w));
  return result;
}

static float luminanceDeviation(const std::vector<simd_float4> &image) {
  double mean = 0;
  for (const auto &p : image)
    mean += (p.x + p.y + p.z) / 3.0;
  mean /= image.size();
  double deviation = 0;
  for (const auto &p : image)
    deviation += std::abs((p.x + p.y + p.z) / 3.0 - mean);
  return float(deviation / image.size());
}

static float meanLuminance(const std::vector<simd_float4> &image) {
  double mean = 0.0;
  for (const auto &p : image)
    mean += (p.x + p.y + p.z) / 3.0;
  return float(mean / image.size());
}

static float meanChromaSpread(const std::vector<simd_float4> &image) {
  double spread = 0.0;
  for (const auto &p : image) {
    float high = std::max(p.x, std::max(p.y, p.z));
    float low = std::min(p.x, std::min(p.y, p.z));
    spread += high - low;
  }
  return float(spread / image.size());
}

static float logEncode(float x, float base, float a, float b, float c, float d,
                       float cut, float e = 0.0f) {
  float atCut = c * std::log(a * cut + b) / std::log(base) + d;
  float slope = e > 0.0f ? e : c * a / ((a * cut + b) * std::log(base));
  return x > cut ? c * std::log(a * x + b) / std::log(base) + d
                 : atCut + slope * (x - cut);
}

static float logDecode(float y, float base, float a, float b, float c, float d,
                       float cut, float e = 0.0f) {
  float atCut = c * std::log(a * cut + b) / std::log(base) + d;
  float slope = e > 0.0f ? e : c * a / ((a * cut + b) * std::log(base));
  return y > atCut ? (std::pow(base, (y - d) / c) - b) / a
                   : cut + (y - atCut) / slope;
}

static float encodeWorking(float v, uint32_t space) {
  switch (space) {
  case LDBWorkingColorSpaceACEScct:
    return v > 0.0078125f ? (std::log2(v) + 9.72f) / 17.52f
                          : 10.5402377416545f * v + 0.0729055341958355f;
  case LDBWorkingColorSpaceDaVinciIntermediate:
    return logEncode(v, 2, 1, .0075f, .07329248f, .51304736f, .00262409f,
                     10.44426855f);
  case LDBWorkingColorSpaceARRILogC3EI800:
    return logEncode(v, 10, 5.55555555555556f, .0522722750251688f,
                     .247189638318671f, .385536998692443f, .0105909904954696f);
  case LDBWorkingColorSpaceARRILogC4:
    return logEncode(v, 2, 2231.82630906769f, 64, .0647954196341293f,
                     -.295908392682586f, -.0180569961199113f);
  default:
    return v;
  }
}

static float decodeWorking(float v, uint32_t space) {
  switch (space) {
  case LDBWorkingColorSpaceACEScct:
    return v > .155251141552511f ? std::exp2(v * 17.52f - 9.72f)
                                 : (v - .0729055341958355f) / 10.5402377416545f;
  case LDBWorkingColorSpaceDaVinciIntermediate:
    return logDecode(v, 2, 1, .0075f, .07329248f, .51304736f, .00262409f,
                     10.44426855f);
  case LDBWorkingColorSpaceARRILogC3EI800:
    return logDecode(v, 10, 5.55555555555556f, .0522722750251688f,
                     .247189638318671f, .385536998692443f, .0105909904954696f);
  case LDBWorkingColorSpaceARRILogC4:
    return logDecode(v, 2, 2231.82630906769f, 64, .0647954196341293f,
                     -.295908392682586f, -.0180569961199113f);
  default:
    return v;
  }
}

int main(int argc, char **argv) {
  if (argc == 3) {
    std::freopen(argv[2], "w", stdout);
    std::freopen(argv[2], "a", stderr);
  }
  @autoreleasepool {
    require(argc == 2 || argc == 3,
            "usage: ldb-optics-tests LDBOptics.metallib [result-log]");
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    require(device != nil, "No Metal device found");
    id<MTLCommandQueue> queue = [device newCommandQueue];
    NSURL *libraryURL =
        [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    LDBOpticsEngine engine(device, libraryURL);
    require(engine.valid(), engine.errorMessage());

    constexpr uint32_t width = 64, height = 48;
    std::vector<simd_float4> image(width * height);
    for (uint32_t y = 0; y < height; ++y) {
      for (uint32_t x = 0; x < width; ++x) {
        float fx = float(x) / float(width - 1);
        float fy = float(y) / float(height - 1);
        image[y * width + x] = {
            fx, fy,
            0.25f + 2.0f * ((x == width / 2 && y == height / 2) ? 1.0f : 0.0f),
            1.0f};
      }
    }

    auto neutral = LDBNeutralOpticsParameters(width, height);
    auto neutralOut =
        render(engine, device, queue, image, width, height, neutral);
    require(maxDifference(image, neutralOut) < 1e-5f,
            "Neutral state must be identity");

    auto zeroBlend = neutral;
    zeroBlend.distortionK1 = -0.2f;
    zeroBlend.vignetteOptical = 1.0f;
    zeroBlend.effectBlend = 0.0f;
    auto zeroBlendOut =
        render(engine, device, queue, image, width, height, zeroBlend);
    require(maxDifference(image, zeroBlendOut) < 1e-5f,
            "Zero blend must be identity");

    auto vignette = neutral;
    vignette.vignetteNatural = 0.8f;
    auto vignetteOut =
        render(engine, device, queue, image, width, height, vignette);
    float center = vignetteOut[(height / 2) * width + width / 2].x;
    float corner = vignetteOut[0].x;
    require(center > corner,
            "Vignette must attenuate corners more than center");

    auto distortion = neutral;
    distortion.distortionK1 = -0.18f;
    auto distortionOut =
        render(engine, device, queue, image, width, height, distortion);
    require(maxDifference(image, distortionOut) > 0.01f,
            "Distortion must alter a spatial gradient");
    auto secondaryDistortion = neutral;
    secondaryDistortion.distortionK2 = .5f;
    auto moustacheDistortion = neutral;
    moustacheDistortion.moustacheK3 = .35f;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, secondaryDistortion)) > .001f,
            "Secondary distortion must respond within its UI range");
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, moustacheDistortion)) > .001f,
            "Moustache distortion must respond within its UI range");
    auto gatedGeometry = neutral;
    gatedGeometry.distortionK1 = .2f;
    gatedGeometry.geometryFieldAmount = 1.0f;
    gatedGeometry.responseFieldOnset = .45f;
    gatedGeometry.responseFieldFalloff = .5f;
    auto gatedGeometryOut = render(engine, device, queue, image, width, height,
                                   gatedGeometry);
    require(maxDifference(image, gatedGeometryOut) > .001f,
            "Field-gated geometry must deform the perimeter");
    auto peripheralGeometry = neutral;
    peripheralGeometry.geometryFieldAmount = 1.0f;
    peripheralGeometry.responseFieldOnset = .3f;
    peripheralGeometry.responseFieldFalloff = .55f;
    peripheralGeometry.peripheralStretch = .8f;
    peripheralGeometry.peripheralWarp = .9f;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, peripheralGeometry)) > .001f,
            "Peripheral stretch and irregular warp must work without barrel distortion");
    auto refractive = neutral;
    refractive.refractiveIrregularity = 1.0f;
    refractive.refractiveScale = 1.2f;
    refractive.refractiveEdgeBias = .6f;
    refractive.refractiveAnisotropy = .4f;
    refractive.refractiveRotation = 31;
    refractive.refractiveDispersion = .8f;
    refractive.refractiveSeed = 123;
    auto refractiveOut = render(engine, device, queue, image, width, height,
                                refractive);
    require(maxDifference(image, refractiveOut) > .001f,
            "Refractive irregularity must create local displacement");
    require(maxDifference(refractiveOut,
                          render(engine, device, queue, image, width, height,
                                 refractive)) < 1e-7f,
            "Refractive irregularity must remain deterministic");
    auto refractiveOtherSeed = refractive;
    refractiveOtherSeed.refractiveSeed = 124;
    require(maxDifference(refractiveOut,
                          render(engine, device, queue, image, width, height,
                                 refractiveOtherSeed)) > .0001f,
            "Refractive seed must select a distinct stable field");
    auto prism = neutral;
    prism.prismAmount = 1.0f;
    prism.prismDirection = 0.0f;
    prism.prismDispersion = .75f;
    prism.prismEdgeBias = .55f;
    prism.prismSoftness = .35f;
    auto prismOut = render(engine, device, queue, image, width, height, prism);
    require(maxDifference(image, prismOut) > .001f,
            "Prism Amount must create coherent edge refraction");
    auto prismOpposite = prism;
    prismOpposite.prismDirection = 180.0f;
    require(maxDifference(prismOut,
                          render(engine, device, queue, image, width, height,
                                 prismOpposite)) > .001f,
            "Prism Direction must select the refracted edge");
    auto prismAchromatic = prism;
    prismAchromatic.prismDispersion = 0.0f;
    require(maxDifference(prismOut,
                          render(engine, device, queue, image, width, height,
                                 prismAchromatic)) > .0001f,
            "Prism Dispersion must independently separate wavelengths");
    auto prismHard = prism;
    prismHard.prismSoftness = .03f;
    require(maxDifference(prismOut,
                          render(engine, device, queue, image, width, height,
                                 prismHard)) > .0001f,
            "Prism Softness must shape the edge transition");
    auto anamorphicField = distortion;
    anamorphicField.anamorphicSqueeze = 1.8f;
    require(
        maxDifference(distortionOut, render(engine, device, queue, image, width,
                                            height, anamorphicField)) > .001f,
        "Anamorphic field must shape its documented parent distortion");
    auto anamorphicExtreme = distortion;
    anamorphicExtreme.anamorphicSqueeze = 4.0f;
    require(maxDifference(render(engine, device, queue, image, width, height,
                                 anamorphicField),
                          render(engine, device, queue, image, width, height,
                                 anamorphicExtreme)) > .001f,
            "Expanded Anamorphic Field range must continue shaping off-axis "
            "effects");
    auto cylindricalDistortion = neutral;
    cylindricalDistortion.anamorphicDistortion = .55f;
    auto cylindricalOut = render(engine, device, queue, image, width, height,
                                 cylindricalDistortion);
    require(maxDifference(image, cylindricalOut) > .001f,
            "Anamorphic Distortion must act independently from ordinary "
            "distortion");
    auto inverseCylindrical = neutral;
    inverseCylindrical.anamorphicDistortion = -.55f;
    require(maxDifference(cylindricalOut,
                          render(engine, device, queue, image, width, height,
                                 inverseCylindrical)) > .001f,
            "Signed Anamorphic Distortion must reverse its field response");
    auto shiftedCenter = distortion;
    shiftedCenter.opticalCenter = {.35f, .6f};
    require(maxDifference(distortionOut, render(engine, device, queue, image,
                                                width, height, shiftedCenter)) >
                .001f,
            "Optical Center must reposition field effects");

    auto shapedField = neutral;
    shapedField.cornerSharpnessLoss = 1.0f;
    auto shapedFieldOut =
        render(engine, device, queue, image, width, height, shapedField);
    auto shiftedField = shapedField;
    shiftedField.fieldCenter = {.28f, .66f};
    auto shiftedFieldOut =
        render(engine, device, queue, image, width, height, shiftedField);
    require(maxDifference(shapedFieldOut, shiftedFieldOut) > .001f,
            "Field Center must move off-axis focus independently");
    auto aspectField = shapedField;
    aspectField.fieldAspect = 2.4f;
    auto rotatedField = aspectField;
    rotatedField.fieldRotation = 53.0f;
    auto aspectFieldOut =
        render(engine, device, queue, image, width, height, aspectField);
    require(maxDifference(shapedFieldOut, aspectFieldOut) > .001f,
            "Field Aspect must shape the off-axis response");
    require(maxDifference(aspectFieldOut, render(engine, device, queue, image,
                                                 width, height, rotatedField)) >
                .001f,
            "Field Rotation must rotate an asymmetric off-axis response");
    auto fieldOnly = neutral;
    fieldOnly.fieldCenter = {.25f, .7f};
    fieldOnly.fieldAspect = 2;
    fieldOnly.fieldRotation = 45;
    require(
        maxDifference(image, render(engine, device, queue, image, width, height,
                                    fieldOnly)) < 1e-5f,
        "Field Shape without a parent optical response must remain neutral");
    auto responseOnly = neutral;
    responseOnly.responseHighlightKnee = 1;
    responseOnly.responseFieldOnset = .4f;
    responseOnly.responseFieldFalloff = .7f;
    responseOnly.responseDefocusOnset = .2f;
    responseOnly.responseDefocusFalloff = .8f;
    responseOnly.responseScatterEdgeProtection = 0;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, responseOnly)) < 1e-5f,
            "Advanced Responses without a parent optical response must remain "
            "neutral");
    auto captureZero = shapedField;
    captureZero.captureFocalLength = 18;
    captureZero.captureAperture = 1.0f;
    captureZero.captureFocusDistance = .25f;
    captureZero.captureGateWidth = 24;
    captureZero.captureInfluence = 0;
    require(maxDifference(shapedFieldOut, render(engine, device, queue, image,
                                                 width, height, captureZero)) <
                1e-7f,
            "Capture mapping at zero influence must preserve direct controls "
            "exactly");
    auto captureWideOpen = captureZero;
    captureWideOpen.captureInfluence = 1;
    require(maxDifference(shapedFieldOut,
                          render(engine, device, queue, image, width, height,
                                 captureWideOpen)) > .001f,
            "Capture mapping must reshape an active direct optical response");
    auto neutralLook = neutral;
    neutralLook.lookCharacter = 1;
    neutralLook.lookVintageBias = 1;
    neutralLook.lookVintageCaricatureBias = 1;
    neutralLook.lookExoticBias = 1;
    neutralLook.lookAnamorphicBias = 1;
    neutralLook.lookInfluence = 0;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, neutralLook)) < 1e-5f,
            "Look mapping at zero influence must remain neutral");
    auto characterLook = neutral;
    characterLook.lookInfluence = 1;
    characterLook.lookCharacter = .5f;
    auto characterLookOut =
        render(engine, device, queue, image, width, height, characterLook);
    require(maxDifference(image, characterLookOut) > .001f,
            "Look mapping must create a coordinated editable optical response");
    auto editedCharacterLook = characterLook;
    editedCharacterLook.cornerSharpnessLoss += .4f;
    require(maxDifference(characterLookOut,
                          render(engine, device, queue, image, width, height,
                                 editedCharacterLook)) > .001f,
            "Direct controls must remain editable on top of Look mapping");
    std::vector<simd_float4> grayImage = image;
    for (auto &pixel : grayImage) {
      float gray = (pixel.x + pixel.y + pixel.z) / 3.0f;
      pixel = {gray, gray, gray, pixel.w};
    }
    auto characterChromatic = neutral;
    characterChromatic.lookInfluence = 1;
    characterChromatic.lookCharacter = 1;
    auto vintageChromatic = neutral;
    vintageChromatic.lookInfluence = 1;
    vintageChromatic.lookVintageBias = 1;
    auto vintageCaricature = neutral;
    vintageCaricature.lookInfluence = 1;
    vintageCaricature.lookVintageCaricatureBias = 1;
    auto exoticChromatic = neutral;
    exoticChromatic.lookInfluence = 1;
    exoticChromatic.lookExoticBias = 1;
    auto anamorphicChromatic = neutral;
    anamorphicChromatic.lookInfluence = 1;
    anamorphicChromatic.lookAnamorphicBias = 1;
    float characterSpread = meanChromaSpread(render(
        engine, device, queue, grayImage, width, height, characterChromatic));
    float vintageSpread = meanChromaSpread(render(
        engine, device, queue, grayImage, width, height, vintageChromatic));
    auto vintageCaricatureOut = render(engine, device, queue, grayImage, width,
                                       height, vintageCaricature);
    float vintageCaricatureSpread = meanChromaSpread(vintageCaricatureOut);
    float exoticSpread = meanChromaSpread(render(
        engine, device, queue, grayImage, width, height, exoticChromatic));
    auto anamorphicLookOut = render(engine, device, queue, grayImage, width,
                                    height, anamorphicChromatic);
    float anamorphicSpread = meanChromaSpread(anamorphicLookOut);
    require(
        characterSpread > 1e-5f && vintageSpread > characterSpread &&
            vintageCaricatureSpread > vintageSpread &&
            exoticSpread > characterSpread &&
            anamorphicSpread > characterSpread,
        "Look biases must add progressive, differentiated chromatic character");
    require(characterSpread < .08f && vintageSpread < .20f &&
                vintageCaricatureSpread < .28f && exoticSpread < .20f &&
                anamorphicSpread < .25f,
            "Look chromatic character must remain below detached-channel "
            "ghosting strength");
    require(maxDifference(render(engine, device, queue, grayImage, width,
                                 height, vintageChromatic),
                          vintageCaricatureOut) > .001f,
            "Vintage Caricature must be visibly stronger than Vintage Bias");
    require(maxDifference(grayImage, anamorphicLookOut) > .001f,
            "Classic 2x Anamorphic Bias must create a visible coordinated "
            "response");
    auto lateFieldResponse = shapedField;
    lateFieldResponse.responseFieldOnset = .80f;
    lateFieldResponse.responseFieldFalloff = 1.40f;
    require(maxDifference(shapedFieldOut,
                          render(engine, device, queue, image, width, height,
                                 lateFieldResponse)) > .001f,
            "Field Onset and Falloff must reshape active off-axis response");
    auto variationChildrenOnly = neutral;
    variationChildrenOnly.variationFieldAsymmetry = 1;
    variationChildrenOnly.variationChromaticAsymmetry = 1;
    variationChildrenOnly.variationTransmissionUnevenness = 1;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, variationChildrenOnly)) < 1e-5f,
            "Variation children must require Variation Amount");
    auto variedField = shapedField;
    variedField.variationAmount = 1;
    variedField.variationSeed = 17;
    variedField.variationFieldAsymmetry = 1;
    auto variedFieldOut =
        render(engine, device, queue, image, width, height, variedField);
    require(maxDifference(shapedFieldOut, variedFieldOut) > .001f,
            "Field Asymmetry must alter an active off-axis response");
    require(maxDifference(variedFieldOut, render(engine, device, queue, image,
                                                 width, height, variedField)) <
                1e-7f,
            "Variation must be deterministic for the same seed");
    auto otherSeed = variedField;
    otherSeed.variationSeed = 18;
    require(maxDifference(variedFieldOut, render(engine, device, queue, image,
                                                 width, height, otherSeed)) >
                .0001f,
            "Variation Seed must select a distinct stable lens instance");

    auto wornElement = neutral;
    wornElement.frontHaze = .7f;
    wornElement.cleaningMarks = 1.0f;
    wornElement.scratchAmount = .8f;
    wornElement.scratchDirection = 27.0f;
    wornElement.damageScale = 1.3f;
    wornElement.coatingWear = .7f;
    wornElement.coatingWearScale = 1.4f;
    wornElement.damageSeed = 1234;
    auto wornElementOut = render(engine, device, queue, image, width, height,
                                 wornElement);
    require(maxDifference(image, wornElementOut) > .001f,
            "Front element wear must alter scatter and transmission");
    auto hazeOnly = neutral;
    hazeOnly.frontHaze = 1.0f;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, hazeOnly)) > .0001f,
            "Front Haze must independently add highlight veiling");
    auto marksOnly = neutral;
    marksOnly.cleaningMarks = 1.0f;
    marksOnly.damageScale = 1.3f;
    marksOnly.damageSeed = 1234;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, marksOnly)) > .0001f,
            "Cleaning Marks must independently alter transmission and scatter");
    auto scratchesOnly = neutral;
    scratchesOnly.scratchAmount = 1.0f;
    scratchesOnly.scratchDirection = 27.0f;
    scratchesOnly.damageScale = 1.3f;
    scratchesOnly.damageSeed = 1234;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, scratchesOnly)) > .0001f,
            "Deep Scratches must independently alter transmission and scatter");
    auto coatingOnly = neutral;
    coatingOnly.coatingWear = 1.0f;
    coatingOnly.coatingWearScale = 1.4f;
    coatingOnly.damageSeed = 1234;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, coatingOnly)) > .0001f,
            "Coating Wear must independently alter local transmission and scatter");
    require(maxDifference(wornElementOut,
                          render(engine, device, queue, image, width, height,
                                 wornElement)) < 1e-7f,
            "Front element wear must remain fixed for the same seed");
    auto differentDamage = wornElement;
    differentDamage.damageSeed = 4321;
    require(maxDifference(wornElementOut,
                          render(engine, device, queue, image, width, height,
                                 differentDamage)) > .0001f,
            "Damage Seed must select a distinct stable wear pattern");

    auto dirtChildrenOnly = neutral;
    dirtChildrenOnly.internalDirtScale = 3.0f;
    dirtChildrenOnly.internalDirtSmear = 1.0f;
    dirtChildrenOnly.internalDirtScatter = 2.0f;
    dirtChildrenOnly.internalDirtSeed = 82;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, dirtChildrenOnly)) < 1e-7f,
            "Internal contamination child controls must require a nonzero amount");
    auto internalDirt = neutral;
    internalDirt.internalDirtAmount = 1.5f;
    internalDirt.internalDirtScale = 1.4f;
    internalDirt.internalDirtSmear = .45f;
    internalDirt.internalDirtScatter = 1.2f;
    internalDirt.internalDirtSeed = 31415;
    auto internalDirtOut = render(engine, device, queue, image, width, height,
                                  internalDirt);
    require(maxDifference(image, internalDirtOut) > .001f,
            "Internal contamination must create visible optical diffusion");
    auto internalDensityOnly = internalDirt;
    internalDensityOnly.internalDirtScatter = 0.0f;
    auto internalDensityOnlyOut = render(engine, device, queue, image, width,
                                         height, internalDensityOnly);
    require(maxDifference(image, internalDensityOnlyOut) > .0001f,
            "Internal contamination density must remain active without scatter");
    require(maxDifference(internalDensityOnlyOut, internalDirtOut) > .0001f,
            "Internal Scatter must independently add smooth highlight redistribution");
    auto conservativeDensity = internalDensityOnly;
    conservativeDensity.internalDirtAmount = 1.0f;
    auto mediumDensity = internalDensityOnly;
    mediumDensity.internalDirtAmount = 5.0f;
    auto extremeDensity = internalDensityOnly;
    extremeDensity.internalDirtAmount = 10.0f;
    auto conservativeDensityOut = render(engine, device, queue, image, width,
                                         height, conservativeDensity);
    auto mediumDensityOut = render(engine, device, queue, image, width, height,
                                   mediumDensity);
    auto extremeDensityOut = render(engine, device, queue, image, width, height,
                                    extremeDensity);
    require(meanLuminance(conservativeDensityOut) > meanLuminance(mediumDensityOut)
                && meanLuminance(mediumDensityOut) > meanLuminance(extremeDensityOut),
            "Internal Dirt Amount must increase monotonically through the extended range");
    for (const auto &pixel : extremeDensityOut)
      require(std::isfinite(pixel.x) && std::isfinite(pixel.y)
                  && std::isfinite(pixel.z) && pixel.x >= 0.0f
                  && pixel.y >= 0.0f && pixel.z >= 0.0f,
              "Extreme Internal Dirt Amount must remain finite and non-negative");
    auto softDensityOnly = internalDensityOnly;
    softDensityOnly.internalDirtSoftness = 1.0f;
    require(maxDifference(internalDensityOnlyOut,
                          render(engine, device, queue, image, width, height,
                                 softDensityOnly)) > .01f,
            "Cloud Softness must remain visibly effective without Internal Scatter");
    require(maxDifference(internalDirtOut,
                          render(engine, device, queue, image, width, height,
                                 internalDirt)) < 1e-7f,
            "Internal contamination must remain deterministic for one seed");
    auto softCloud = internalDirt;
    softCloud.internalDirtSoftness = 1.0f;
    require(maxDifference(internalDirtOut,
                          render(engine, device, queue, image, width, height,
                                 softCloud)) > .0001f,
            "Cloud Softness must reshape internal optical density");
    auto complexCloud = internalDirt;
    complexCloud.internalDirtComplexity = 1.0f;
    require(maxDifference(internalDirtOut,
                          render(engine, device, queue, image, width, height,
                                 complexCloud)) > .005f,
            "Cloud Complexity must add deterministic multi-scale structure");
    auto internalWithWear = internalDirt;
    internalWithWear.frontHaze = .7f;
    internalWithWear.cleaningMarks = .8f;
    internalWithWear.scratchAmount = .55f;
    internalWithWear.coatingWear = .7f;
    require(maxDifference(internalDirtOut,
                          render(engine, device, queue, image, width, height,
                                 internalWithWear)) > .0001f,
            "Internal contamination must coexist with front element wear");
    auto internalWithScatter = internalDirt;
    internalWithScatter.bloomThreshold = .5f;
    internalWithScatter.bloomEnergy = .45f;
    internalWithScatter.bloomRadius = 10.0f;
    internalWithScatter.glareEnergy = .25f;
    internalWithScatter.glareRadius = 24.0f;
    require(maxDifference(internalDirtOut,
                          render(engine, device, queue, image, width, height,
                                 internalWithScatter)) > .0001f,
            "Internal contamination must feed later bloom and glare stages");
    require(maxAlphaDifference(image, internalDirtOut) < 1e-6f,
            "Internal contamination must preserve alpha");

    auto chromatic = neutral;
    chromatic.lateralCARed = 0.8f;
    chromatic.lateralCABlue = -0.8f;
    auto chromaticOut =
        render(engine, device, queue, image, width, height, chromatic);
    require(maxDifference(image, chromaticOut) > 0.001f,
            "Chromatic aberration must alter channels");
    auto fieldChromatic = chromatic;
    fieldChromatic.responseFieldOnset = .30f;
    fieldChromatic.responseFieldFalloff = .85f;
    std::vector<simd_float4> chromaPattern(width * height);
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float v = ((x / 2 + y / 2) & 1) ? .85f : .15f;
        chromaPattern[size_t(y) * width + x] = {v, v, v, 1};
      }
    auto fieldChromaticOut =
        render(engine, device, queue, chromaPattern, width, height,
               fieldChromatic);
    float chromaCentreDifference = 0, chromaEdgeDifference = 0;
    uint32_t chromaCentreCount = 0, chromaEdgeCount = 0;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float nx = (float(x) + .5f) / float(width) - .5f;
        float ny = (float(y) + .5f) / float(height) - .5f;
        float r = std::sqrt(nx * nx + ny * ny) * 2.0f;
        auto sourceSample = chromaPattern[size_t(y) * width + x];
        auto outputSample = fieldChromaticOut[size_t(y) * width + x];
        float d = std::abs(outputSample.x - sourceSample.x)
                + std::abs(outputSample.z - sourceSample.z);
        if (r < .15f) { chromaCentreDifference += d; ++chromaCentreCount; }
        if (r > .80f) { chromaEdgeDifference += d; ++chromaEdgeCount; }
      }
    chromaCentreDifference /= float(chromaCentreCount);
    chromaEdgeDifference /= float(chromaEdgeCount);
    require(chromaEdgeDifference > .001f &&
                chromaEdgeDifference > chromaCentreDifference * 3.0f,
            "Lateral chromatic aberration must follow the gradual Field "
            "envelope and preserve its centre");
    auto blurredChromatic = fieldChromatic;
    blurredChromatic.cornerSharpnessLoss = 2.0f;
    blurredChromatic.fieldCurvature = 2.0f;
    blurredChromatic.radialSmear = 1.25f;
    blurredChromatic.tangentialSmear = 1.55f;
    blurredChromatic.apertureResponse = 1.0f;
    blurredChromatic.apertureRadius = 24.0f;
    auto blurredAchromatic = blurredChromatic;
    blurredAchromatic.lateralCARed = 0.0f;
    blurredAchromatic.lateralCABlue = 0.0f;
    auto blurredChromaticOut = render(engine, device, queue, chromaPattern,
                                      width, height, blurredChromatic);
    auto blurredAchromaticOut = render(engine, device, queue, chromaPattern,
                                       width, height, blurredAchromatic);
    float combinedCentreDifference = 0, combinedEdgeDifference = 0;
    uint32_t combinedCentreCount = 0, combinedEdgeCount = 0;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float nx = (float(x) + .5f) / float(width) - .5f;
        float ny = (float(y) + .5f) / float(height) - .5f;
        float r = std::sqrt(nx * nx + ny * ny) * 2.0f;
        auto ca = blurredChromaticOut[size_t(y) * width + x];
        auto noCA = blurredAchromaticOut[size_t(y) * width + x];
        float d = std::abs(ca.x - noCA.x) + std::abs(ca.z - noCA.z);
        if (r < .15f) { combinedCentreDifference += d; ++combinedCentreCount; }
        if (r > .80f) { combinedEdgeDifference += d; ++combinedEdgeCount; }
      }
    combinedCentreDifference /= float(combinedCentreCount);
    combinedEdgeDifference /= float(combinedEdgeCount);
    require(combinedEdgeDifference > .001f &&
                combinedEdgeDifference > combinedCentreDifference * 3.0f,
            "Strong edge defocus must not suppress field-gated chromatic "
            "aberration");
    auto independentChromatic = blurredChromatic;
    independentChromatic.chromaticFieldOnset = .32f;
    independentChromatic.chromaticFieldFalloff = .54f;
    auto independentAchromatic = blurredAchromatic;
    independentAchromatic.chromaticFieldOnset = .32f;
    independentAchromatic.chromaticFieldFalloff = .54f;
    require(maxDifference(blurredAchromaticOut,
                          render(engine, device, queue, chromaPattern, width,
                                 height, independentAchromatic)) < 1e-6f,
            "Independent chromatic envelope must not move the focus field");
    auto independentOut = render(engine, device, queue, chromaPattern, width,
                                 height, independentChromatic);
    require(maxDifference(blurredChromaticOut, independentOut) > .001f,
            "Independent chromatic envelope must alter the colour field");
    auto redOnly = neutral;
    redOnly.lateralCARed = 1;
    auto blueOnly = neutral;
    blueOnly.lateralCABlue = -1;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, redOnly)) > .0001f,
            "Red fringing must respond independently");
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, blueOnly)) > .0001f,
            "Blue fringing must respond independently");
    auto anamorphicCA = neutral;
    anamorphicCA.anamorphicAberration = 1.0f;
    auto anamorphicCAOut =
        render(engine, device, queue, image, width, height, anamorphicCA);
    require(
        maxDifference(image, anamorphicCAOut) > .0001f,
        "Anamorphic Aberration must create independent horizontal separation");
    auto inverseAnamorphicCA = neutral;
    inverseAnamorphicCA.anamorphicAberration = -1.0f;
    require(maxDifference(anamorphicCAOut,
                          render(engine, device, queue, image, width, height,
                                 inverseAnamorphicCA)) > .0001f,
            "Signed Anamorphic Aberration must reverse channel separation");
    auto variedChromatic = neutral;
    variedChromatic.variationAmount = 1;
    variedChromatic.variationSeed = 9;
    variedChromatic.variationChromaticAsymmetry = 1;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, variedChromatic)) > .0001f,
            "Chromatic Asymmetry must produce a seeded decentered response");
    auto longitudinal = neutral;
    longitudinal.longitudinalCA = 1.0f;
    longitudinal.longitudinalCARadius = 4.0f;
    auto longitudinalOut =
        render(engine, device, queue, image, width, height, longitudinal);
    require(maxDifference(image, longitudinalOut) > .0001f,
            "Longitudinal CA must create near/far focus chroma");
    auto longitudinalRadius = longitudinal;
    longitudinalRadius.longitudinalCARadius = 10.0f;
    require(
        maxDifference(longitudinalOut,
                      render(engine, device, queue, image, width, height,
                             longitudinalRadius)) > .0001f,
        "Longitudinal CA radius must select a distinct focus-transition scale");
    auto longitudinalColors = longitudinal;
    longitudinalColors.nearFocusColor = {.4f, 1.0f, .5f};
    longitudinalColors.farFocusColor = {1.0f, .35f, .75f};
    require(maxDifference(longitudinalOut,
                          render(engine, device, queue, image, width, height,
                                 longitudinalColors)) > .0001f,
            "Longitudinal near/far colors must independently shape chroma");
    auto longitudinalCreative = longitudinal;
    longitudinalCreative.longitudinalCA = 2.0f;
    require(maxDifference(longitudinalOut,
                          render(engine, device, queue, image, width, height,
                                 longitudinalCreative)) > .0001f,
            "Longitudinal CA creative range must remain visibly progressive");
    auto depthPacked = image;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x)
        depthPacked[y * width + x].w = float(x) / float(width - 1);
    auto depthDiagnostic = neutral;
    depthDiagnostic.depthMode = 2;
    depthDiagnostic.depthChannel = 4;
    depthDiagnostic.processingFlags = LDBDiagnosticDepth;
    auto depthOut = render(engine, device, queue, depthPacked, width, height,
                           depthDiagnostic);
    require(
        depthOut.front().x < .01f && depthOut[width - 1].x > .99f,
        "Depth diagnostic must display normalized near-black auxiliary input");
    auto depthRGB = image;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float z = float(x) / float(width - 1);
        depthRGB[y * width + x] = {z, z, z, 1.0f};
      }
    auto luminanceDepth = depthDiagnostic;
    luminanceDepth.depthChannel = 0;
    auto secondInputOut = renderWithDepth(engine, device, queue, image,
                                           depthRGB, width, height,
                                           luminanceDepth);
    require(maxDifference(depthOut, secondInputOut) < 1e-6f,
            "Second RGB depth input must match the internal depth carrier");
    std::puts("PASS: dedicated second RGB depth-map input");
    auto defocusDiagnostic = depthDiagnostic;
    defocusDiagnostic.processingFlags = LDBDiagnosticDefocus;
    auto defocusOut = render(engine, device, queue, depthPacked, width, height,
                             defocusDiagnostic);
    require(defocusOut[width / 2].x < .01f &&
                defocusOut.front().x > .9f && defocusOut[width - 1].x > .9f,
            "Defocus Amount diagnostic must show the Focus Depth plane");
    std::vector<simd_float4> diagnosticStep(width * height,
                                            simd_float4{0, 0, 0, .2f});
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = width / 2; x < width; ++x)
        diagnosticStep[size_t(y) * width + x].w = .8f;
    auto rejectionDiagnostic = depthDiagnostic;
    rejectionDiagnostic.processingFlags = LDBDiagnosticDepthRejection;
    auto rejectionOut = render(engine, device, queue, diagnosticStep, width,
                               height, rejectionDiagnostic);
    size_t edgeProbe = size_t(height / 2) * width + width / 2;
    size_t flatProbe = size_t(height / 2) * width + width / 4;
    require(rejectionOut[edgeProbe].x > .2f &&
                rejectionOut[flatProbe].x < .01f,
            "Depth Rejection diagnostic must isolate map boundaries");
    auto inverseDepth = depthDiagnostic;
    inverseDepth.depthMode = 1;
    auto inverseOut =
        render(engine, device, queue, depthPacked, width, height, inverseDepth);
    require(inverseOut.front().x > .99f && inverseOut[width - 1].x < .01f,
            "Depth interpretation must support near-white inversion");
    auto depthLongitudinal = longitudinal;
    depthLongitudinal.depthMode = 2;
    depthLongitudinal.depthChannel = 4;
    depthLongitudinal.depthFocus = .5f;
    auto depthLongitudinalOut = render(engine, device, queue, depthPacked,
                                       width, height, depthLongitudinal);
    require(maxDifference(longitudinalOut, depthLongitudinalOut) > .0001f,
            "External depth must drive near/far longitudinal CA");
    auto shiftedDepthFocus = depthLongitudinal;
    shiftedDepthFocus.depthFocus = .15f;
    require(maxDifference(depthLongitudinalOut,
                          render(engine, device, queue, depthPacked, width,
                                 height, shiftedDepthFocus)) > .0001f,
            "Focus Depth must move the longitudinal CA focus plane");
    auto broadDefocusResponse = depthLongitudinal;
    broadDefocusResponse.responseDefocusOnset = 0.0f;
    broadDefocusResponse.responseDefocusFalloff = .12f;
    require(maxDifference(depthLongitudinalOut,
                          render(engine, device, queue, depthPacked, width,
                                 height, broadDefocusResponse)) > .0001f,
            "Defocus Onset and Falloff must reshape active depth response");
    auto invertedDepthLongitudinal = depthLongitudinal;
    invertedDepthLongitudinal.depthMode = 1;
    require(maxDifference(depthLongitudinalOut,
                          render(engine, device, queue, depthPacked, width,
                                 height, invertedDepthLongitudinal)) > .0001f,
            "Near-white and near-black depth must swap longitudinal tint "
            "assignment");
    auto ignoredDepthFocus = longitudinal;
    ignoredDepthFocus.depthFocus = .1f;
    require(maxDifference(longitudinalOut,
                          render(engine, device, queue, image, width, height,
                                 ignoredDepthFocus)) < 1e-7f,
            "Depth-Free optics must ignore Focus Depth");

    auto transmission = neutral;
    transmission.transmissionColor = {1.0f, 0.7f, 0.5f};
    transmission.transmissionColorAmount = 1.0f;
    auto transmissionOut =
        render(engine, device, queue, image, width, height, transmission);
    size_t sampleIndex = (height / 3) * width + width / 3;
    require(transmissionOut[sampleIndex].y < image[sampleIndex].y,
            "Transmission color must attenuate selected channels");
    auto density = neutral;
    density.transmissionDensity = 1.0f;
    auto densityOut =
        render(engine, device, queue, image, width, height, density);
    require(densityOut[sampleIndex].x < image[sampleIndex].x,
            "Transmission Density must alter lens throughput");
    auto lowContrast = neutral;
    lowContrast.transmissionContrast = -.8f;
    auto lowContrastOut =
        render(engine, device, queue, image, width, height, lowContrast);
    require(maxDifference(image, lowContrastOut) > .001f,
            "Transmission Contrast must reshape tonal separation");
    std::vector<simd_float4> transmissionRamp(width * height,
                                              simd_float4{.18f, .18f, .18f, 1});
    transmissionRamp[size_t(height / 2) * width + width / 2] = {4, 4, 4, 1};
    auto softHighlights = neutral;
    softHighlights.transmissionHighlightSoftness = 1.0f;
    auto softHighlightOut = render(engine, device, queue, transmissionRamp,
                                   width, height, softHighlights);
    size_t middleSample = size_t(height / 3) * width + width / 3;
    size_t highlightSample = size_t(height / 2) * width + width / 2;
    require(std::abs(softHighlightOut[middleSample].x - .18f) < 1e-5f,
            "Transmission Highlight Softness must preserve middle grey");
    require(softHighlightOut[highlightSample].x <
                transmissionRamp[highlightSample].x,
            "Transmission Highlight Softness must compress highlights");
    auto variedTransmission = neutral;
    variedTransmission.variationAmount = 1;
    variedTransmission.variationSeed = 31;
    variedTransmission.variationTransmissionUnevenness = 1;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, variedTransmission)) > .001f,
            "Transmission Unevenness must create stable broad throughput "
            "variation");

    auto opticalVignette = neutral;
    opticalVignette.vignetteOptical = .8f;
    require(maxDifference(image, render(engine, device, queue, image, width,
                                        height, opticalVignette)) > .01f,
            "Optical vignette must respond independently");
    auto mechanicalVignette = neutral;
    mechanicalVignette.vignetteMechanical = 1;
    mechanicalVignette.imageCircleSize = .8f;
    auto mechanicalOut =
        render(engine, device, queue, image, width, height, mechanicalVignette);
    require(maxDifference(image, mechanicalOut) > .01f,
            "Mechanical vignette must respond within its UI range");
    auto circleAspect = mechanicalVignette;
    circleAspect.imageCircleAspect = 1.8f;
    auto circleSoftness = mechanicalVignette;
    circleSoftness.imageCircleSoftness = .5f;
    require(maxDifference(mechanicalOut, render(engine, device, queue, image,
                                                width, height, circleAspect)) >
                .001f,
            "Image Circle Aspect must shape Mechanical Vignette");
    require(
        maxDifference(mechanicalOut, render(engine, device, queue, image, width,
                                            height, circleSoftness)) > .001f,
        "Image Circle Softness must shape Mechanical Vignette");

    std::vector<simd_float4> impulse(width * height, simd_float4{0, 0, 0, 1});
    impulse[(height / 2) * width + width / 2] = {4, 4, 4, 1};
    auto bloom = neutral;
    bloom.bloomThreshold = 1.0f;
    bloom.bloomEnergy = 0.5f;
    bloom.bloomRadius = 8.0f;
    bloom.bloomHorizontalStretch = 1.0f;
    auto bloomOut =
        render(engine, device, queue, impulse, width, height, bloom);
    size_t adjacent = (height / 2) * width + width / 2 + 3;
    require(bloomOut[adjacent].x > 0.0f,
            "Bloom must distribute highlight energy to neighbouring pixels");
    auto bloomRadiusChanged = bloom;
    bloomRadiusChanged.bloomRadius = 20;
    auto bloomStretchChanged = bloom;
    bloomStretchChanged.bloomHorizontalStretch = 3;
    auto bloomThresholdChanged = bloom;
    bloomThresholdChanged.bloomThreshold = 3.5f;
    require(maxDifference(bloomOut, render(engine, device, queue, impulse,
                                           width, height, bloomRadiusChanged)) >
                .0001f,
            "Bloom Radius must shape active bloom");
    require(
        maxDifference(bloomOut, render(engine, device, queue, impulse, width,
                                       height, bloomStretchChanged)) > .0001f,
        "Bloom Stretch must shape active bloom");
    require(
        maxDifference(bloomOut, render(engine, device, queue, impulse, width,
                                       height, bloomThresholdChanged)) > .0001f,
        "Bloom Threshold must shape active bloom");
    std::vector<simd_float4> kneeImpulse(width * height,
                                         simd_float4{0, 0, 0, 1});
    kneeImpulse[size_t(height / 2) * width + width / 2] = {.8f, .8f, .8f, 1};
    auto hardKneeBloom = bloom;
    hardKneeBloom.bloomThreshold = 1.0f;
    auto softKneeBloom = hardKneeBloom;
    softKneeBloom.responseHighlightKnee = .5f;
    require(maxDifference(render(engine, device, queue, kneeImpulse, width,
                                 height, hardKneeBloom),
                          render(engine, device, queue, kneeImpulse, width,
                                 height, softKneeBloom)) > .00001f,
            "Highlight Knee must soften active scatter eligibility");
    std::vector<simd_float4> shadowField(
        width * height, simd_float4{.01f, .01f, .01f, 1.0f});
    auto maximumKneeBloom = hardKneeBloom;
    maximumKneeBloom.responseHighlightKnee = 4.0f;
    require(maxDifference(
                shadowField,
                render(engine, device, queue, shadowField, width, height,
                       maximumKneeBloom)) < 1e-6f,
            "Highlight Knee must not turn sub-threshold shadows into scatter");
    auto anamorphicFlare = neutral;
    anamorphicFlare.anamorphicFlareAmount = 1.0f;
    anamorphicFlare.anamorphicFlareRadius = 32.0f;
    anamorphicFlare.anamorphicFlareThreshold = 1.0f;
    anamorphicFlare.anamorphicFlareColor = {.25f, .5f, 1.0f};
    auto flareOut =
        render(engine, device, queue, impulse, width, height, anamorphicFlare);
    size_t horizontalFlare = size_t(height / 2) * width + width / 2 + 10;
    size_t verticalFlare = size_t(height / 2 + 10) * width + width / 2;
    require(flareOut[horizontalFlare].z > flareOut[verticalFlare].z,
            "Anamorphic Flare must form an independent horizontal streak");
    require(flareOut[horizontalFlare].z > flareOut[horizontalFlare].x,
            "Anamorphic Flare Color must tint the streak");
    auto shortFlare = anamorphicFlare;
    shortFlare.anamorphicFlareRadius = 12.0f;
    require(maxDifference(flareOut, render(engine, device, queue, impulse,
                                           width, height, shortFlare)) > .0001f,
            "Anamorphic Flare Radius must shape the streak independently");
    auto rejectedFlare = anamorphicFlare;
    rejectedFlare.anamorphicFlareThreshold = 8.0f;
    require(maxDifference(flareOut, render(engine, device, queue, impulse,
                                           width, height, rejectedFlare)) >
                .0001f,
            "Anamorphic Flare Threshold must control highlight eligibility");
    auto coreFlare = anamorphicFlare;
    coreFlare.anamorphicFlareCoreAmount = 1.4f;
    require(maxDifference(flareOut, render(engine, device, queue, impulse,
                                           width, height, coreFlare)) > .0001f,
            "Flare Core must independently concentrate streak energy");
    auto asymmetricFlare = anamorphicFlare;
    asymmetricFlare.anamorphicFlareAsymmetry = .8f;
    require(maxDifference(flareOut, render(engine, device, queue, impulse,
                                           width, height, asymmetricFlare)) > .0001f,
            "Flare Asymmetry must bias the streak tail");
    std::vector<simd_float4> offCentreImpulse(width * height,
                                              simd_float4{0, 0, 0, 1});
    offCentreImpulse[size_t(height / 2) * width + width / 3] = {8, 8, 8, 1};
    auto plainOffCentreFlare = render(engine, device, queue, offCentreImpulse,
                                      width, height, anamorphicFlare);
    auto ghostFlare = anamorphicFlare;
    ghostFlare.anamorphicFlareGhostAmount = 1.2f;
    ghostFlare.anamorphicFlareGhostPosition = -.72f;
    ghostFlare.anamorphicFlareGhostScale = .85f;
    ghostFlare.anamorphicFlareGhostColor = {.8f, .2f, 1.0f};
    auto ghostOut = render(engine, device, queue, offCentreImpulse, width,
                           height, ghostFlare);
    require(maxDifference(plainOffCentreFlare, ghostOut) > .0001f,
            "Flare Ghost must add a source-responsive internal reflection");
    auto ghostTrainFlare=ghostFlare;
    ghostTrainFlare.anamorphicFlareGhostCount=5.0f;
    ghostTrainFlare.anamorphicFlareGhostSpacing=14.0f;
    ghostTrainFlare.anamorphicFlareGhostScaleDecay=.82f;
    ghostTrainFlare.anamorphicFlareGhostEnergyDecay=.64f;
    auto ghostTrainOut=render(engine,device,queue,offCentreImpulse,width,height,
                              ghostTrainFlare);
    require(maxDifference(ghostOut,ghostTrainOut)>.0001f,
            "Ghost Paths must add a bounded analytic reflection train");
    auto bandedFlare = anamorphicFlare;
    bandedFlare.anamorphicFlareBandAmount = 1.0f;
    bandedFlare.anamorphicFlareBandSeparation = 8.0f;
    auto bandedOut = render(engine, device, queue, impulse, width, height,
                            bandedFlare);
    require(maxDifference(flareOut, bandedOut) > .0001f,
            "Flare Bands must add independently spaced layered streaks");
    auto thinFlare = bandedFlare;
    // Exercise thickness with a radius large enough to escape the one-pixel
    // vertical minimum in this compact fixture.
    thinFlare.anamorphicFlareRadius = 200.0f;
    thinFlare.anamorphicFlareThickness = .1f;
    auto thinFlareOut = render(engine, device, queue, impulse, width, height,
                               thinFlare);
    auto thickFlare = thinFlare;
    thickFlare.anamorphicFlareThickness = 4.0f;
    require(maxDifference(thinFlareOut, render(engine, device, queue, impulse,
                                               width, height, thickFlare)) > .00001f,
            "Flare Thickness must independently shape layered streak width");
    auto secondaryFlare = bandedFlare;
    secondaryFlare.anamorphicFlareSecondaryAmount = .8f;
    secondaryFlare.anamorphicFlareSecondaryOffset = 12.0f;
    require(maxDifference(bandedOut, render(engine, device, queue, impulse,
                                            width, height, secondaryFlare)) >
                .0001f,
            "Secondary Streak must add an independently offset flare layer");
    auto rayFlare = anamorphicFlare;
    rayFlare.diffractionRayAmount = 1.0f;
    rayFlare.diffractionRayLength = 80.0f;
    auto rayOut = render(engine, device, queue, impulse, width, height, rayFlare);
    require(rayOut[verticalFlare].z > flareOut[verticalFlare].z,
            "Vertical Rays must add source-derived diffraction energy");
    auto rayContributionAt = [&](uint32_t offset) {
      size_t sample = size_t(height / 2 + offset) * width + width / 2;
      return rayOut[sample].z - flareOut[sample].z;
    };
    require(rayContributionAt(8) > rayContributionAt(16) &&
                rayContributionAt(16) > rayContributionAt(24),
            "Analytic diffraction rays must have a smooth monotonic falloff");
    auto shortRay = rayFlare;
    shortRay.diffractionRayLength = 18.0f;
    require(maxDifference(rayOut, render(engine, device, queue, impulse,
                                         width, height, shortRay)) > .00001f,
            "Ray Length must independently shape vertical diffraction extent");
    auto diagnosticBloom = bloom;
    diagnosticBloom.processingFlags = LDBDiagnosticScatter;
    require(maxDifference(bloomOut, render(engine, device, queue, impulse,
                                           width, height, diagnosticBloom)) >
                .001f,
            "Diagnostic View must change the displayed analysis image");
    auto combinedScatter = anamorphicFlare;
    combinedScatter.bloomEnergy = .8f;
    combinedScatter.bloomRadius = 64.0f;
    combinedScatter.glareEnergy = .5f;
    combinedScatter.glareRadius = 96.0f;
    combinedScatter.sphericalHalo = .8f;
    for (uint32_t diagnosticMode = 0; diagnosticMode <= 6; ++diagnosticMode) {
        combinedScatter.processingFlags = diagnosticMode << 8;
        auto transitionOut = render(engine, device, queue, impulse, width,
                                    height, combinedScatter);
        for (const auto &sample : transitionOut)
          require(std::isfinite(sample.x) && std::isfinite(sample.y) &&
                      std::isfinite(sample.z) && std::isfinite(sample.w),
                  "Diagnostic View transitions must remain finite");
    }

    // With an explicit near-black depth map, a bright background practical
    // must not scatter through a nearer foreground silhouette. Reversing
    // the layer assignment must still allow a nearer practical to veil the
    // farther layer, matching the engine's occlusion direction.
    std::vector<simd_float4> depthScatter(width * height,
                                          simd_float4{0, 0, 0, .8f});
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width / 2; ++x)
        depthScatter[size_t(y) * width + x].w = .2f;
    depthScatter[size_t(height / 2) * width + width / 2 + 1] = {8, 8, 8, .8f};
    auto depthBloom = bloom;
    depthBloom.depthMode = 2;
    depthBloom.depthChannel = 4;
    depthBloom.bloomRadius = 10;
    depthBloom.bloomEnergy = 1;
    auto protectedBloom =
        render(engine, device, queue, depthScatter, width, height, depthBloom);
    size_t nearSide = size_t(height / 2) * width + width / 2 - 2;
    auto depthFreeBloom = depthBloom;
    depthFreeBloom.depthMode = 0;
    auto unprotectedBloom = render(engine, device, queue, depthScatter, width,
                                   height, depthFreeBloom);
    require(protectedBloom[nearSide].x < unprotectedBloom[nearSide].x * .3f,
            "Depth-aware Bloom must strongly reduce background spill across "
            "foreground");
    require(protectedBloom[nearSide].x > 0.0f,
            "Depth-aware Bloom must retain a nonzero optical veil across depth "
            "boundaries");
    auto disabledEdgeProtection = depthBloom;
    disabledEdgeProtection.responseScatterEdgeProtection = 0.0f;
    auto openBoundaryBloom = render(engine, device, queue, depthScatter, width,
                                    height, disabledEdgeProtection);
    require(openBoundaryBloom[nearSide].x > protectedBloom[nearSide].x,
            "Depth Edge Protection must control cross-layer optical spill");
    auto softDepthScatter = depthScatter;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = width / 2; x < width; ++x)
        softDepthScatter[size_t(y) * width + x].w = .27f;
    auto crispBoundaryBloom = depthBloom;
    crispBoundaryBloom.depthEdgeSoftness = 0.0f;
    auto crispProtection = render(engine, device, queue, softDepthScatter,
                                  width, height, crispBoundaryBloom);
    auto softBoundaryBloom = depthBloom;
    softBoundaryBloom.depthEdgeSoftness = 1.0f;
    auto softenedProtection = render(engine, device, queue, softDepthScatter,
                                     width, height, softBoundaryBloom);
    require(softenedProtection[nearSide].x > crispProtection[nearSide].x,
            "Depth Edge Softness must admit more response across a soft map "
            "transition");
    auto depthGlare = depthBloom;
    depthGlare.bloomEnergy = 0;
    depthGlare.glareEnergy = 1;
    depthGlare.glareRadius = 10;
    auto protectedGlare =
        render(engine, device, queue, depthScatter, width, height, depthGlare);
    auto depthFreeGlare = depthGlare;
    depthFreeGlare.depthMode = 0;
    auto unprotectedGlare = render(engine, device, queue, depthScatter, width,
                                   height, depthFreeGlare);
    require(protectedGlare[nearSide].x < unprotectedGlare[nearSide].x * .3f,
            "Depth-aware Glare must strongly reduce background spill across "
            "foreground");
    require(protectedGlare[nearSide].x > 0.0f,
            "Depth-aware Glare must retain a nonzero optical veil across depth "
            "boundaries");
    depthScatter[size_t(height / 2) * width + width / 2 - 1] = {8, 8, 8, .2f};
    depthScatter[size_t(height / 2) * width + width / 2 + 1] = {0, 0, 0, .8f};
    auto foregroundBloom =
        render(engine, device, queue, depthScatter, width, height, depthBloom);
    size_t farSide = size_t(height / 2) * width + width / 2 + 2;
    require(foregroundBloom[farSide].x > .001f,
            "Nearer Bloom must remain able to veil a farther layer");

    auto swirl = neutral;
    swirl.swirl = 0.8f;
    auto swirlOut = render(engine, device, queue, image, width, height, swirl);
    require(maxDifference(image, swirlOut) > 0.001f,
            "Swirl must alter off-axis image geometry");

    auto curvature = neutral;
    curvature.fieldCurvature = 1.0f;
    auto curvatureOut =
        render(engine, device, queue, image, width, height, curvature);
    require(maxDifference(image, curvatureOut) > 0.0001f,
            "Field curvature must alter off-axis focus");

    std::vector<simd_float4> focusPattern(width * height);
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float v = ((x / 2 + y / 2) & 1) ? 0.85f : 0.15f;
        focusPattern[size_t(y) * width + x] = {v, v, v, 1};
      }
    auto astigmatic = neutral;
    astigmatic.astigmatism = 1.0f;
    auto radialSmeared = neutral;
    radialSmeared.radialSmear = 1.0f;
    auto tangentSmeared = neutral;
    tangentSmeared.tangentialSmear = 1.0f;
    auto astigmaticOut =
        render(engine, device, queue, focusPattern, width, height, astigmatic);
    auto radialSmearedOut = render(engine, device, queue, focusPattern, width,
                                   height, radialSmeared);
    auto tangentSmearedOut = render(engine, device, queue, focusPattern, width,
                                    height, tangentSmeared);
    require(maxDifference(focusPattern, astigmaticOut) > .01f,
            "Normalized astigmatism must work without another focus control");
    require(maxDifference(focusPattern, radialSmearedOut) > .01f,
            "Normalized radial smear must work without another focus control");
    require(
        maxDifference(focusPattern, tangentSmearedOut) > .01f,
        "Normalized tangential smear must work without another focus control");
    require(
        maxDifference(radialSmearedOut, tangentSmearedOut) > .001f,
        "Radial and tangential smear must have distinct directional responses");
    auto strongAstigmatic = neutral;
    strongAstigmatic.astigmatism = 2.0f;
    require(maxDifference(astigmaticOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, strongAstigmatic)) > .001f,
            "Expanded focus-character range must remain visually effective "
            "beyond 1.0");
    auto cornerLoss = neutral;
    cornerLoss.cornerSharpnessLoss = 1;
    require(
        maxDifference(focusPattern, render(engine, device, queue, focusPattern,
                                           width, height, cornerLoss)) > .01f,
        "Corner Detail Loss must respond within its UI range");

    auto circularAperture = neutral;
    circularAperture.apertureResponse = 1;
    circularAperture.apertureRadius = 8;
    auto circularApertureOut = render(engine, device, queue, focusPattern,
                                      width, height, circularAperture);
    require(maxDifference(focusPattern, circularApertureOut) > .01f,
            "Aperture Response must work independently");
    auto depthFocusPattern = focusPattern;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x)
        depthFocusPattern[size_t(y) * width + x].w =
            float(x) / float(width - 1);
    auto depthAperture = circularAperture;
    depthAperture.depthMode = 2;
    depthAperture.depthChannel = 4;
    depthAperture.depthFocus = .5f;
    auto depthApertureOut = render(engine, device, queue, depthFocusPattern,
                                   width, height, depthAperture);
    require(
        maxDifference(circularApertureOut, depthApertureOut) > .001f,
        "External depth must modulate Aperture Response around Focus Depth");
    auto shiftedDepthAperture = depthAperture;
    shiftedDepthAperture.depthFocus = .2f;
    require(maxDifference(depthApertureOut,
                          render(engine, device, queue, depthFocusPattern,
                                 width, height, shiftedDepthAperture)) > .001f,
            "Focus Depth must move the aperture focus plane");
    auto polygonAperture = circularAperture;
    polygonAperture.apertureShape = 1;
    polygonAperture.apertureBladeCurvature = 0;
    auto polygonApertureOut = render(engine, device, queue, focusPattern, width,
                                     height, polygonAperture);
    require(maxDifference(circularApertureOut, polygonApertureOut) > .001f,
            "Polygon aperture must differ from circular response");
    auto bladeCountAperture = polygonAperture;
    bladeCountAperture.apertureBladeCount = 11;
    require(maxDifference(polygonApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, bladeCountAperture)) > .001f,
            "Blade Count must shape polygon response");
    auto manyBladeAperture = polygonAperture;
    manyBladeAperture.apertureBladeCount = 24;
    require(maxDifference(polygonApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, manyBladeAperture)) > .001f,
            "Extended creative Blade Count must remain effective above 16");
    auto curvedAperture = polygonAperture;
    curvedAperture.apertureBladeCurvature = .8f;
    require(maxDifference(polygonApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, curvedAperture)) > .001f,
            "Blade Curvature must round polygon response");
    auto rotatedAperture = polygonAperture;
    rotatedAperture.apertureRotation = 37;
    require(maxDifference(polygonApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, rotatedAperture)) > .001f,
            "Aperture Rotation must rotate shaped response");
    auto ovalAperture = circularAperture;
    ovalAperture.apertureShape = 2;
    ovalAperture.apertureAspect = 2;
    auto ovalApertureOut = render(engine, device, queue, focusPattern, width,
                                  height, ovalAperture);
    require(maxDifference(circularApertureOut, ovalApertureOut) > .001f,
            "Oval aperture aspect must shape response");
    auto catEyeAperture = ovalAperture;
    catEyeAperture.apertureCatEye = 1;
    require(maxDifference(ovalApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, catEyeAperture)) > .001f,
            "Cat-eye response must deform the off-axis pupil");
    auto shiftedPupil = catEyeAperture;
    shiftedPupil.aperturePupilShift = .8f;
    auto shiftedPupilOut = render(engine, device, queue, focusPattern, width,
                                  height, shiftedPupil);
    require(maxDifference(shiftedPupilOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, catEyeAperture)) > .001f,
            "Pupil Shift must independently displace off-axis bokeh");
    auto clippedPupil = shiftedPupil;
    clippedPupil.aperturePupilClip = .7f;
    auto clippedPupilOut = render(engine, device, queue, focusPattern, width,
                                  height, clippedPupil);
    require(maxDifference(shiftedPupilOut, clippedPupilOut) > .001f,
            "Pupil Clipping must independently shape off-axis bokeh");
    auto rimmedPupil = clippedPupil;
    rimmedPupil.apertureRimWeight = .8f;
    require(maxDifference(clippedPupilOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, rimmedPupil)) > .001f,
            "Pupil Rim Weight must redistribute bokeh energy");
    auto spatialAperture = circularAperture;
    spatialAperture.responseFieldOnset = .22f;
    spatialAperture.responseFieldFalloff = .82f;
    auto spatialApertureOut = render(engine, device, queue, focusPattern, width,
                                     height, spatialAperture);
    float centreDifference = 0, edgeDifference = 0;
    uint32_t centreCount = 0, edgeCount = 0;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float nx = (float(x) + .5f) / float(width) - .5f;
        float ny = (float(y) + .5f) / float(height) - .5f;
        float d = std::abs(spatialApertureOut[size_t(y) * width + x].x -
                           focusPattern[size_t(y) * width + x].x);
        float r = std::sqrt(nx * nx + ny * ny) * 2.0f;
        if (r < .16f) { centreDifference += d; ++centreCount; }
        if (r > .72f) { edgeDifference += d; ++edgeCount; }
      }
    centreDifference /= float(centreCount);
    edgeDifference /= float(edgeCount);
    require(edgeDifference > .01f && edgeDifference > centreDifference * 3.0f,
            "Depth-free aperture response must preserve a usable centre and "
            "progressively apply pupil reconstruction off axis");
    auto spatialBokeh = spatialAperture;
    spatialBokeh.apertureBokehSwirl = 2;
    auto spatialBokehOut = render(engine, device, queue, focusPattern, width,
                                  height, spatialBokeh);
    require(maxDifference(spatialApertureOut, spatialBokehOut) > .001f,
            "Bokeh Swirl must reshape an active spatial aperture response");
    auto polygonAspect = polygonAperture;
    polygonAspect.apertureAspect = 1.8f;
    require(maxDifference(polygonApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, polygonAspect)) > .001f,
            "Pupil Aspect must independently reshape polygonal pupils");
    auto extremeBokeh = spatialAperture;
    extremeBokeh.apertureBokehSwirl = 6.0f;
    extremeBokeh.apertureCatEye = 1.0f;
    auto extremeBokehOut = render(engine, device, queue, focusPattern, width,
                                  height, extremeBokeh);
    require(std::all_of(extremeBokehOut.begin(), extremeBokehOut.end(),
                        [](simd_float4 value) {
                          return std::isfinite(value.x) && std::isfinite(value.y) &&
                                 std::isfinite(value.z) && std::isfinite(value.w);
                        }),
            "Extreme Bokeh Swirl must retain a finite bounded pupil response");
    auto zeroWidthField = spatialAperture;
    zeroWidthField.responseFieldOnset = .55f;
    zeroWidthField.responseFieldFalloff = 0.0f;
    auto zeroWidthFieldOut = render(engine, device, queue, focusPattern, width,
                                    height, zeroWidthField);
    require(std::all_of(zeroWidthFieldOut.begin(), zeroWidthFieldOut.end(),
                        [](simd_float4 value) {
                          return std::isfinite(value.x) && std::isfinite(value.y) &&
                                 std::isfinite(value.z) && std::isfinite(value.w);
                        }),
            "Zero Field Falloff must retain a finite feathered transition");
    auto shiftedSpatialAperture = spatialAperture;
    shiftedSpatialAperture.fieldCenter = {.35f, .55f};
    require(maxDifference(spatialApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, shiftedSpatialAperture)) > .001f,
            "Depth-free aperture falloff must follow Field Center");
    auto softAperture = polygonAperture;
    softAperture.apertureSoftness = 1;
    require(maxDifference(polygonApertureOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, softAperture)) > .001f,
            "Aperture softness must continuously soften shaped response");
    auto irregularPupil = polygonAperture;
    irregularPupil.variationAmount = 1;
    irregularPupil.variationSeed = 23;
    irregularPupil.variationPupilIrregularity = 1;
    auto irregularPupilOut = render(engine, device, queue, focusPattern, width,
                                    height, irregularPupil);
    require(maxDifference(polygonApertureOut, irregularPupilOut) > .0001f,
            "Pupil Irregularity must reshape an active aperture response");
    require(maxDifference(irregularPupilOut,
                          render(engine, device, queue, focusPattern, width,
                                 height, irregularPupil)) < 1e-7f,
            "Pupil Irregularity must remain deterministic for a fixed seed");
    std::vector<simd_float4> aperturePoint(width * height,
                                           simd_float4{0, 0, 0, 1});
    aperturePoint[(height / 2) * width + width / 2] = {5, 5, 5, 1};
    auto filledAperture = neutral;
    filledAperture.apertureResponse = 1;
    filledAperture.apertureRadius = 10;
    filledAperture.fieldCenter = {0, 0};
    auto filledApertureOut = render(engine, device, queue, aperturePoint, width,
                                    height, filledAperture);
    float ringMinimum = 1e9f, ringMaximum = 0;
    for (uint32_t angleIndex = 0; angleIndex < 24; ++angleIndex) {
      float angle = float(angleIndex) * 2.0f * float(M_PI) / 24.0f;
      int x = int(width / 2) + int(std::lround(std::cos(angle) * 4.0f));
      int y = int(height / 2) + int(std::lround(std::sin(angle) * 4.0f));
      float sample = filledApertureOut[size_t(y) * width + x].x;
      ringMinimum = std::min(ringMinimum, sample);
      ringMaximum = std::max(ringMaximum, sample);
    }
    require(ringMinimum > ringMaximum * .12f,
            "Circular aperture footprint must be filled without cross-shaped "
            "angular gaps");
    float interiorMinimum = 1e9f, interiorMaximum = 0, interiorSum = 0,
          interiorSquareSum = 0;
    uint32_t interiorCount = 0;
    for (int y = -5; y <= 5; ++y)
      for (int x = -5; x <= 5; ++x)
        if (x * x + y * y <= 25) {
          float sample = filledApertureOut[size_t(int(height / 2) + y) * width +
                                           size_t(int(width / 2) + x)]
                             .x;
          interiorMinimum = std::min(interiorMinimum, sample);
          interiorMaximum = std::max(interiorMaximum, sample);
          interiorSum += sample;
          interiorSquareSum += sample * sample;
          ++interiorCount;
        }
    float interiorMean = interiorSum / float(interiorCount);
    float interiorVariance = std::max(interiorSquareSum / float(interiorCount) -
                                          interiorMean * interiorMean,
                                      0.0f);
    require(interiorMinimum > interiorMaximum * .04f &&
                std::sqrt(interiorVariance) < interiorMean * .65f,
            "Aperture footprint must reconstruct uniformly without a visible "
            "sample rosette");
    float centreSample =
        filledApertureOut[size_t(height / 2) * width + width / 2].x;
    float surroundingMean = 0;
    for (uint32_t angleIndex = 0; angleIndex < 16; ++angleIndex) {
      float angle = float(angleIndex) * 2.0f * float(M_PI) / 16.0f;
      int x = int(width / 2) + int(std::lround(std::cos(angle) * 3.0f));
      int y = int(height / 2) + int(std::lround(std::sin(angle) * 3.0f));
      surroundingMean += filledApertureOut[size_t(y) * width + x].x;
    }
    surroundingMean /= 16.0f;
    require(centreSample < surroundingMean * 1.35f,
            "Full aperture response must not retain a concentrated "
            "point-source core");
    auto depthPoint = aperturePoint;
    for (auto &pixel : depthPoint)
      pixel.w = .5f;
    auto focusedDepthAperture = filledAperture;
    focusedDepthAperture.depthMode = 2;
    focusedDepthAperture.depthChannel = 4;
    focusedDepthAperture.depthFocus = .5f;
    require(maxDifference(aperturePoint,
                          render(engine, device, queue, depthPoint, width,
                                 height, focusedDepthAperture)) < 1e-6f,
            "Aperture depth focus plane must preserve the unblurred source");
    for (auto &pixel : depthPoint)
      pixel.w = .75f;
    auto partialDepthApertureOut = render(engine, device, queue, depthPoint,
                                          width, height, focusedDepthAperture);
    float partialCentre =
        partialDepthApertureOut[size_t(height / 2) * width + width / 2].x;
    float partialSurround = 0;
    for (uint32_t angleIndex = 0; angleIndex < 16; ++angleIndex) {
      float angle = float(angleIndex) * 2.0f * float(M_PI) / 16.0f;
      int x = int(width / 2) + int(std::lround(std::cos(angle) * 2.0f));
      int y = int(height / 2) + int(std::lround(std::sin(angle) * 2.0f));
      partialSurround += partialDepthApertureOut[size_t(y) * width + x].x;
    }
    partialSurround /= 16.0f;
    require(
        partialCentre < partialSurround * 1.5f,
        "Depth-scaled aperture footprint must not retain a sharp point core");

    // A discontinuous map must select either side of a hard depth jump
    // without softening the explicitly focused region itself. This does not
    // claim foreground occlusion reconstruction; the dedicated 79--83
    // visual series evaluates boundary contamination and thin structures.
    std::vector<simd_float4> depthStep(width * height);
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        bool near = x < width / 2;
        float value = ((x / 3 + y / 3) & 1) ? 1.0f : .05f;
        depthStep[size_t(y) * width + x] = {value, value, value,
                                            near ? .2f : .8f};
      }
    auto stepAperture = circularAperture;
    stepAperture.depthMode = 2;
    stepAperture.depthChannel = 4;
    stepAperture.depthFocus = .2f;
    auto nearFocusedStep =
        render(engine, device, queue, depthStep, width, height, stepAperture);
    size_t nearProbe = size_t(height / 2) * width + width / 4;
    require(simd_length(simd_float3{
                nearFocusedStep[nearProbe].x - depthStep[nearProbe].x,
                nearFocusedStep[nearProbe].y - depthStep[nearProbe].y,
                nearFocusedStep[nearProbe].z - depthStep[nearProbe].z}) < 1e-6f,
            "Hard-depth near focus must preserve the selected source region");
    stepAperture.depthFocus = .8f;
    auto farFocusedStep =
        render(engine, device, queue, depthStep, width, height, stepAperture);
    size_t farProbe = size_t(height / 2) * width + width * 3 / 4;
    require(simd_length(simd_float3{
                farFocusedStep[farProbe].x - depthStep[farProbe].x,
                farFocusedStep[farProbe].y - depthStep[farProbe].y,
                farFocusedStep[farProbe].z - depthStep[farProbe].z}) < 1e-6f,
            "Hard-depth far focus must preserve the selected source region");
    require(maxDifference(nearFocusedStep, farFocusedStep) > .01f,
            "Hard-depth focus selection must move across a discontinuity");
    std::vector<simd_float4> boundaryPoint(width * height,
                                           simd_float4{0, 0, 0, .8f});
    boundaryPoint[size_t(height / 2) * width + width / 2 - 1] = {5, 5, 5, .2f};
    stepAperture.depthFocus = .2f;
    stepAperture.apertureRadius = 10;
    auto protectedBoundary = render(engine, device, queue, boundaryPoint, width,
                                    height, stepAperture);
    float wrongLayerLeak = 0;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = width / 2 + 1; x < width; ++x)
        wrongLayerLeak = std::max(wrongLayerLeak,
                                  protectedBoundary[size_t(y) * width + x].x);
    require(wrongLayerLeak < .02f, "Depth-aware aperture must reject bright "
                                   "samples across a hard layer boundary");

    std::vector<simd_float4> alignmentPoint(width * height,
                                            simd_float4{0, 0, 0, 1});
    alignmentPoint[(height / 2) * width + width * 3 / 4] = {5, 5, 5, 1};
    auto warpedPoint = neutral;
    warpedPoint.distortionK1 = -.28f;
    auto warpedPointOut = render(engine, device, queue, alignmentPoint, width,
                                 height, warpedPoint);
    auto warpedBloom = warpedPoint;
    warpedBloom.bloomThreshold = 1;
    warpedBloom.bloomEnergy = .5f;
    warpedBloom.bloomRadius = 5;
    auto warpedBloomOut = render(engine, device, queue, alignmentPoint, width,
                                 height, warpedBloom);
    uint32_t peakX = 0, peakY = 0;
    float peak = -1;
    double sum = 0, sumX = 0, sumY = 0;
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        size_t i = size_t(y) * width + x;
        if (warpedPointOut[i].x > peak) {
          peak = warpedPointOut[i].x;
          peakX = x;
          peakY = y;
        }
        double energy =
            std::max(0.0f, warpedBloomOut[i].x - warpedPointOut[i].x);
        sum += energy;
        sumX += energy * x;
        sumY += energy * y;
      }
    require(sum > 0,
            "Distorted bloom alignment test must produce scattered energy");
    float centroidDistance =
        std::hypot(float(sumX / sum) - peakX, float(sumY / sum) - peakY);
    require(centroidDistance < 2.5f, "Bloom/glare/halo scatter must remain "
                                     "aligned with distorted image geometry");

    std::vector<simd_float4> offAxisPoint(width * height,
                                          simd_float4{0, 0, 0, 1});
    uint32_t pointX = width * 3 / 4, pointY = height / 2;
    offAxisPoint[pointY * width + pointX] = {5, 5, 5, 1};
    auto comaShape = neutral;
    comaShape.coma = 1;
    auto comaShapeOut =
        render(engine, device, queue, offAxisPoint, width, height, comaShape);
    float comaOutward = comaShapeOut[pointY * width + pointX + 6].x;
    float comaInward = comaShapeOut[pointY * width + pointX - 6].x;
    require(comaOutward > comaInward + 1e-4f,
            "Coma must form an asymmetric tail away from the optical center");
    for (uint32_t offset = 1; offset <= 8; ++offset)
      require(comaShapeOut[pointY * width + pointX + offset].x > 1e-6f,
              "Coma tail must remain continuous without sampled ghost gaps");
    auto strongComa = comaShape;
    strongComa.coma = 2;
    require(
        maxDifference(comaShapeOut, render(engine, device, queue, offAxisPoint,
                                           width, height, strongComa)) > .001f,
        "Expanded Coma range must produce additional optical character");
    auto highComaThreshold = comaShape;
    highComaThreshold.comaThreshold = 4.0f;
    require(maxDifference(comaShapeOut,
                          render(engine, device, queue, offAxisPoint, width,
                                 height, highComaThreshold)) > .001f,
            "Coma Threshold must control highlight eligibility");

    auto haloShape = neutral;
    haloShape.sphericalHalo = 1;
    auto haloShapeOut =
        render(engine, device, queue, offAxisPoint, width, height, haloShape);
    float haloInner = haloShapeOut[pointY * width + pointX + 4].x;
    float haloMiddle = haloShapeOut[pointY * width + pointX + 8].x;
    float haloOuter = haloShapeOut[pointY * width + pointX + 12].x;
    require(haloInner > haloMiddle && haloMiddle > haloOuter &&
                haloOuter > 1e-5f,
            "Spherical aberration must form a smooth decaying spatial halo");
    require(maxDifference(comaShapeOut, haloShapeOut) > .001f,
            "Coma and spherical halo must have independent spatial shapes");
    auto depthHaloPoint = offAxisPoint;
    for (auto &pixel : depthHaloPoint)
      pixel.w = .5f;
    auto depthHalo = haloShape;
    depthHalo.depthMode = 2;
    depthHalo.depthChannel = 4;
    depthHalo.depthFocus = .5f;
    auto focusedHalo =
        render(engine, device, queue, depthHaloPoint, width, height, depthHalo);
    auto opaqueDepthHaloPoint = depthHaloPoint;
    for (auto &pixel : opaqueDepthHaloPoint)
      pixel.w = 1.0f;
    require(maxDifference(focusedHalo, opaqueDepthHaloPoint) < 1e-6f,
            "Spherical Halo must preserve highlights on Focus Depth");
    for (auto &pixel : depthHaloPoint)
      pixel.w = .85f;
    opaqueDepthHaloPoint = depthHaloPoint;
    for (auto &pixel : opaqueDepthHaloPoint)
      pixel.w = 1.0f;
    auto defocusedHalo =
        render(engine, device, queue, depthHaloPoint, width, height, depthHalo);
    require(maxDifference(defocusedHalo, opaqueDepthHaloPoint) > .001f,
            "Spherical Halo must respond away from Focus Depth");
    auto shiftedHaloFocus = depthHalo;
    shiftedHaloFocus.depthFocus = .85f;
    require(
        maxDifference(render(engine, device, queue, depthHaloPoint, width,
                             height, shiftedHaloFocus),
                      opaqueDepthHaloPoint) < 1e-6f,
        "Moving Focus Depth must move the clean spherical-aberration plane");

    auto glareAudit = neutral;
    glareAudit.glareEnergy = .6f;
    glareAudit.glareRadius = 8;
    glareAudit.glareThreshold = 1;
    auto glareAuditOut =
        render(engine, device, queue, offAxisPoint, width, height, glareAudit);
    auto glareRadiusAudit = glareAudit;
    glareRadiusAudit.glareRadius = 24;
    auto glareTintAudit = glareAudit;
    glareTintAudit.glareColor = {1, .3f, .2f};
    glareTintAudit.glareColorAmount = 1;
    require(maxDifference(glareAuditOut,
                          render(engine, device, queue, offAxisPoint, width,
                                 height, glareRadiusAudit)) > .0001f,
            "Glare Radius must shape active glare");
    require(maxDifference(glareAuditOut,
                          render(engine, device, queue, offAxisPoint, width,
                                 height, glareTintAudit)) > .0001f,
            "Glare Color must tint active glare");

    std::vector<simd_float4> normalizedGlare(width * height,
                                             simd_float4{.04f, .04f, .04f, 1});
    for (int dy = -2; dy <= 2; ++dy)
      for (int dx = -2; dx <= 2; ++dx)
        normalizedGlare[(pointY + dy) * width + pointX + dx] =
            {.92f, .82f, .68f, 1};
    auto normalizedGlareControl = neutral;
    normalizedGlareControl.glareEnergy = .8f;
    normalizedGlareControl.glareRadius = 24;
    normalizedGlareControl.glareThreshold = .4f;
    auto normalizedGlareOut = render(engine, device, queue, normalizedGlare,
                                     width, height, normalizedGlareControl);
    require(maxDifference(normalizedGlareOut, normalizedGlare) > .0005f,
            "Glare must respond to normalized image highlights");
    auto suppressedGlare = normalizedGlareControl;
    suppressedGlare.glareThreshold = 1.2f;
    auto neutralNormalized = render(engine, device, queue, normalizedGlare,
                                    width, height, neutral);
    auto suppressedGlareOut = render(engine, device, queue, normalizedGlare,
                                     width, height, suppressedGlare);
    require(maxDifference(suppressedGlareOut, neutralNormalized) < 1e-5f,
            "Glare Threshold must independently reject sub-threshold highlights");
    auto unrelatedBloomThreshold = normalizedGlareControl;
    unrelatedBloomThreshold.bloomThreshold = 3.5f;
    require(maxDifference(normalizedGlareOut,
                          render(engine, device, queue, normalizedGlare, width,
                                 height, unrelatedBloomThreshold)) < 1e-6f,
            "Bloom Threshold must not alter Glare");
    auto glareDifference = normalizedGlareControl;
    glareDifference.processingFlags = LDBDiagnosticDifference;
    auto suppressedDifference = suppressedGlare;
    suppressedDifference.processingFlags = LDBDiagnosticDifference;
    auto glareScatter = normalizedGlareControl;
    glareScatter.processingFlags = LDBDiagnosticScatter;
    auto suppressedScatter = suppressedGlare;
    suppressedScatter.processingFlags = LDBDiagnosticScatter;
    require(maxDifference(render(engine, device, queue, normalizedGlare, width,
                                 height, glareDifference),
                          render(engine, device, queue, normalizedGlare, width,
                                 height, suppressedDifference)) > .001f,
            "Difference diagnostic must expose normalized Glare");
    require(maxDifference(render(engine, device, queue, normalizedGlare, width,
                                 height, glareScatter),
                          render(engine, device, queue, normalizedGlare, width,
                                 height, suppressedScatter)) > .001f,
            "Scatter diagnostic must expose normalized Glare");

    std::vector<simd_float4> detailPattern(width * height);
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float fine = ((x + y) & 1) ? .65f : .35f;
        float broad = ((x / 8) & 1) ? .12f : -.12f;
        detailPattern[y * width + x] = {fine + broad, fine + broad,
                                        fine + broad, .37f};
      }
    auto fineBoost = neutral;
    fineBoost.fineDetail = .7f;
    auto fineBoostOut =
        render(engine, device, queue, detailPattern, width, height, fineBoost);
    auto fineLoss = neutral;
    fineLoss.fineDetail = -.7f;
    auto fineLossOut =
        render(engine, device, queue, detailPattern, width, height, fineLoss);
    require(luminanceDeviation(fineBoostOut) >
                luminanceDeviation(detailPattern),
            "Fine detail boost must increase high-frequency contrast");
    require(luminanceDeviation(fineLossOut) < luminanceDeviation(detailPattern),
            "Fine detail loss must reduce high-frequency contrast");

    auto micro = neutral;
    micro.microContrast = .6f;
    auto microOut =
        render(engine, device, queue, detailPattern, width, height, micro);
    require(maxDifference(detailPattern, microOut) > .005f,
            "Microcontrast must alter medium-frequency transfer");
    require(maxDifference(microOut, fineBoostOut) > .005f,
            "Microcontrast and fine detail must be independent");

    auto edgeDetail = neutral;
    edgeDetail.detailEdgeFalloff = .8f;
    auto edgeDetailOut =
        render(engine, device, queue, detailPattern, width, height, edgeDetail);
    size_t centerDetail = (height / 2) * width + width / 2;
    size_t cornerDetail = 2 * width + 2;
    require(std::abs(edgeDetailOut[cornerDetail].x -
                     detailPattern[cornerDetail].x) >
                std::abs(edgeDetailOut[centerDetail].x -
                         detailPattern[centerDetail].x) +
                    .001f,
            "Detail falloff must be stronger off axis");

    auto defocusedDetail = neutral;
    defocusedDetail.cornerSharpnessLoss = 2.0f;
    defocusedDetail.fieldCurvature = 1.5f;
    defocusedDetail.responseFieldOnset = 0.0f;
    defocusedDetail.responseFieldFalloff = .65f;
    auto defocusedOnlyOut = render(engine, device, queue, detailPattern, width,
                                   height, defocusedDetail);
    auto boostedDefocus = defocusedDetail;
    boostedDefocus.fineDetail = .7f;
    boostedDefocus.microContrast = .6f;
    auto boostedDefocusOut = render(engine, device, queue, detailPattern,
                                    width, height, boostedDefocus);
    float standaloneBoost = std::abs(fineBoostOut[cornerDetail].x -
                                     detailPattern[cornerDetail].x);
    float postDefocusBoost = std::abs(boostedDefocusOut[cornerDetail].x -
                                      defocusedOnlyOut[cornerDetail].x);
    require(postDefocusBoost < standaloneBoost * .65f,
            "Positive detail enhancement must not reconstruct sharp texture "
            "after strong field defocus");

    auto sagittal = neutral;
    sagittal.sagittalDetail = .8f;
    auto tangential = neutral;
    tangential.tangentialDetail = .8f;
    auto sagittalOut =
        render(engine, device, queue, detailPattern, width, height, sagittal);
    auto tangentialOut =
        render(engine, device, queue, detailPattern, width, height, tangential);
    require(
        maxDifference(sagittalOut, tangentialOut) > .005f,
        "Sagittal and tangential transfer must be independently directional");

    auto scaleWide = micro;
    scaleWide.detailScale = 4;
    auto scaleWideOut =
        render(engine, device, queue, detailPattern, width, height, scaleWide);
    require(maxDifference(microOut, scaleWideOut) > .001f,
            "Detail scale must select a different spatial-frequency response");
    require(maxAlphaDifference(detailPattern, scaleWideOut) < 1e-6f,
            "Detail transfer must preserve alpha");

    std::vector<simd_float4> stepEdge(width * height);
    for (uint32_t y = 0; y < height; ++y)
      for (uint32_t x = 0; x < width; ++x) {
        float v = x < width / 2 ? .2f : .8f;
        stepEdge[y * width + x] = {v, v, v, 1};
      }
    auto haloLimit = neutral;
    haloLimit.microContrast = 1;
    haloLimit.fineDetail = 1;
    haloLimit.detailScale = 2;
    auto haloLimitOut =
        render(engine, device, queue, stepEdge, width, height, haloLimit);
    for (const auto &p : haloLimitOut)
      require(p.x >= .15f && p.x <= .85f && p.y >= .15f && p.y <= .85f &&
                  p.z >= .15f && p.z <= .85f,
              "Detail transfer must suppress bright and dark edge halos");

    auto compactBloom = neutral;
    compactBloom.bloomThreshold = 1.0f;
    compactBloom.bloomEnergy = 0.5f;
    compactBloom.bloomRadius = 2.0f;
    compactBloom.glareRadius = 18.0f;
    auto compactBloomOut =
        render(engine, device, queue, impulse, width, height, compactBloom);
    auto broadGlare = neutral;
    broadGlare.bloomThreshold = 1.0f;
    broadGlare.glareEnergy = 0.5f;
    broadGlare.glareRadius = 18.0f;
    broadGlare.bloomRadius = 2.0f;
    auto broadGlareOut =
        render(engine, device, queue, impulse, width, height, broadGlare);
    size_t farSample = (height / 2) * width + width / 2 + 14;
    require(broadGlareOut[farSample].x > compactBloomOut[farSample].x + 1e-6f,
            "Glare radius must be independent from bloom radius and energy");

    require(maxAlphaDifference(image, vignetteOut) < 1e-6f,
            "Optical processing must preserve alpha");

    const uint32_t spaces[] = {
        LDBWorkingColorSpaceACEScg, LDBWorkingColorSpaceACEScct,
        LDBWorkingColorSpaceDaVinciIntermediate,
        LDBWorkingColorSpaceARRILogC3EI800, LDBWorkingColorSpaceARRILogC4};
    for (uint32_t space : spaces) {
      std::vector<simd_float4> encoded(width * height);
      for (size_t i = 0; i < encoded.size(); ++i) {
        float linear = -0.01f + 4.01f * float(i) / float(encoded.size() - 1);
        simd_float3 ap1 = {linear, linear * .61f + .03f, linear * .27f - .01f};
        simd_float3 value = LDBColorReference::encode(ap1, space);
        encoded[i] = {value.x, value.y, value.z,
                      .2f + .8f * float(i % width) / float(width - 1)};
      }
      auto roundTrip = neutral;
      roundTrip.workingColorSpace = space;
      auto roundTripOut =
          render(engine, device, queue, encoded, width, height, roundTrip);
      require(maxDifference(encoded, roundTripOut) < 2e-4f,
              "Working-space neutral round trip must preserve extended-range "
              "pixels");

      auto exactBypass = roundTrip;
      exactBypass.effectBlend = 0.0f;
      exactBypass.vignetteNatural = 1.0f;
      auto exactBypassOut =
          render(engine, device, queue, encoded, width, height, exactBypass);
      require(maxDifference(encoded, exactBypassOut) == 0.0f,
              "Zero blend must be bit-exact in every working space");

      auto grayTransmission = roundTrip;
      grayTransmission.transmissionColor = {.8f, .8f, .8f};
      grayTransmission.transmissionColorAmount = 1.0f;
      auto transmitted = render(engine, device, queue, encoded, width, height,
                                grayTransmission);
      size_t mid = encoded.size() / 2;
      simd_float3 sourceAP1 = LDBColorReference::decode(
          {encoded[mid].x, encoded[mid].y, encoded[mid].z}, space);
      simd_float3 resultAP1 = LDBColorReference::decode(
          {transmitted[mid].x, transmitted[mid].y, transmitted[mid].z}, space);
      simd_float3 expected = sourceAP1 * .8f;
      require(simd_reduce_max(simd_abs(resultAP1 - expected)) < 4e-4f,
              "Optical response must be equivalent after decoding each working "
              "space");

      auto encodedContamination = roundTrip;
      encodedContamination.internalDirtAmount = 1.2f;
      encodedContamination.internalDirtScale = 1.4f;
      encodedContamination.internalDirtSmear = .35f;
      encodedContamination.internalDirtScatter = 1.0f;
      encodedContamination.internalDirtSeed = 16180;
      auto contaminated = render(engine, device, queue, encoded, width, height,
                                 encodedContamination);
      require(maxDifference(encoded, contaminated) > .0001f,
              "Internal contamination must operate in every working space");
      require(maxAlphaDifference(encoded, contaminated) < 1e-6f,
              "Internal contamination must preserve alpha in every working space");
    }

    std::printf("PASS: neutral identity\n");
    std::printf("PASS: zero blend identity\n");
    std::printf("PASS: vignette field response\n");
    std::printf("PASS: geometric distortion\n");
    std::printf("PASS: lateral chromatic aberration\n");
    std::printf("PASS: gradual field-gated chromatic aberration\n");
    std::printf("PASS: longitudinal near/far chromatic aberration\n");
    std::printf("PASS: optional depth input interpretation and diagnostic\n");
    std::printf("PASS: depth edge softness and protection\n");
    std::printf("PASS: defocus and depth rejection diagnostics\n");
    std::printf("PASS: transmission color and response\n");
    std::printf("PASS: independent field shape\n");
    std::printf("PASS: independent anamorphic distortion and aberration\n");
    std::printf("PASS: deterministic lens variation responses\n");
    std::printf("PASS: deterministic internal element contamination interactions\n");
    std::printf("PASS: simultaneous advanced response shaping\n");
    std::printf("PASS: deterministic capture and look mapping\n");
    std::printf("PASS: multi-pass bloom distribution\n");
    std::printf("PASS: field swirl\n");
    std::printf("PASS: field curvature response\n");
    std::printf("PASS: normalized independent astigmatism and smear\n");
    std::printf("PASS: continuous spatial aperture and pupil response\n");
    std::printf("PASS: independent aperture shape controls\n");
    std::printf("PASS: filled aperture footprint without directional spokes\n");
    std::printf("PASS: uniform aperture reconstruction without retained "
                "point-source core\n");
    std::printf("PASS: expanded creative focus and coma ranges\n");
    std::printf("PASS: anamorphic full-field shaping\n");
    std::printf("PASS: coherent-source analytic flare, reflection train and diffraction\n");
    std::printf("PASS: all UI control ranges and documented dependencies\n");
    std::printf("PASS: distortion-aligned optical scatter\n");
    std::printf("PASS: asymmetric off-axis coma tail\n");
    std::printf("PASS: continuous coma tail without ghost gaps\n");
    std::printf("PASS: smooth spatial spherical-aberration halo\n");
    std::printf("PASS: depth-conditioned spherical-aberration halo\n");
    std::printf("PASS: independent coma and spherical shapes\n");
    std::printf("PASS: fine-detail boost and loss\n");
    std::printf("PASS: independent microcontrast transfer\n");
    std::printf("PASS: field-dependent detail falloff\n");
    std::printf("PASS: sagittal and tangential detail transfer\n");
    std::printf("PASS: selectable detail scale\n");
    std::printf("PASS: detail-transfer halo suppression\n");
    std::printf("PASS: detail enhancement respects field-defocus ordering\n");
    std::printf("PASS: independent bloom and glare fields\n");
    std::printf("PASS: independent anamorphic flare response\n");
    std::printf("PASS: fixed high-quality diagnostic transitions\n");
    std::printf("PASS: alpha preservation\n");
    std::printf("PASS: five-space extended-range round trips\n");
    std::printf("PASS: five-space bit-exact zero blend\n");
    std::printf("PASS: cross-space linear optical equivalence\n");
    std::printf("Metal device: %s\n", device.name.UTF8String);
  }
  return 0;
}
