#include "LensDebaserPlugin.h"
#include "LensDebaserMetal.h"
#include "ofxsProcessing.h"
#include "ofxsSupportPrivate.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
constexpr const char *kName = "Lens Debaser 1.35";
constexpr const char *kIdentifier = "com.ldb.LensDebaser";
constexpr const char *kDepthClipName = "Depth";
struct DoubleSpec {
  const char *id;
  const char *label;
  double value, low, high, step;
  const char *hint;
};
const DoubleSpec kSpecs[] = {
    {"distortionK1", "Primary Distortion", 0, -.25, .25, .0001,
     "Barrel or pincushion distortion."},
    {"distortionK2", "Secondary Distortion", 0, -1, 1, .001,
     "Higher-order edge distortion."},
    {"moustacheK3", "Moustache", 0, -1, 1, .001,
     "Complex wave-shaped radial distortion."},
    {"anamorphicSqueeze", "Anamorphic Field", 1, .25, 4, .001,
     "Shapes the complete off-axis lens field; this is not an image "
     "desqueeze."},
    {"captureInfluence", "Capture Influence", 0, 0, 1, .001,
     "Blends Capture mapping from no influence to full influence."},
    {"captureFocalLength", "Focal Length (mm)", 50, 8, 300, .1,
     "Capture context used to scale active off-axis responses."},
    {"captureAperture", "Aperture", 2.8, .7, 32, .01,
     "Capture context used to scale active pupil and highlight responses."},
    {"captureFocusDistance", "Focus Distance (cm)", 300, 1, 1000, 1,
     "Capture context from 1 cm to 10 m; 1000 represents infinity focus."},
    {"lookCharacter", "Character", 0, 0, 1, .001,
     "Adds a coordinated amount of general optical character."},
    {"lookVintageBias", "Vintage Bias", 0, 0, 1, .001,
     "Biases the visible direct model toward vintage response."},
    {"lookVintageCaricatureBias", "Vintage Caricature", 0, 0, 1, .001,
     "Exaggerates the familiar softness, glow, colour and field character of "
     "vintage optics."},
    {"lookExoticBias", "Exotic Bias", 0, 0, 1, .001,
     "Biases the visible direct model toward asymmetric and anamorphic "
     "character."},
    {"lookAnamorphicBias", "Classic 2x Anamorphic Bias", 0, 0, 1, .001,
     "Adds an exaggerated classic 2x anamorphic field, flare, chromatic and "
     "pupil character."},
    {"lookInfluence", "Look Influence", 0, 0, 1, .001,
     "Blends all Look macro contributions to zero."},
    {"lateralCARed", "Red Fringing", 0, -10, 10, .01,
     "Radial red-channel displacement."},
    {"lateralCABlue", "Blue Fringing", 0, -10, 10, .01,
     "Radial blue-channel displacement."},
    {"longitudinalCA", "Longitudinal Amount", 0, 0, 2, .001,
     "Near/far focus color separation around local focus transitions."},
    {"longitudinalCARadius", "Longitudinal Radius", 4, .5, 12, .01,
     "Feature scale used to identify near- and far-focus transitions."},
    {"vignetteNatural", "Natural Vignette", 0, 0, 1, .001,
     "Smooth cosine-like edge falloff."},
    {"vignetteOptical", "Optical Vignette", 0, 0, 1, .001,
     "Stronger outer-field transmission loss."},
    {"vignetteMechanical", "Mechanical Vignette", 0, 0, 1, .001,
     "Mixes in the defined image-circle boundary."},
    {"imageCircleSize", "Image Circle Size", 1.2, .25, 2, .001,
     "Boundary size used by Mechanical Vignette."},
    {"imageCircleAspect", "Image Circle Aspect", 1, .25, 4, .001,
     "Boundary aspect used by Mechanical Vignette."},
    {"imageCircleSoftness", "Image Circle Softness", .1, 0, 1, .001,
     "Boundary softness used by Mechanical Vignette."},
    {"apertureResponse", "Aperture Response", 0, 0, 1, .001,
     "Mixes in continuous aperture-shaped defocus; external depth holds Focus "
     "Depth sharp and increases defocus away from it."},
    {"apertureRadius", "Response Radius", 6, 0, 24, .01,
     "Spatial size of the aperture response in pixels."},
    {"apertureBladeCurvature", "Blade Curvature", .5, 0, 1, .001,
     "Rounds polygonal blades toward a circular response."},
    {"apertureRotation", "Aperture Rotation", 0, -180, 180, .1,
     "Rotates polygonal or oval aperture response in degrees."},
    {"apertureSoftness", "Edge Softness", .5, 0, 1, .001,
     "Redistributes pupil energy toward the centre for a progressively softer "
     "aperture boundary."},
    {"apertureCatEye", "Cat-Eye", 0, 0, 1, .001,
     "Compresses the pupil radially toward the frame edge."},
    {"apertureAspect", "Pupil Aspect", 1, .25, 4, .001,
     "Oval pupil aspect and cat-eye tangential shape."},
    {"cornerSharpnessLoss", "Corner Detail Loss", 0, 0, 2, .001,
     "Progressive off-axis focus loss."},
    {"astigmatism", "Astigmatism", 0, -2, 2, .001,
     "Directional off-axis focus split; sign swaps orientation."},
    {"fieldCurvature", "Field Curvature", 0, 0, 2, .001,
     "Curved off-axis focus response."},
    {"swirl", "Swirl", 0, -2, 2, .001,
     "Rotational field mapping toward the edges."},
    {"radialSmear", "Radial Smear", 0, 0, 2, .001,
     "Independent radial off-axis spread."},
    {"tangentialSmear", "Tangential Smear", 0, 0, 2, .001,
     "Independent tangential off-axis spread."},
    {"fieldAspect", "Field Aspect", 1, .25, 4, .001,
     "Aspect of the independent focus and off-axis response field."},
    {"fieldRotation", "Field Rotation", 0, -180, 180, .1,
     "Rotation of the independent focus and off-axis response field."},
    {"microContrast", "Microcontrast", 0, -2, 2, .001,
     "Medium-frequency texture transfer."},
    {"fineDetail", "Fine Detail", 0, -2, 2, .001,
     "Fine-frequency transfer without conventional sharpening halos."},
    {"detailEdgeFalloff", "Edge Falloff", 0, 0, 2, .001,
     "Progressive off-axis detail loss."},
    {"sagittalDetail", "Sagittal Detail", 0, -2, 2, .001,
     "Radial directional detail transfer."},
    {"tangentialDetail", "Tangential Detail", 0, -2, 2, .001,
     "Tangential directional detail transfer."},
    {"detailScale", "Detail Scale", 1, .25, 8, .001,
     "Feature size affected by Detail Transfer."},
    {"coma", "Coma", 0, -2, 2, .001, "Asymmetric off-axis highlight tail."},
    {"comaThreshold", "Coma Threshold", .6, 0, 4, .001,
     "Scene-linear highlight level at which coma begins."},
    {"sphericalHalo", "Spherical Halo", 0, 0, 2, .001,
     "Smooth highlight halo approximating spherical aberration."},
    {"bloomEnergy", "Bloom Amount", 0, 0, 4, .001,
     "Energy added by highlight bloom."},
    {"bloomThreshold", "Bloom Threshold", 1, 0, 4, .001,
     "Scene-linear extraction threshold."},
    {"bloomRadius", "Bloom Radius", 12, 0, 200, .01,
     "Bloom spread; requires Bloom Amount."},
    {"bloomHorizontalStretch", "Bloom Stretch", 1, 1, 12, .001,
     "Horizontal bloom aspect; requires Bloom Amount."},
    {"anamorphicDistortion", "Distortion", 0, -.25, .25, .0001,
     "Independent signed cylindrical field distortion; not a desqueeze."},
    {"anamorphicAberration", "Aberration", 0, -2, 2, .001,
     "Independent signed horizontal chromatic separation."},
    {"anamorphicFlareAmount", "Flare Amount", 0, 0, 2, .001,
     "Amount of dedicated horizontal highlight flare."},
    {"anamorphicFlareRadius", "Flare Radius", 80, 0, 400, .1,
     "Horizontal extent of Anamorphic Flare."},
    {"anamorphicFlareThreshold", "Flare Threshold", 1, 0, 16, .001,
     "Scene-linear highlight threshold for Anamorphic Flare."},
    {"glareEnergy", "Glare Amount", 0, 0, 2, .001,
     "Energy added by veiling glare."},
    {"glareRadius", "Glare Radius", 24, 0, 200, .01,
     "Glare spread; requires Glare Amount."},
    {"depthNear", "Input Near", 0, 0, 1, .001,
     "Input-map value remapped to the normalized near endpoint."},
    {"depthFar", "Input Far", 1, 0, 1, .001,
     "Input-map value remapped to the normalized far endpoint."},
    {"depthFocus", "Focus Depth", .5, 0, 1, .001,
     "Normalized depth plane held in focus; longitudinal color increases away "
     "from this value."},
    {"transmissionColorAmount", "Transmission Amount", 0, 0, 1, .001,
     "Mixes the Transmission Color into lens throughput."},
    {"glareColorAmount", "Glare Color Amount", 0, 0, 1, .001,
     "Mixes the Glare Color into glare."},
    {"transmissionDensity", "Transmission Density", 0, -2, 2, .001,
     "Signed optical throughput in stops."},
    {"transmissionContrast", "Transmission Contrast", 0, -2, 2, .001,
     "Signed scene-linear contrast around 18 percent grey."},
    {"transmissionHighlightSoftness", "Highlight Softness", 0, 0, 2, .001,
     "Compresses positive highlights while preserving middle grey."},
    {"variationAmount", "Variation Amount", 0, 0, 1, .001,
     "Parent blend for deterministic lens-to-lens variation."},
    {"variationSeed", "Variation Seed", 0, 0, 65535, 1,
     "Whole-number stable lens-instance selector."},
    {"variationFieldAsymmetry", "Field Asymmetry", 0, -1, 1, .001,
     "Seeded asymmetry of active off-axis response."},
    {"variationPupilIrregularity", "Pupil Irregularity", 0, -1, 1, .001,
     "Seeded irregularity of an active aperture footprint."},
    {"variationChromaticAsymmetry", "Chromatic Asymmetry", 0, -2, 2, .001,
     "Seeded decentered chromatic response."},
    {"variationTransmissionUnevenness", "Transmission Unevenness", 0, -1, 1,
     .001, "Broad stable transmission variation."},
    {"responseHighlightKnee", "Highlight Knee", 0, 0, 4, .001,
     "Softens highlight eligibility around active scatter thresholds."},
    {"responseFieldOnset", "Field Onset", 0, 0, 1.5, .001,
     "Normalized radius where active off-axis responses begin."},
    {"responseFieldFalloff", "Field Falloff", 1, 0, 1.5, .001,
     "Normalized radius where active off-axis responses reach full strength."},
    {"responseDefocusOnset", "Defocus Onset", .018, 0, 1, .001,
     "Depth distance where active defocus responses begin."},
    {"responseDefocusFalloff", "Defocus Falloff", .36, 0, 1, .001,
     "Depth distance where active defocus responses reach full strength."},
    {"responseScatterEdgeProtection", "Depth Edge Protection", 1, 0, 1, .001,
     "Controls cross-layer rejection for depth-aware aperture and scatter."},
    {"depthEdgeSoftness", "Depth Edge Softness", .5, 0, 1, .001,
     "Adjusts depth-layer tolerance at soft or noisy map boundaries."},
    {"effectBlend", "Blend", 1, 0, 1, .001,
     "Final dry/wet blend in increments of 0.001."}};

struct Preset {
  std::string name;
  std::unordered_map<std::string, double> values;
  std::array<double, 2> center{.5, .5}, fieldCenter{.5, .5};
  std::array<double, 3> transmission{1, 1, 1}, glare{1, 1, 1},
      nearFocus{1, .35, .75}, farFocus{.35, 1, .65},
      anamorphicFlare{.35, .55, 1};
  int apertureShape = 0, apertureBladeCount = 6, depthMode = 0,
      captureGate = 0;
};

class Processor final : public OFX::ImageProcessor {
public:
  explicit Processor(OFX::ImageEffect &e) : ImageProcessor(e) {}
  OFX::Image *source = nullptr;
  OFX::Image *depth = nullptr;
  LDBOpticsParameters p{};
  void processImagesMetal() override {
    const OfxRectI sourceBounds = source->getBounds();
    const OfxRectI destinationBounds = _dstImg->getBounds();
    const int width = sourceBounds.x2 - sourceBounds.x1;
    const int height = sourceBounds.y2 - sourceBounds.y1;
    if (width != destinationBounds.x2 - destinationBounds.x1 ||
        height != destinationBounds.y2 - destinationBounds.y1)
      OFX::throwSuiteStatusException(kOfxStatErrValue);
    RunLensDebaserMetal(_pMetalCmdQ, width, height, p,
                        static_cast<const float *>(source->getPixelData()),
                        static_cast<float *>(_dstImg->getPixelData()),
                        depth ? static_cast<const float *>(depth->getPixelData())
                              : nullptr);
  }
  void multiThreadProcessImages(OfxRectI) override {
    OFX::throwSuiteStatusException(kOfxStatErrUnsupported);
  }
};

class Plugin final : public OFX::ImageEffect {
public:
  explicit Plugin(OfxImageEffectHandle h) : ImageEffect(h), handle(h) {
    source = fetchClip(kOfxImageEffectSimpleSourceClipName);
    destination = fetchClip(kOfxImageEffectOutputClipName);
    try { depthInput = fetchClip(kDepthClipName); } catch (...) { depthInput = nullptr; }
    for (const auto &s : kSpecs)
      doubles.emplace(s.id, fetchDoubleParam(s.id));
    workingSpace = fetchChoiceParam("workingSpace");
    diagnostic = fetchChoiceParam("diagnosticView");
    presetChoice = fetchChoiceParam("preset");
    apertureShape = fetchChoiceParam("apertureShape");
    depthMode = fetchChoiceParam("depthMode");
    captureGate = fetchChoiceParam("captureGate");
    apertureBladeCount = fetchDoubleParam("apertureBladeCount");
    opticalCenter = fetchDouble2DParam("opticalCenter");
    fieldCenter = fetchDouble2DParam("fieldCenter");
    transmission = fetchRGBParam("transmissionColor");
    glare = fetchRGBParam("glareColor");
    nearFocus = fetchRGBParam("nearFocusColor");
    farFocus = fetchRGBParam("farFocusColor");
    anamorphicFlare = fetchRGBParam("anamorphicFlareColor");
    updateApertureControls();
    updateChromaticControls();
    updateDepthControls();
    updateV4Controls();
  }
  void render(const OFX::RenderArguments &a) override {
    if (!a.isEnabledMetalRender)
      OFX::throwSuiteStatusException(kOfxStatErrUnsupported);
    std::unique_ptr<OFX::Image> src(source->fetchImage(a.time)),
        dst(destination->fetchImage(a.time));
    if (!src || !dst || src->getPixelDepth() != OFX::eBitDepthFloat ||
        src->getPixelComponents() != OFX::ePixelComponentRGBA)
      OFX::throwSuiteStatusException(kOfxStatErrUnsupported);
    Processor processor(*this);
    processor.source = src.get();
    std::unique_ptr<OFX::Image> depth;
    if (depthInput && depthInput->isConnected()) {
      depth.reset(depthInput->fetchImage(a.time));
      if (!depth || depth->getPixelDepth() != OFX::eBitDepthFloat ||
          depth->getPixelComponents() != OFX::ePixelComponentRGBA ||
          depth->getBounds().x2 - depth->getBounds().x1 !=
              src->getBounds().x2 - src->getBounds().x1 ||
          depth->getBounds().y2 - depth->getBounds().y1 !=
              src->getBounds().y2 - src->getBounds().y1)
        OFX::throwSuiteStatusException(kOfxStatErrUnsupported);
      processor.depth = depth.get();
    }
    processor.setDstImg(dst.get());
    processor.setGPURenderArgs(a);
    processor.setRenderWindow(a.renderWindow);
    processor.p = parameters(a.time);
    processor.process();
  }
  bool isIdentity(const OFX::IsIdentityArguments &a, OFX::Clip *&clip,
                  double &time) override {
    if (value("effectBlend", a.time) <= 0) {
      clip = source;
      time = a.time;
      return true;
    }
    return false;
  }
  void changedParam(const OFX::InstanceChangedArgs &args,
                    const std::string &name) override {
    if (inPresetChange)
      return;
    if (name == "loadPreset") {
      std::string path = ChooseLensDebaserPresetToLoad();
      if (!path.empty())
        load(path);
      return;
    }
    if (name == "savePreset") {
      std::string path = ChooseLensDebaserPresetToSave();
      if (!path.empty())
        save(path, args.time);
      return;
    }
    if (name == "preset") {
      int index = 0;
      presetChoice->getValue(index);
      if (index == 0)
        apply(neutralPreset(), true, 0);
      else if (index == 1)
        comparisonPresetIndex = -1;
      else if (index >= 2 && size_t(index - 2) < loaded.size())
        apply(loaded[index - 2], false, index);
      return;
    }
    if (name == "apertureShape" || name == "apertureCatEye")
      updateApertureControls();
    if (name == "longitudinalCA")
      updateChromaticControls();
    if (name == "depthMode")
      updateDepthControls();
    if (name == "captureInfluence" || name == "lookInfluence" ||
        name == "variationAmount" || name == "anamorphicFlareAmount")
      updateV4Controls();
    if (isPresetControl(name)) {
      inPresetChange = true;
      if (comparisonPresetIndex >= 0 &&
          matchesPreset(presetForIndex(comparisonPresetIndex), args.time))
        selectPresetIfNeeded(comparisonPresetIndex);
      else
        selectPresetIfNeeded(1);
      inPresetChange = false;
    }
  }

private:
  double value(const char *id, double t) const {
    return doubles.at(id)->getValueAtTime(t);
  }
  LDBOpticsParameters parameters(double t) const {
    LDBOpticsParameters p = LDBNeutralOpticsParameters(0, 0);
#define D(x) p.x = float(value(#x, t))
    D(distortionK1);
    D(distortionK2);
    D(moustacheK3);
    D(anamorphicSqueeze);
    D(lateralCARed);
    D(lateralCABlue);
    D(longitudinalCA);
    D(longitudinalCARadius);
    D(vignetteNatural);
    D(vignetteOptical);
    D(vignetteMechanical);
    D(imageCircleSize);
    D(imageCircleAspect);
    D(imageCircleSoftness);
    D(cornerSharpnessLoss);
    D(astigmatism);
    D(coma);
    D(comaThreshold);
    D(sphericalHalo);
    D(fieldCurvature);
    D(swirl);
    D(radialSmear);
    D(tangentialSmear);
    D(microContrast);
    D(fineDetail);
    D(detailEdgeFalloff);
    D(sagittalDetail);
    D(tangentialDetail);
    D(detailScale);
    D(bloomEnergy);
    D(bloomThreshold);
    D(bloomRadius);
    D(bloomHorizontalStretch);
    D(glareEnergy);
    D(glareRadius);
    D(effectBlend);
    D(transmissionColorAmount);
    D(glareColorAmount);
    D(apertureResponse);
    D(apertureRadius);
    D(apertureBladeCurvature);
    D(apertureRotation);
    D(apertureSoftness);
    D(apertureCatEye);
    D(apertureAspect);
    D(fieldAspect);
    D(fieldRotation);
    D(transmissionDensity);
    D(transmissionContrast);
    D(transmissionHighlightSoftness);
    D(anamorphicDistortion);
    D(anamorphicAberration);
    D(anamorphicFlareAmount);
    D(anamorphicFlareRadius);
    D(anamorphicFlareThreshold);
    D(variationAmount);
    D(variationFieldAsymmetry);
    D(variationPupilIrregularity);
    D(variationChromaticAsymmetry);
    D(variationTransmissionUnevenness);
    D(responseHighlightKnee);
    D(responseFieldOnset);
    D(responseFieldFalloff);
    D(responseDefocusOnset);
    D(responseDefocusFalloff);
    D(responseScatterEdgeProtection);
    D(depthEdgeSoftness);
    D(captureFocalLength);
    D(captureAperture);
    D(captureFocusDistance);
    D(captureInfluence);
    D(lookCharacter);
    D(lookVintageBias);
    D(lookVintageCaricatureBias);
    D(lookExoticBias);
    D(lookAnamorphicBias);
    D(lookInfluence);
#undef D
    double x, y;
    opticalCenter->getValueAtTime(t, x, y);
    p.opticalCenter = {float(x), float(y)};
    fieldCenter->getValueAtTime(t, x, y);
    p.fieldCenter = {float(x), float(y)};
    int s = 0, d = 0, a = 0, dm = 0, cg = 0;
    workingSpace->getValueAtTime(t, s);
    diagnostic->getValueAtTime(t, d);
    apertureShape->getValueAtTime(t, a);
    depthMode->getValueAtTime(t, dm);
    captureGate->getValueAtTime(t, cg);
    p.depthMode = uint32_t(dm);
    p.depthChannel = 0u;
    p.depthNear = float(value("depthNear", t));
    p.depthFar = float(value("depthFar", t));
    p.depthFocus = float(value("depthFocus", t));
    constexpr float gates[][2] = {
        {36, 24},         {24.89f, 18.66f}, {23.6f, 15.7f},  {17.3f, 13.0f},
        {54.12f, 25.58f}, {12.52f, 7.41f},  {10.26f, 7.49f}, {4.8f, 3.5f},
        {5.79f, 4.01f},   {9.8f, 7.3f},     {47.88f, 24.0f}, {55.8f, 24.0f},
        {72.0f, 24.0f}};
    cg = std::clamp(cg, 0, 12);
    p.captureGateWidth = gates[cg][0];
    p.captureGateHeight = gates[cg][1];
    p.captureFocusDistance =
        value("captureFocusDistance", t) >= 999.5
            ? 1000.0f
            : float(value("captureFocusDistance", t) * .01);
    p.variationSeed = uint32_t(
        std::clamp(std::llround(value("variationSeed", t)), 0ll, 65535ll));
    double bladeValue = 6;
    apertureBladeCount->getValueAtTime(t, bladeValue);
    int blades = std::clamp(int(std::lround(bladeValue)), 3, 32);
    p.workingColorSpace = uint32_t(s);
    p.processingFlags = uint32_t(d) << 8;
    p.apertureShape = uint32_t(a);
    p.apertureBladeCount = uint32_t(blades);
    double r, g, b;
    transmission->getValueAtTime(t, r, g, b);
    p.transmissionColor = {float(r), float(g), float(b)};
    glare->getValueAtTime(t, r, g, b);
    p.glareColor = {float(r), float(g), float(b)};
    nearFocus->getValueAtTime(t, r, g, b);
    p.nearFocusColor = {float(r), float(g), float(b)};
    farFocus->getValueAtTime(t, r, g, b);
    p.farFocusColor = {float(r), float(g), float(b)};
    anamorphicFlare->getValueAtTime(t, r, g, b);
    p.anamorphicFlareColor = {float(r), float(g), float(b)};
    return p;
  }
  Preset neutralPreset() const {
    Preset p;
    p.name = "Clean Slate";
    for (const auto &s : kSpecs)
      p.values[s.id] = s.value;
    return p;
  }
  Preset snapshot(const std::string &name, double time) const {
    Preset p;
    p.name = name;
    for (const auto &s : kSpecs)
      p.values[s.id] = value(s.id, time);
    opticalCenter->getValueAtTime(time, p.center[0], p.center[1]);
    fieldCenter->getValueAtTime(time, p.fieldCenter[0], p.fieldCenter[1]);
    transmission->getValueAtTime(time, p.transmission[0], p.transmission[1],
                                 p.transmission[2]);
    glare->getValueAtTime(time, p.glare[0], p.glare[1], p.glare[2]);
    nearFocus->getValueAtTime(time, p.nearFocus[0], p.nearFocus[1],
                              p.nearFocus[2]);
    farFocus->getValueAtTime(time, p.farFocus[0], p.farFocus[1], p.farFocus[2]);
    anamorphicFlare->getValueAtTime(time, p.anamorphicFlare[0],
                                    p.anamorphicFlare[1], p.anamorphicFlare[2]);
    apertureShape->getValueAtTime(time, p.apertureShape);
    depthMode->getValueAtTime(time, p.depthMode);
    captureGate->getValueAtTime(time, p.captureGate);
    double blades = 6;
    apertureBladeCount->getValueAtTime(time, blades);
    p.apertureBladeCount = std::clamp(int(std::lround(blades)), 3, 32);
    return p;
  }
  bool isPresetControl(const std::string &name) const {
    for (const auto &s : kSpecs)
      if (name == s.id)
        return true;
    static const std::array<const char *, 17> otherControls = {
        "opticalCenter",
        "fieldCenter",
        "transmissionColor",
        "glareColor",
        "nearFocusColor",
        "farFocusColor",
        "anamorphicFlareColor",
        "apertureShape",
        "apertureBladeCount",
        "depthMode",
        "captureGate",
        "opticalCenterX",
        "opticalCenterY",
        "fieldCenterX",
        "fieldCenterY",
        "depthNear",
        "depthFar"};
    return std::find(otherControls.begin(), otherControls.end(), name) !=
           otherControls.end();
  }
  const Preset &presetForIndex(int index) const {
    if (index == 0)
      return cleanSlateComparison;
    return loaded.at(size_t(index - 2));
  }
  bool matchesPreset(const Preset &target, double time) const {
    const Preset current = snapshot("", time);
    auto close = [](double a, double b) { return std::abs(a - b) <= 1e-6; };
    for (const auto &s : kSpecs)
      if (!close(current.values.at(s.id), target.values.at(s.id)))
        return false;
    auto arrayClose = [&](const auto &a, const auto &b) {
      for (size_t i = 0; i < a.size(); ++i)
        if (!close(a[i], b[i]))
          return false;
      return true;
    };
    return arrayClose(current.center, target.center) &&
           arrayClose(current.fieldCenter, target.fieldCenter) &&
           arrayClose(current.transmission, target.transmission) &&
           arrayClose(current.glare, target.glare) &&
           arrayClose(current.nearFocus, target.nearFocus) &&
           arrayClose(current.farFocus, target.farFocus) &&
           arrayClose(current.anamorphicFlare, target.anamorphicFlare) &&
           current.apertureShape == target.apertureShape &&
           current.apertureBladeCount == target.apertureBladeCount &&
           current.depthMode == target.depthMode &&
           current.captureGate == target.captureGate;
  }
  void updateApertureControls() {
    int shape = 0;
    apertureShape->getValue(shape);
    double catEye = 0;
    doubles.at("apertureCatEye")->getValue(catEye);
    bool polygon = shape == 1, oval = shape == 2;
    apertureBladeCount->setEnabled(polygon);
    doubles.at("apertureBladeCurvature")->setEnabled(polygon);
    doubles.at("apertureRotation")->setEnabled(polygon || oval);
    doubles.at("apertureAspect")->setEnabled(oval || catEye > 1e-8);
  }
  void updateChromaticControls() {
    double amount = 0;
    doubles.at("longitudinalCA")->getValue(amount);
    bool active = amount > 1e-8;
    doubles.at("longitudinalCARadius")->setEnabled(active);
    nearFocus->setEnabled(active);
    farFocus->setEnabled(active);
  }
  void updateDepthControls() {
    int mode = 0;
    depthMode->getValue(mode);
    bool active = mode > 0;
    depthMode->setEnabled(true);
    doubles.at("depthNear")->setEnabled(active);
    doubles.at("depthFar")->setEnabled(active);
    doubles.at("depthFocus")->setEnabled(active);
    doubles.at("responseScatterEdgeProtection")->setEnabled(active);
    doubles.at("depthEdgeSoftness")->setEnabled(active);
  }
  void updateV4Controls() {
    auto enabledBy = [&](const char *parent,
                         std::initializer_list<const char *> children) {
      double amount = 0;
      doubles.at(parent)->getValue(amount);
      for (auto child : children)
        doubles.at(child)->setEnabled(amount > 1e-8);
    };
    enabledBy("captureInfluence", {"captureFocalLength", "captureAperture",
                                   "captureFocusDistance"});
    double captureAmount = 0;
    doubles.at("captureInfluence")->getValue(captureAmount);
    captureGate->setEnabled(captureAmount > 1e-8);
    enabledBy("lookInfluence",
              {"lookCharacter", "lookVintageBias", "lookVintageCaricatureBias",
               "lookExoticBias", "lookAnamorphicBias"});
    enabledBy("variationAmount",
              {"variationSeed", "variationFieldAsymmetry",
               "variationPupilIrregularity", "variationChromaticAsymmetry",
               "variationTransmissionUnevenness"});
    enabledBy("anamorphicFlareAmount",
              {"anamorphicFlareRadius", "anamorphicFlareThreshold"});
    double flareAmount = 0;
    doubles.at("anamorphicFlareAmount")->getValue(flareAmount);
    anamorphicFlare->setEnabled(flareAmount > 1e-8);
  }
  void setGroupOpen(const char *name, bool open) {
    OfxParamSetHandle set = nullptr;
    OfxParamHandle param = nullptr;
    OfxPropertySetHandle props = nullptr;
    if (OFX::Private::gEffectSuite->getParamSet(handle, &set) == kOfxStatOK &&
        OFX::Private::gParamSuite->paramGetHandle(set, name, &param, &props) ==
            kOfxStatOK)
      OFX::Private::gPropSuite->propSetInt(props, kOfxParamPropGroupOpen, 0,
                                           open ? 1 : 0);
  }
  void updateGroups(const Preset &p) {
    auto active = [&](std::initializer_list<const char *> ids) {
      for (auto id : ids) {
        for (const auto &s : kSpecs)
          if (std::string(s.id) == id &&
              std::abs(p.values.at(id) - s.value) > 1e-8)
            return true;
      }
      return false;
    };
    setGroupOpen("geometry",
                 active({"distortionK1", "distortionK2", "moustacheK3",
                         "anamorphicSqueeze", "swirl"}) ||
                     p.center != std::array<double, 2>{.5, .5});
    setGroupOpen("focusField",
                 active({"cornerSharpnessLoss", "fieldCurvature", "astigmatism",
                         "radialSmear", "tangentialSmear"}));
    setGroupOpen("detail",
                 active({"microContrast", "fineDetail", "detailEdgeFalloff",
                         "sagittalDetail", "tangentialDetail", "detailScale"}));
    setGroupOpen("chromatic",
                 active({"lateralCARed", "lateralCABlue", "longitudinalCA",
                         "longitudinalCARadius"}));
    setGroupOpen("vignette", active({"vignetteNatural", "vignetteOptical"}));
    setGroupOpen("aperture", active({"apertureResponse", "apertureRadius",
                                     "apertureBladeCurvature",
                                     "apertureRotation", "apertureSoftness",
                                     "apertureCatEye", "apertureAspect"}) ||
                                 p.apertureShape != 0 ||
                                 p.apertureBladeCount != 6);
    setGroupOpen("bloom", active({"bloomEnergy", "bloomThreshold",
                                  "bloomRadius", "bloomHorizontalStretch"}));
    setGroupOpen("glareHalo", active({"glareEnergy", "glareRadius",
                                      "glareColorAmount", "sphericalHalo"}));
    setGroupOpen(
        "transmission",
        active({"transmissionColorAmount", "transmissionDensity",
                "transmissionContrast", "transmissionHighlightSoftness"}));
    setGroupOpen("offAxis", active({"coma", "comaThreshold"}));
    setGroupOpen("capture", active({"captureInfluence"}));
    setGroupOpen("look", active({"lookInfluence"}));
    setGroupOpen("fieldShape",
                 active({"fieldAspect", "fieldRotation", "swirl"}) ||
                     p.fieldCenter != std::array<double, 2>{.5, .5});
    setGroupOpen("anamorphic",
                 active({"anamorphicSqueeze", "anamorphicDistortion",
                         "anamorphicAberration", "anamorphicFlareAmount"}));
    setGroupOpen("imageCircle",
                 active({"vignetteMechanical", "imageCircleSize",
                         "imageCircleAspect", "imageCircleSoftness"}));
    setGroupOpen("variation", active({"variationAmount"}));
    setGroupOpen(
        "responses",
        active({"responseHighlightKnee", "responseFieldOnset",
                "responseFieldFalloff", "responseDefocusOnset",
                "responseDefocusFalloff"}));
    setGroupOpen("opticsSection",
                 active({"distortionK1",
                         "distortionK2",
                         "moustacheK3",
                         "anamorphicSqueeze",
                         "swirl",
                         "cornerSharpnessLoss",
                         "fieldCurvature",
                         "astigmatism",
                         "radialSmear",
                         "tangentialSmear",
                         "microContrast",
                         "fineDetail",
                         "detailEdgeFalloff",
                         "sagittalDetail",
                         "tangentialDetail",
                         "detailScale",
                         "lateralCARed",
                         "lateralCABlue",
                         "longitudinalCA",
                         "longitudinalCARadius",
                         "fieldAspect",
                         "fieldRotation",
                         "anamorphicDistortion",
                         "anamorphicAberration",
                         "anamorphicFlareAmount"}) ||
                     p.center != std::array<double, 2>{.5, .5} ||
                     p.fieldCenter != std::array<double, 2>{.5, .5});
    setGroupOpen(
        "pupilSection",
        active({"apertureResponse", "apertureRadius", "apertureBladeCurvature",
                "apertureRotation", "apertureSoftness", "apertureCatEye",
                "apertureAspect", "vignetteNatural", "vignetteOptical",
                "vignetteMechanical", "imageCircleSize", "imageCircleAspect",
                "imageCircleSoftness"}) ||
            p.apertureShape != 0 || p.apertureBladeCount != 6);
    setGroupOpen(
        "lightSection",
        active({"bloomEnergy", "bloomThreshold", "bloomRadius",
                "bloomHorizontalStretch", "glareEnergy", "glareRadius",
                "glareColorAmount", "sphericalHalo", "transmissionColorAmount",
                "transmissionDensity", "transmissionContrast",
                "transmissionHighlightSoftness"}));
    setGroupOpen("depthGroup", p.depthMode > 0);
    setGroupOpen(
        "advancedSection",
        active({"coma", "comaThreshold", "variationAmount",
                "responseHighlightKnee", "responseFieldOnset",
                "responseFieldFalloff", "responseDefocusOnset",
                "responseDefocusFalloff", "responseScatterEdgeProtection",
                "depthEdgeSoftness"}) ||
            p.depthMode > 0);
  }
  void selectPresetIfNeeded(int desired) {
    int current = -1;
    presetChoice->getValue(current);
    if (current != desired)
      presetChoice->setValue(desired);
  }
  void apply(const Preset &p, bool clean, int presetIndex = -1) {
    inPresetChange = true;
    if (clean)
      cleanSlateComparison = p;
    comparisonPresetIndex =
        clean ? 0 : (presetIndex >= 2 ? presetIndex : int(loaded.size() + 1));
    beginEditBlock(clean ? "Reset Lens Debaser" : "Load Lens Debaser Preset");
    for (const auto &s : kSpecs) {
      auto it = p.values.find(s.id);
      doubles.at(s.id)->setValue(it == p.values.end() ? s.value : it->second);
    }
    opticalCenter->setValue(p.center[0], p.center[1]);
    fieldCenter->setValue(p.fieldCenter[0], p.fieldCenter[1]);
    transmission->setValue(p.transmission[0], p.transmission[1],
                           p.transmission[2]);
    glare->setValue(p.glare[0], p.glare[1], p.glare[2]);
    nearFocus->setValue(p.nearFocus[0], p.nearFocus[1], p.nearFocus[2]);
    farFocus->setValue(p.farFocus[0], p.farFocus[1], p.farFocus[2]);
    anamorphicFlare->setValue(p.anamorphicFlare[0], p.anamorphicFlare[1],
                              p.anamorphicFlare[2]);
    apertureShape->setValue(std::clamp(p.apertureShape, 0, 2));
    apertureBladeCount->setValue(std::clamp(p.apertureBladeCount, 3, 32));
    depthMode->setValue(std::clamp(p.depthMode, 0, 5));
    captureGate->setValue(std::clamp(p.captureGate, 0, 12));
    selectPresetIfNeeded(comparisonPresetIndex);
    endEditBlock();
    updateApertureControls();
    updateChromaticControls();
    updateDepthControls();
    updateV4Controls();
    updateGroups(p);
    inPresetChange = false;
  }
  void refreshChoices() {
    presetChoice->resetOptions();
    presetChoice->appendOption("Clean Slate");
    presetChoice->appendOption("Custom");
    for (const auto &p : loaded)
      presetChoice->appendOption(p.name);
  }
  bool readPreset(const std::string &path, Preset &p, bool showError) {
    std::ifstream f(path);
    if (!f) {
      if (showError)
        sendMessage(OFX::Message::eMessageError, "preset",
                    "Unable to open preset file.");
      return false;
    }
    p = neutralPreset();
    p.name = std::filesystem::path(path).stem().string();
    std::string line;
    int presetVersion = 0;
    bool focusDistanceRead = false;
    while (std::getline(f, line)) {
      auto pos = line.find('=');
      if (pos == std::string::npos)
        continue;
      std::string key = line.substr(0, pos), v = line.substr(pos + 1);
      if (key == "LensDebaserPreset") {
        try {
          presetVersion = std::stoi(v);
        } catch (...) {
          presetVersion = 0;
        }
        continue;
      }
      try {
        double n = std::stod(v);
        if (p.values.count(key)) {
          p.values[key] = n;
          if (key == "captureFocusDistance")
            focusDistanceRead = true;
        } else if (key == "apertureShape")
          p.apertureShape = int(n);
        else if (key == "apertureBladeCount")
          p.apertureBladeCount = int(std::lround(n));
        else if (key == "depthMode")
          p.depthMode = int(n);
        else if (key == "captureGate")
          p.captureGate = int(n);
        else if (key == "opticalCenterX")
          p.center[0] = n;
        else if (key == "opticalCenterY")
          p.center[1] = n;
        else if (key == "fieldCenterX")
          p.fieldCenter[0] = n;
        else if (key == "fieldCenterY")
          p.fieldCenter[1] = n;
        else if (key == "anamorphicFlareR")
          p.anamorphicFlare[0] = n;
        else if (key == "anamorphicFlareG")
          p.anamorphicFlare[1] = n;
        else if (key == "anamorphicFlareB")
          p.anamorphicFlare[2] = n;
        else if (key == "transmissionR")
          p.transmission[0] = n;
        else if (key == "transmissionG")
          p.transmission[1] = n;
        else if (key == "transmissionB")
          p.transmission[2] = n;
        else if (key == "glareR")
          p.glare[0] = n;
        else if (key == "glareG")
          p.glare[1] = n;
        else if (key == "glareB")
          p.glare[2] = n;
        else if (key == "nearFocusR")
          p.nearFocus[0] = n;
        else if (key == "nearFocusG")
          p.nearFocus[1] = n;
        else if (key == "nearFocusB")
          p.nearFocus[2] = n;
        else if (key == "farFocusR")
          p.farFocus[0] = n;
        else if (key == "farFocusG")
          p.farFocus[1] = n;
        else if (key == "farFocusB")
          p.farFocus[2] = n;
      } catch (...) {
      }
    }
    if (presetVersion < 1 || presetVersion > 2) {
      if (showError)
        sendMessage(OFX::Message::eMessageError, "preset",
                    "Not a supported Lens Debaser .ldbpreset file.");
      return false;
    }
    // Version 1 stored Capture Focus Distance in metres. Version 2 presents
    // and stores centimetres while retaining the same persisted parameter ID.
    if (presetVersion == 1 && focusDistanceRead)
      p.values["captureFocusDistance"] *= 100.0;
    return true;
  }
  void load(const std::string &path) {
    const std::filesystem::path selectedPath =
        std::filesystem::absolute(path).lexically_normal();
    Preset selected;
    if (!readPreset(selectedPath.string(), selected, true))
      return;

    std::vector<std::filesystem::path> paths;
    std::error_code error;
    for (const auto &entry : std::filesystem::directory_iterator(
             selectedPath.parent_path(), error)) {
      if (entry.is_regular_file() && entry.path().extension() == ".ldbpreset")
        paths.push_back(entry.path());
    }
    std::sort(paths.begin(), paths.end(), [](const auto &a, const auto &b) {
      return a.filename().string() < b.filename().string();
    });

    loaded.clear();
    int selectedIndex = -1;
    for (const auto &candidate : paths) {
      Preset preset;
      if (!readPreset(candidate.string(), preset, false))
        continue;
      if (std::filesystem::absolute(candidate).lexically_normal() ==
          selectedPath)
        selectedIndex = int(loaded.size());
      loaded.push_back(std::move(preset));
    }
    if (selectedIndex < 0) {
      selectedIndex = int(loaded.size());
      loaded.push_back(std::move(selected));
    }
    refreshChoices();
    apply(loaded[size_t(selectedIndex)], false, selectedIndex + 2);
  }
  void save(std::string path, double time) {
    if (std::filesystem::path(path).extension() != ".ldbpreset")
      path += ".ldbpreset";
    Preset p = snapshot(std::filesystem::path(path).stem().string(), time);
    std::ofstream f(path);
    if (!f) {
      sendMessage(OFX::Message::eMessageError, "preset",
                  "Unable to save preset file.");
      return;
    }
    f << "LensDebaserPreset=2\n";
    for (const auto &s : kSpecs)
      f << s.id << '=' << p.values[s.id] << '\n';
    f << "apertureShape=" << p.apertureShape << '\n'
      << "apertureBladeCount=" << p.apertureBladeCount << '\n'
      << "depthMode=" << p.depthMode << '\n'
      << "captureGate=" << p.captureGate << '\n'
      << "opticalCenterX=" << p.center[0] << "\nopticalCenterY=" << p.center[1]
      << '\n'
      << "fieldCenterX=" << p.fieldCenter[0]
      << "\nfieldCenterY=" << p.fieldCenter[1] << '\n'
      << "anamorphicFlareR=" << p.anamorphicFlare[0]
      << "\nanamorphicFlareG=" << p.anamorphicFlare[1]
      << "\nanamorphicFlareB=" << p.anamorphicFlare[2] << '\n'
      << "transmissionR=" << p.transmission[0]
      << "\ntransmissionG=" << p.transmission[1]
      << "\ntransmissionB=" << p.transmission[2] << '\n'
      << "glareR=" << p.glare[0] << "\nglareG=" << p.glare[1]
      << "\nglareB=" << p.glare[2] << '\n'
      << "nearFocusR=" << p.nearFocus[0] << "\nnearFocusG=" << p.nearFocus[1]
      << "\nnearFocusB=" << p.nearFocus[2] << '\n'
      << "farFocusR=" << p.farFocus[0] << "\nfarFocusG=" << p.farFocus[1]
      << "\nfarFocusB=" << p.farFocus[2] << '\n';
    f.close();
    load(path);
  }
  OfxImageEffectHandle handle;
  Preset cleanSlateComparison = neutralPreset();
  int comparisonPresetIndex = 0;
  OFX::Clip *source = nullptr, *destination = nullptr, *depthInput = nullptr;
  OFX::ChoiceParam *workingSpace = nullptr, *diagnostic = nullptr,
                   *presetChoice = nullptr,
                   *apertureShape = nullptr, *depthMode = nullptr,
                   *captureGate = nullptr;
  OFX::DoubleParam *apertureBladeCount = nullptr;
  OFX::Double2DParam *opticalCenter = nullptr, *fieldCenter = nullptr;
  OFX::RGBParam *transmission = nullptr, *glare = nullptr, *nearFocus = nullptr,
                *farFocus = nullptr, *anamorphicFlare = nullptr;
  std::unordered_map<std::string, OFX::DoubleParam *> doubles;
  std::vector<Preset> loaded;
  bool inPresetChange = false;
};

OFX::DoubleParamDescriptor *addDouble(OFX::ImageEffectDescriptor &d,
                                      const DoubleSpec &s,
                                      OFX::GroupParamDescriptor &g,
                                      OFX::PageParamDescriptor &p) {
  auto *x = d.defineDoubleParam(s.id);
  x->setLabels(s.label, s.label, s.label);
  x->setScriptName(s.id);
  x->setHint(s.hint);
  x->setDefault(s.value);
  x->setRange(s.low, s.high);
  x->setDisplayRange(s.low, s.high);
  x->setIncrement(s.step);
  x->setParent(g);
  p.addChild(*x);
  return x;
}
OFX::GroupParamDescriptor *addGroup(OFX::ImageEffectDescriptor &d,
                                    OFX::PageParamDescriptor &p, const char *id,
                                    const char *label, bool open = false) {
  auto *g = d.defineGroupParam(id);
  g->setLabels(label, label, label);
  g->setOpen(open);
  p.addChild(*g);
  return g;
}
} // namespace

LensDebaserPluginFactory::LensDebaserPluginFactory()
    : PluginFactoryHelper(kIdentifier, 1, 35) {}
void LensDebaserPluginFactory::describe(OFX::ImageEffectDescriptor &d) {
  d.setLabels(kName, kName, kName);
  d.getPropertySet().propSetString(kOfxPropIcon, "com.ldb.LensDebaser.png", 1,
                                   false);
  d.setPluginGrouping("LDB");
  d.setPluginDescription("Perceptual cinematic lens character for Apple "
                         "Silicon and DaVinci Resolve.");
  d.addSupportedContext(OFX::eContextFilter);
  d.addSupportedContext(OFX::eContextGeneral);
  d.addSupportedBitDepth(OFX::eBitDepthFloat);
  d.setSupportsMetalRender(true);
  d.setSupportsTiles(false);
  d.setSupportsMultiResolution(false);
  d.setTemporalClipAccess(false);
  d.setHostFrameThreading(false);
  d.setRenderTwiceAlways(false);
  d.setNoSpatialAwareness(false);
}
void LensDebaserPluginFactory::describeInContext(OFX::ImageEffectDescriptor &d,
                                                 OFX::ContextEnum context) {
  auto *src = d.defineClip(kOfxImageEffectSimpleSourceClipName);
  src->addSupportedComponent(OFX::ePixelComponentRGBA);
  src->setSupportsTiles(false);
  if (context == OFX::eContextGeneral) {
    auto *depth = d.defineClip(kDepthClipName);
    depth->setLabels("Depth Map", "Depth Map", "Depth Map");
    depth->addSupportedComponent(OFX::ePixelComponentRGBA);
    depth->setOptional(true);
    depth->setSupportsTiles(false);
  }
  auto *dst = d.defineClip(kOfxImageEffectOutputClipName);
  dst->addSupportedComponent(OFX::ePixelComponentRGBA);
  dst->setSupportsTiles(false);
  auto *page = d.definePageParam("Controls");
  auto *setup = page;
  auto *optics = page;
  auto *pupil = page;
  auto *light = page;
  auto *advanced = page;
  auto *setupSection = addGroup(d, *page, "setupSection", "Setup", true);
  auto *opticsSection = addGroup(d, *page, "opticsSection", "Optics", true);
  auto *pupilSection = addGroup(d, *page, "pupilSection", "Pupil & Vignette");
  auto *lightSection = addGroup(d, *page, "lightSection", "Light");
  auto *advancedSection = addGroup(d, *page, "advancedSection", "Advanced");
  auto *output = addGroup(d, *page, "output", "Blend", true);
  auto *presetGroup = addGroup(d, *setup, "presetGroup", "Presets", true);
  presetGroup->setParent(*setupSection);
  auto *preset = d.defineChoiceParam("preset");
  preset->setLabels("Preset", "Preset", "Preset");
  preset->appendOption("Clean Slate");
  preset->appendOption("Custom");
  preset->setDefault(0);
  preset->setParent(*presetGroup);
  setup->addChild(*preset);
  auto *load = d.definePushButtonParam("loadPreset");
  load->setLabels("Load", "Load", "Load");
  load->setParent(*presetGroup);
  setup->addChild(*load);
  auto *save = d.definePushButtonParam("savePreset");
  save->setLabels("Save", "Save", "Save");
  save->setParent(*presetGroup);
  setup->addChild(*save);
  auto *processing = addGroup(d, *setup, "processing", "Processing", true);
  processing->setParent(*setupSection);
  auto *ws = d.defineChoiceParam("workingSpace");
  ws->setLabels("Input Working Space", "Input Working Space",
                "Input Working Space");
  for (auto *s :
       {"ACEScg (Linear AP1)", "ACEScct", "DaVinci Wide Gamut / Intermediate",
        "ARRI LogC3 EI800", "ARRI LogC4"})
    ws->appendOption(s);
  ws->setDefault(2);
  ws->setHint("Must match the image encoding entering Lens Debaser. Not stored "
              "in presets.");
  ws->setParent(*processing);
  setup->addChild(*ws);
  auto *diag = d.defineChoiceParam("diagnosticView");
  diag->setLabels("Diagnostic View", "Diagnostic View", "Diagnostic View");
  diag->setHint("Scatter Only is black when no bloom, glare or halo energy is "
                "present. Direct Optics Only excludes those scatter layers. "
                "Depth Input displays normalized depth. Defocus Amount shows "
                "distance from Focus Depth. Depth Rejection shows protected "
                "map boundaries.");
  for (auto *s : {"Off", "Difference (Amplified)", "Scatter Only",
                  "Direct Optics Only", "Depth Input", "Defocus Amount",
                  "Depth Rejection"})
    diag->appendOption(s);
  diag->setDefault(0);
  diag->setParent(*processing);
  setup->addChild(*diag);
  auto *capture = addGroup(d, *setup, "capture", "Capture");
  capture->setParent(*setupSection);
  auto *look = addGroup(d, *setup, "look", "Look");
  look->setParent(*setupSection);
  auto *geometry = addGroup(d, *optics, "geometry", "Geometry");
  auto *fieldShape = addGroup(d, *optics, "fieldShape", "Field Shape");
  auto *focus = addGroup(d, *optics, "focusField", "Focus & Field");
  auto *detail = addGroup(d, *optics, "detail", "Detail Transfer");
  auto *chromatic = addGroup(d, *optics, "chromatic", "Chromatic Aberration");
  auto *anamorphic = addGroup(d, *optics, "anamorphic", "Anamorphic");
  geometry->setParent(*opticsSection);
  fieldShape->setParent(*opticsSection);
  focus->setParent(*opticsSection);
  detail->setParent(*opticsSection);
  chromatic->setParent(*opticsSection);
  anamorphic->setParent(*opticsSection);
  auto *aperture = addGroup(d, *pupil, "aperture", "Aperture", true);
  auto *vignette = addGroup(d, *pupil, "vignette", "Vignette");
  auto *imageCircle = addGroup(d, *pupil, "imageCircle", "Image Circle");
  aperture->setParent(*pupilSection);
  vignette->setParent(*pupilSection);
  imageCircle->setParent(*pupilSection);
  auto *bloom = addGroup(d, *light, "bloom", "Bloom");
  auto *glareHalo = addGroup(d, *light, "glareHalo", "Glare & Halo");
  auto *transmissionGroup = addGroup(d, *light, "transmission", "Transmission");
  bloom->setParent(*lightSection);
  glareHalo->setParent(*lightSection);
  transmissionGroup->setParent(*lightSection);
  auto *offAxis = addGroup(d, *advanced, "offAxis", "Off-Axis Character");
  offAxis->setParent(*advancedSection);
  auto *variation = addGroup(d, *advanced, "variation", "Variation");
  variation->setParent(*advancedSection);
  auto *responses = addGroup(d, *advanced, "responses", "Advanced Responses");
  responses->setParent(*advancedSection);
  auto *depthGroup = addGroup(d, *advanced, "depthGroup", "Depth Input");
  depthGroup->setParent(*advancedSection);
  auto *dm = d.defineChoiceParam("depthMode");
  dm->setLabels("Depth Interpretation", "Depth Interpretation",
                "Depth Interpretation");
  for (auto *s : {"Depth-Free", "Near White", "Near Black", "Linear Camera Z",
                  "Inverse Z / Disparity", "Logarithmic Z"})
    dm->appendOption(s);
  dm->setDefault(0);
  dm->setHint(
      "External modes read luminance from the dedicated Depth Map RGB input. "
      "Depth drives Aperture "
      "Response, Longitudinal Amount, Spherical Halo, and Bloom/Glare "
      "occlusion. Depth-Free preserves the local approximation.");
  dm->setParent(*depthGroup);
  advanced->addChild(*dm);
  auto *shape = d.defineChoiceParam("apertureShape");
  shape->setLabels("Aperture Shape", "Aperture Shape", "Aperture Shape");
  shape->appendOption("Circular");
  shape->appendOption("Polygon");
  shape->appendOption("Oval / Anamorphic");
  shape->setDefault(0);
  shape->setHint("Selects the continuous aperture-response approximation; "
                 "Aperture Response must be above zero.");
  shape->setParent(*aperture);
  pupil->addChild(*shape);
  auto *center = d.defineDouble2DParam("opticalCenter");
  center->setLabels("Optical Center", "Optical Center", "Optical Center");
  center->setDimensionLabels("X", "Y");
  center->setDefault(.5, .5);
  center->setRange(0, 0, 1, 1);
  center->setDisplayRange(0, 0, 1, 1);
  center->setParent(*geometry);
  optics->addChild(*center);
  auto *fieldCentre = d.defineDouble2DParam("fieldCenter");
  fieldCentre->setLabels("Field Center", "Field Center", "Field Center");
  fieldCentre->setDimensionLabels("X", "Y");
  fieldCentre->setDefault(.5, .5);
  fieldCentre->setRange(0, 0, 1, 1);
  fieldCentre->setDisplayRange(0, 0, 1, 1);
  fieldCentre->setParent(*fieldShape);
  optics->addChild(*fieldCentre);
  for (const auto &s : kSpecs) {
    std::string id = s.id;
    OFX::GroupParamDescriptor *g = geometry;
    OFX::PageParamDescriptor *p = optics;
    if (id.rfind("capture", 0) == 0) {
      g = capture;
      p = setup;
    } else if (id.rfind("look", 0) == 0) {
      g = look;
      p = setup;
    } else if (id == "fieldAspect" || id == "fieldRotation" || id == "swirl")
      g = fieldShape;
    else if (id == "cornerSharpnessLoss" || id == "fieldCurvature" ||
             id == "astigmatism" || id == "radialSmear" ||
             id == "tangentialSmear")
      g = focus;
    else if (id == "microContrast" || id == "fineDetail" ||
             id == "detailEdgeFalloff" || id == "sagittalDetail" ||
             id == "tangentialDetail" || id == "detailScale")
      g = detail;
    else if (id == "lateralCARed" || id == "lateralCABlue" ||
             id == "longitudinalCA" || id == "longitudinalCARadius")
      g = chromatic;
    else if (id.rfind("anamorphic", 0) == 0) {
      g = anamorphic;
      p = optics;
    } else if (id == "depthNear" || id == "depthFar" || id == "depthFocus" ||
               id == "responseScatterEdgeProtection" ||
               id == "depthEdgeSoftness") {
      g = depthGroup;
      p = advanced;
    } else if (id.rfind("aperture", 0) == 0) {
      g = aperture;
      p = pupil;
    } else if (id.rfind("imageCircle", 0) == 0) {
      g = imageCircle;
      p = pupil;
    } else if (id.rfind("vignette", 0) == 0) {
      g = vignette;
      p = pupil;
    } else if (id.rfind("bloom", 0) == 0) {
      g = bloom;
      p = light;
    } else if (id.rfind("glare", 0) == 0 || id == "sphericalHalo") {
      g = glareHalo;
      p = light;
    } else if (id.rfind("transmission", 0) == 0) {
      g = transmissionGroup;
      p = light;
    } else if (id.rfind("variation", 0) == 0) {
      g = variation;
      p = advanced;
    } else if (id.rfind("response", 0) == 0) {
      g = responses;
      p = advanced;
    } else if (id == "coma" || id == "comaThreshold") {
      g = offAxis;
      p = advanced;
    } else if (id == "effectBlend") {
      g = output;
      p = advanced;
    }
    if (id == "captureFocusDistance") {
      auto *gate = d.defineChoiceParam("captureGate");
      gate->setLabels("Gate / Capture Format", "Gate / Capture Format",
                      "Gate / Capture Format");
      for (auto *option :
           {"Full Frame Open Gate 36 x 24", "Super 35 24.89 x 18.66",
            "APS-C 23.6 x 15.7", "Micro Four Thirds 17.3 x 13",
            "65mm 54.12 x 25.58", "Super 16mm 12.52 x 7.41",
            "16mm 10.26 x 7.49", "8mm 4.8 x 3.5", "Super 8mm 5.79 x 4.01",
            "Smartphone (Approx.) 9.8 x 7.3", "Full Frame + 1.33x Anamorphic",
            "Full Frame + 1.55x Anamorphic", "Full Frame + 2x Anamorphic"})
        gate->appendOption(option);
      gate->setDefault(0);
      gate->setHint(
          "Sensor, film gate, or full-frame anamorphic field-coverage "
          "context used by Capture mapping; it does not desqueeze the image.");
      gate->setParent(*capture);
      setup->addChild(*gate);
    }
    if (id == "apertureBladeCurvature") {
      auto *blades = d.defineDoubleParam("apertureBladeCount");
      blades->setLabels("Blade Count", "Blade Count", "Blade Count");
      blades->setScriptName("apertureBladeCount");
      blades->setHint("Whole-number blade count used by Polygon shape; high "
                      "counts approach a circular iris.");
      blades->setDefault(6);
      blades->setRange(3, 32);
      blades->setDisplayRange(3, 32);
      blades->setIncrement(1);
      blades->setDigits(0);
      blades->setParent(*aperture);
      pupil->addChild(*blades);
    }
    addDouble(d, s, *g, *p);
  }
  auto addColor = [&](const char *id, const char *label,
                      OFX::GroupParamDescriptor &g, OFX::PageParamDescriptor &p,
                      double r = 1, double green = 1, double b = 1) {
    auto *x = d.defineRGBParam(id);
    x->setLabels(label, label, label);
    x->setDefault(r, green, b);
    x->setRange(0, 2, 0, 2, 0, 2);
    x->setDisplayRange(0, 1, 0, 1, 0, 1);
    x->setParent(g);
    p.addChild(*x);
  };
  addColor("transmissionColor", "Transmission Color", *transmissionGroup,
           *light);
  addColor("glareColor", "Glare Color", *glareHalo, *light);
  addColor("nearFocusColor", "Near-Focus Color", *chromatic, *optics, 1, .35,
           .75);
  addColor("farFocusColor", "Far-Focus Color", *chromatic, *optics, .35, 1,
           .65);
  addColor("anamorphicFlareColor", "Flare Color", *anamorphic, *optics, .35,
           .55, 1);
}
OFX::ImageEffect *
LensDebaserPluginFactory::createInstance(OfxImageEffectHandle h,
                                         OFX::ContextEnum) {
  return new Plugin(h);
}
void OFX::Plugin::getPluginIDs(PluginFactoryArray &a) {
  static LensDebaserPluginFactory f;
  a.push_back(&f);
}
