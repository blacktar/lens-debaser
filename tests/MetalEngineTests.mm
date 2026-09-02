#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "LDBColorReference.h"
#include "LDBOpticsEngine.h"

static void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        std::exit(1);
    }
}

static std::vector<simd_float4> render(LDBOpticsEngine& engine,
                                       id<MTLDevice> device,
                                       id<MTLCommandQueue> queue,
                                       const std::vector<simd_float4>& input,
                                       uint32_t width,
                                       uint32_t height,
                                       const LDBOpticsParameters& parameters) {
    NSUInteger bytes = input.size() * sizeof(simd_float4);
    id<MTLBuffer> src = [device newBufferWithBytes:input.data() length:bytes options:MTLResourceStorageModeShared];
    id<MTLBuffer> dst = [device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    engine.encode(command, src, dst, width, height, parameters);
    [command commit];
    [command waitUntilCompleted];
    require(command.status == MTLCommandBufferStatusCompleted, "Metal command did not complete");
    simd_float4* values = static_cast<simd_float4*>(dst.contents);
    return std::vector<simd_float4>(values, values + input.size());
}

static float maxDifference(const std::vector<simd_float4>& a, const std::vector<simd_float4>& b) {
    float result = 0.0f;
    for (size_t i = 0; i < a.size(); ++i) {
        simd_float4 d = simd_abs(a[i] - b[i]);
        result = std::max(result, std::max(std::max(d.x, d.y), std::max(d.z, d.w)));
    }
    return result;
}

static float maxAlphaDifference(const std::vector<simd_float4>& a, const std::vector<simd_float4>& b) {
    float result = 0.0f;
    for (size_t i = 0; i < a.size(); ++i) result = std::max(result, std::abs(a[i].w - b[i].w));
    return result;
}

static float luminanceDeviation(const std::vector<simd_float4>& image) {
    double mean = 0;
    for (const auto& p : image) mean += (p.x+p.y+p.z)/3.0;
    mean /= image.size();
    double deviation = 0;
    for (const auto& p : image) deviation += std::abs((p.x+p.y+p.z)/3.0-mean);
    return float(deviation/image.size());
}

static float logEncode(float x, float base, float a, float b, float c, float d, float cut, float e = 0.0f) {
    float atCut = c * std::log(a * cut + b) / std::log(base) + d;
    float slope = e > 0.0f ? e : c * a / ((a * cut + b) * std::log(base));
    return x > cut ? c * std::log(a * x + b) / std::log(base) + d : atCut + slope * (x - cut);
}

static float logDecode(float y, float base, float a, float b, float c, float d, float cut, float e = 0.0f) {
    float atCut = c * std::log(a * cut + b) / std::log(base) + d;
    float slope = e > 0.0f ? e : c * a / ((a * cut + b) * std::log(base));
    return y > atCut ? (std::pow(base, (y - d) / c) - b) / a : cut + (y - atCut) / slope;
}

static float encodeWorking(float v, uint32_t space) {
    switch (space) {
        case LDBWorkingColorSpaceACEScct:
            return v > 0.0078125f ? (std::log2(v) + 9.72f) / 17.52f : 10.5402377416545f * v + 0.0729055341958355f;
        case LDBWorkingColorSpaceDaVinciIntermediate:
            return logEncode(v, 2, 1, .0075f, .07329248f, .51304736f, .00262409f, 10.44426855f);
        case LDBWorkingColorSpaceARRILogC3EI800:
            return logEncode(v, 10, 5.55555555555556f, .0522722750251688f, .247189638318671f, .385536998692443f, .0105909904954696f);
        case LDBWorkingColorSpaceARRILogC4:
            return logEncode(v, 2, 2231.82630906769f, 64, .0647954196341293f, -.295908392682586f, -.0180569961199113f);
        default: return v;
    }
}

static float decodeWorking(float v, uint32_t space) {
    switch (space) {
        case LDBWorkingColorSpaceACEScct:
            return v > .155251141552511f ? std::exp2(v * 17.52f - 9.72f) : (v - .0729055341958355f) / 10.5402377416545f;
        case LDBWorkingColorSpaceDaVinciIntermediate:
            return logDecode(v, 2, 1, .0075f, .07329248f, .51304736f, .00262409f, 10.44426855f);
        case LDBWorkingColorSpaceARRILogC3EI800:
            return logDecode(v, 10, 5.55555555555556f, .0522722750251688f, .247189638318671f, .385536998692443f, .0105909904954696f);
        case LDBWorkingColorSpaceARRILogC4:
            return logDecode(v, 2, 2231.82630906769f, 64, .0647954196341293f, -.295908392682586f, -.0180569961199113f);
        default: return v;
    }
}

int main(int argc, char** argv) {
    if (argc == 3) {
        std::freopen(argv[2], "w", stdout);
        std::freopen(argv[2], "a", stderr);
    }
    @autoreleasepool {
        require(argc == 2 || argc == 3, "usage: ldb-optics-tests LDBOptics.metallib [result-log]");
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        require(device != nil, "No Metal device found");
        id<MTLCommandQueue> queue = [device newCommandQueue];
        NSURL* libraryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        LDBOpticsEngine engine(device, libraryURL);
        require(engine.valid(), engine.errorMessage());

        constexpr uint32_t width = 64, height = 48;
        std::vector<simd_float4> image(width * height);
        for (uint32_t y = 0; y < height; ++y) {
            for (uint32_t x = 0; x < width; ++x) {
                float fx = float(x) / float(width - 1);
                float fy = float(y) / float(height - 1);
                image[y * width + x] = {fx, fy, 0.25f + 2.0f * ((x == width / 2 && y == height / 2) ? 1.0f : 0.0f), 1.0f};
            }
        }

        auto neutral = LDBNeutralOpticsParameters(width, height);
        auto neutralOut = render(engine, device, queue, image, width, height, neutral);
        require(maxDifference(image, neutralOut) < 1e-5f, "Neutral state must be identity");

        auto zeroBlend = neutral;
        zeroBlend.distortionK1 = -0.2f;
        zeroBlend.vignetteOptical = 1.0f;
        zeroBlend.effectBlend = 0.0f;
        auto zeroBlendOut = render(engine, device, queue, image, width, height, zeroBlend);
        require(maxDifference(image, zeroBlendOut) < 1e-5f, "Zero blend must be identity");

        auto vignette = neutral;
        vignette.vignetteNatural = 0.8f;
        auto vignetteOut = render(engine, device, queue, image, width, height, vignette);
        float center = vignetteOut[(height / 2) * width + width / 2].x;
        float corner = vignetteOut[0].x;
        require(center > corner, "Vignette must attenuate corners more than center");

        auto distortion = neutral;
        distortion.distortionK1 = -0.18f;
        auto distortionOut = render(engine, device, queue, image, width, height, distortion);
        require(maxDifference(image, distortionOut) > 0.01f, "Distortion must alter a spatial gradient");
        auto secondaryDistortion=neutral; secondaryDistortion.distortionK2=.5f;
        auto moustacheDistortion=neutral; moustacheDistortion.moustacheK3=.35f;
        require(maxDifference(image,render(engine,device,queue,image,width,height,secondaryDistortion))>.001f,
                "Secondary distortion must respond within its UI range");
        require(maxDifference(image,render(engine,device,queue,image,width,height,moustacheDistortion))>.001f,
                "Moustache distortion must respond within its UI range");
        auto anamorphicField=distortion; anamorphicField.anamorphicSqueeze=1.8f;
        require(maxDifference(distortionOut,render(engine,device,queue,image,width,height,anamorphicField))>.001f,
                "Anamorphic field must shape its documented parent distortion");
        auto anamorphicExtreme=distortion; anamorphicExtreme.anamorphicSqueeze=4.0f;
        require(maxDifference(render(engine,device,queue,image,width,height,anamorphicField),
                              render(engine,device,queue,image,width,height,anamorphicExtreme))>.001f,
                "Expanded Anamorphic Field range must continue shaping off-axis effects");
        auto shiftedCenter=distortion; shiftedCenter.opticalCenter={.35f,.6f};
        require(maxDifference(distortionOut,render(engine,device,queue,image,width,height,shiftedCenter))>.001f,
                "Optical Center must reposition field effects");

        auto chromatic = neutral;
        chromatic.lateralCARed = 0.8f;
        chromatic.lateralCABlue = -0.8f;
        auto chromaticOut = render(engine, device, queue, image, width, height, chromatic);
        require(maxDifference(image, chromaticOut) > 0.001f, "Chromatic aberration must alter channels");
        auto redOnly=neutral; redOnly.lateralCARed=1;
        auto blueOnly=neutral; blueOnly.lateralCABlue=-1;
        require(maxDifference(image,render(engine,device,queue,image,width,height,redOnly))>.0001f,
                "Red fringing must respond independently");
        require(maxDifference(image,render(engine,device,queue,image,width,height,blueOnly))>.0001f,
                "Blue fringing must respond independently");
        auto longitudinal = neutral;
        longitudinal.longitudinalCA = 1.0f;
        longitudinal.longitudinalCARadius = 4.0f;
        auto longitudinalOut = render(engine,device,queue,image,width,height,longitudinal);
        require(maxDifference(image,longitudinalOut)>.0001f,
                "Longitudinal CA must create near/far focus chroma");
        auto longitudinalRadius = longitudinal; longitudinalRadius.longitudinalCARadius = 10.0f;
        require(maxDifference(longitudinalOut,render(engine,device,queue,image,width,height,longitudinalRadius))>.0001f,
                "Longitudinal CA radius must select a distinct focus-transition scale");
        auto longitudinalColors = longitudinal;
        longitudinalColors.nearFocusColor={.4f,1.0f,.5f}; longitudinalColors.farFocusColor={1.0f,.35f,.75f};
        require(maxDifference(longitudinalOut,render(engine,device,queue,image,width,height,longitudinalColors))>.0001f,
                "Longitudinal near/far colors must independently shape chroma");
        auto longitudinalCreative=longitudinal;longitudinalCreative.longitudinalCA=2.0f;
        require(maxDifference(longitudinalOut,
                              render(engine,device,queue,image,width,height,longitudinalCreative))>.0001f,
                "Longitudinal CA creative range must remain visibly progressive");
        auto depthPacked=image;
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x)depthPacked[y*width+x].w=float(x)/float(width-1);
        auto depthDiagnostic=neutral;depthDiagnostic.depthMode=2;depthDiagnostic.depthChannel=4;
        depthDiagnostic.processingFlags=LDBDiagnosticDepth;
        auto depthOut=render(engine,device,queue,depthPacked,width,height,depthDiagnostic);
        require(depthOut.front().x<.01f&&depthOut[width-1].x>.99f,
                "Depth diagnostic must display normalized near-black auxiliary input");
        auto inverseDepth=depthDiagnostic;inverseDepth.depthMode=1;
        auto inverseOut=render(engine,device,queue,depthPacked,width,height,inverseDepth);
        require(inverseOut.front().x>.99f&&inverseOut[width-1].x<.01f,
                "Depth interpretation must support near-white inversion");
        auto depthLongitudinal=longitudinal;
        depthLongitudinal.depthMode=2;depthLongitudinal.depthChannel=4;
        depthLongitudinal.depthFocus=.5f;
        auto depthLongitudinalOut=render(engine,device,queue,depthPacked,width,height,depthLongitudinal);
        require(maxDifference(longitudinalOut,depthLongitudinalOut)>.0001f,
                "External depth must drive near/far longitudinal CA");
        auto shiftedDepthFocus=depthLongitudinal;shiftedDepthFocus.depthFocus=.15f;
        require(maxDifference(depthLongitudinalOut,
                              render(engine,device,queue,depthPacked,width,height,shiftedDepthFocus))>.0001f,
                "Focus Depth must move the longitudinal CA focus plane");
        auto invertedDepthLongitudinal=depthLongitudinal;invertedDepthLongitudinal.depthMode=1;
        require(maxDifference(depthLongitudinalOut,
                              render(engine,device,queue,depthPacked,width,height,invertedDepthLongitudinal))>.0001f,
                "Near-white and near-black depth must swap longitudinal tint assignment");
        auto ignoredDepthFocus=longitudinal;ignoredDepthFocus.depthFocus=.1f;
        require(maxDifference(longitudinalOut,
                              render(engine,device,queue,image,width,height,ignoredDepthFocus))<1e-7f,
                "Depth-Free optics must ignore Focus Depth");

        auto transmission = neutral;
        transmission.transmissionColor = {1.0f, 0.7f, 0.5f};
        transmission.transmissionColorAmount = 1.0f;
        auto transmissionOut = render(engine, device, queue, image, width, height, transmission);
        size_t sampleIndex = (height / 3) * width + width / 3;
        require(transmissionOut[sampleIndex].y < image[sampleIndex].y, "Transmission color must attenuate selected channels");

        auto opticalVignette=neutral; opticalVignette.vignetteOptical=.8f;
        require(maxDifference(image,render(engine,device,queue,image,width,height,opticalVignette))>.01f,
                "Optical vignette must respond independently");
        auto mechanicalVignette=neutral; mechanicalVignette.vignetteMechanical=1; mechanicalVignette.imageCircleSize=.8f;
        auto mechanicalOut=render(engine,device,queue,image,width,height,mechanicalVignette);
        require(maxDifference(image,mechanicalOut)>.01f,"Mechanical vignette must respond within its UI range");
        auto circleAspect=mechanicalVignette; circleAspect.imageCircleAspect=1.8f;
        auto circleSoftness=mechanicalVignette; circleSoftness.imageCircleSoftness=.5f;
        require(maxDifference(mechanicalOut,render(engine,device,queue,image,width,height,circleAspect))>.001f,
                "Image Circle Aspect must shape Mechanical Vignette");
        require(maxDifference(mechanicalOut,render(engine,device,queue,image,width,height,circleSoftness))>.001f,
                "Image Circle Softness must shape Mechanical Vignette");

        std::vector<simd_float4> impulse(width * height, simd_float4{0, 0, 0, 1});
        impulse[(height / 2) * width + width / 2] = {4, 4, 4, 1};
        auto bloom = neutral;
        bloom.bloomThreshold = 1.0f;
        bloom.bloomEnergy = 0.5f;
        bloom.bloomRadius = 8.0f;
        bloom.bloomHorizontalStretch = 1.0f;
        auto bloomOut = render(engine, device, queue, impulse, width, height, bloom);
        size_t adjacent = (height / 2) * width + width / 2 + 3;
        require(bloomOut[adjacent].x > 0.0f, "Bloom must distribute highlight energy to neighbouring pixels");
        auto bloomRadiusChanged=bloom; bloomRadiusChanged.bloomRadius=20;
        auto bloomStretchChanged=bloom; bloomStretchChanged.bloomHorizontalStretch=3;
        auto bloomThresholdChanged=bloom; bloomThresholdChanged.bloomThreshold=3.5f;
        require(maxDifference(bloomOut,render(engine,device,queue,impulse,width,height,bloomRadiusChanged))>.0001f,
                "Bloom Radius must shape active bloom");
        require(maxDifference(bloomOut,render(engine,device,queue,impulse,width,height,bloomStretchChanged))>.0001f,
                "Bloom Stretch must shape active bloom");
        require(maxDifference(bloomOut,render(engine,device,queue,impulse,width,height,bloomThresholdChanged))>.0001f,
                "Bloom Threshold must shape active bloom");
        auto fastBloom=bloomRadiusChanged;fastBloom.processingFlags=LDBProcessingQualityFast;
        auto highBloom=bloomRadiusChanged;highBloom.processingFlags=LDBProcessingQualityHigh;
        require(maxDifference(render(engine,device,queue,impulse,width,height,fastBloom),
                              render(engine,device,queue,impulse,width,height,highBloom))>.00001f,
                "Quality choices must select distinct scatter approximations");
        auto diagnosticBloom=bloom;diagnosticBloom.processingFlags=LDBDiagnosticScatter;
        require(maxDifference(bloomOut,render(engine,device,queue,impulse,width,height,diagnosticBloom))>.001f,
                "Diagnostic View must change the displayed analysis image");

        auto swirl = neutral;
        swirl.swirl = 0.8f;
        auto swirlOut = render(engine, device, queue, image, width, height, swirl);
        require(maxDifference(image, swirlOut) > 0.001f, "Swirl must alter off-axis image geometry");

        auto curvature = neutral;
        curvature.fieldCurvature = 1.0f;
        auto curvatureOut = render(engine, device, queue, image, width, height, curvature);
        require(maxDifference(image, curvatureOut) > 0.0001f, "Field curvature must alter off-axis focus");

        std::vector<simd_float4> focusPattern(width*height);
        for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
            float v=((x/2+y/2)&1)?0.85f:0.15f;
            focusPattern[size_t(y)*width+x]={v,v,v,1};
        }
        auto astigmatic=neutral; astigmatic.astigmatism=1.0f;
        auto radialSmeared=neutral; radialSmeared.radialSmear=1.0f;
        auto tangentSmeared=neutral; tangentSmeared.tangentialSmear=1.0f;
        auto astigmaticOut=render(engine,device,queue,focusPattern,width,height,astigmatic);
        auto radialSmearedOut=render(engine,device,queue,focusPattern,width,height,radialSmeared);
        auto tangentSmearedOut=render(engine,device,queue,focusPattern,width,height,tangentSmeared);
        require(maxDifference(focusPattern,astigmaticOut)>.01f,
                "Normalized astigmatism must work without another focus control");
        require(maxDifference(focusPattern,radialSmearedOut)>.01f,
                "Normalized radial smear must work without another focus control");
        require(maxDifference(focusPattern,tangentSmearedOut)>.01f,
                "Normalized tangential smear must work without another focus control");
        require(maxDifference(radialSmearedOut,tangentSmearedOut)>.001f,
                "Radial and tangential smear must have distinct directional responses");
        auto strongAstigmatic=neutral;strongAstigmatic.astigmatism=2.0f;
        require(maxDifference(astigmaticOut,
                              render(engine,device,queue,focusPattern,width,height,strongAstigmatic))>.001f,
                "Expanded focus-character range must remain visually effective beyond 1.0");
        auto cornerLoss=neutral;cornerLoss.cornerSharpnessLoss=1;
        require(maxDifference(focusPattern,render(engine,device,queue,focusPattern,width,height,cornerLoss))>.01f,
                "Corner Detail Loss must respond within its UI range");

        auto circularAperture=neutral;circularAperture.apertureResponse=1;circularAperture.apertureRadius=8;
        auto circularApertureOut=render(engine,device,queue,focusPattern,width,height,circularAperture);
        require(maxDifference(focusPattern,circularApertureOut)>.01f,
                "Aperture Response must work independently");
        auto depthFocusPattern=focusPattern;
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x)
            depthFocusPattern[size_t(y)*width+x].w=float(x)/float(width-1);
        auto depthAperture=circularAperture;
        depthAperture.depthMode=2;depthAperture.depthChannel=4;depthAperture.depthFocus=.5f;
        auto depthApertureOut=render(engine,device,queue,depthFocusPattern,width,height,depthAperture);
        require(maxDifference(circularApertureOut,depthApertureOut)>.001f,
                "External depth must modulate Aperture Response around Focus Depth");
        auto shiftedDepthAperture=depthAperture;shiftedDepthAperture.depthFocus=.2f;
        require(maxDifference(depthApertureOut,
                              render(engine,device,queue,depthFocusPattern,width,height,shiftedDepthAperture))>.001f,
                "Focus Depth must move the aperture focus plane");
        auto polygonAperture=circularAperture;polygonAperture.apertureShape=1;polygonAperture.apertureBladeCurvature=0;
        auto polygonApertureOut=render(engine,device,queue,focusPattern,width,height,polygonAperture);
        require(maxDifference(circularApertureOut,polygonApertureOut)>.001f,
                "Polygon aperture must differ from circular response");
        auto bladeCountAperture=polygonAperture;bladeCountAperture.apertureBladeCount=11;
        require(maxDifference(polygonApertureOut,render(engine,device,queue,focusPattern,width,height,bladeCountAperture))>.001f,
                "Blade Count must shape polygon response");
        auto manyBladeAperture=polygonAperture;manyBladeAperture.apertureBladeCount=24;
        require(maxDifference(polygonApertureOut,render(engine,device,queue,focusPattern,width,height,manyBladeAperture))>.001f,
                "Extended creative Blade Count must remain effective above 16");
        auto curvedAperture=polygonAperture;curvedAperture.apertureBladeCurvature=.8f;
        require(maxDifference(polygonApertureOut,render(engine,device,queue,focusPattern,width,height,curvedAperture))>.001f,
                "Blade Curvature must round polygon response");
        auto rotatedAperture=polygonAperture;rotatedAperture.apertureRotation=37;
        require(maxDifference(polygonApertureOut,render(engine,device,queue,focusPattern,width,height,rotatedAperture))>.001f,
                "Aperture Rotation must rotate shaped response");
        auto ovalAperture=circularAperture;ovalAperture.apertureShape=2;ovalAperture.apertureAspect=2;
        auto ovalApertureOut=render(engine,device,queue,focusPattern,width,height,ovalAperture);
        require(maxDifference(circularApertureOut,ovalApertureOut)>.001f,
                "Oval aperture aspect must shape response");
        auto catEyeAperture=ovalAperture;catEyeAperture.apertureCatEye=1;
        require(maxDifference(ovalApertureOut,render(engine,device,queue,focusPattern,width,height,catEyeAperture))>.001f,
                "Cat-eye response must deform the off-axis pupil");
        auto softAperture=polygonAperture;softAperture.apertureSoftness=1;
        require(maxDifference(polygonApertureOut,render(engine,device,queue,focusPattern,width,height,softAperture))>.001f,
                "Aperture softness must continuously soften shaped response");
        std::vector<simd_float4> aperturePoint(width*height,simd_float4{0,0,0,1});
        aperturePoint[(height/2)*width+width/2]={5,5,5,1};
        auto filledAperture=neutral;filledAperture.apertureResponse=1;filledAperture.apertureRadius=10;
        auto filledApertureOut=render(engine,device,queue,aperturePoint,width,height,filledAperture);
        float ringMinimum=1e9f,ringMaximum=0;
        for(uint32_t angleIndex=0;angleIndex<24;++angleIndex) {
            float angle=float(angleIndex)*2.0f*float(M_PI)/24.0f;
            int x=int(width/2)+int(std::lround(std::cos(angle)*4.0f));
            int y=int(height/2)+int(std::lround(std::sin(angle)*4.0f));
            float sample=filledApertureOut[size_t(y)*width+x].x;
            ringMinimum=std::min(ringMinimum,sample);ringMaximum=std::max(ringMaximum,sample);
        }
        require(ringMinimum>ringMaximum*.12f,
                "Circular aperture footprint must be filled without cross-shaped angular gaps");
        float interiorMinimum=1e9f,interiorMaximum=0,interiorSum=0,interiorSquareSum=0;
        uint32_t interiorCount=0;
        for(int y=-5;y<=5;++y)for(int x=-5;x<=5;++x)if(x*x+y*y<=25) {
            float sample=filledApertureOut[size_t(int(height/2)+y)*width+size_t(int(width/2)+x)].x;
            interiorMinimum=std::min(interiorMinimum,sample);interiorMaximum=std::max(interiorMaximum,sample);
            interiorSum+=sample;interiorSquareSum+=sample*sample;++interiorCount;
        }
        float interiorMean=interiorSum/float(interiorCount);
        float interiorVariance=std::max(interiorSquareSum/float(interiorCount)-interiorMean*interiorMean,0.0f);
        require(interiorMinimum>interiorMaximum*.04f&&std::sqrt(interiorVariance)<interiorMean*.65f,
                "Aperture footprint must reconstruct uniformly without a visible sample rosette");
        float centreSample=filledApertureOut[size_t(height/2)*width+width/2].x;
        float surroundingMean=0;
        for(uint32_t angleIndex=0;angleIndex<16;++angleIndex) {
            float angle=float(angleIndex)*2.0f*float(M_PI)/16.0f;
            int x=int(width/2)+int(std::lround(std::cos(angle)*3.0f));
            int y=int(height/2)+int(std::lround(std::sin(angle)*3.0f));
            surroundingMean+=filledApertureOut[size_t(y)*width+x].x;
        }
        surroundingMean/=16.0f;
        require(centreSample<surroundingMean*1.35f,
                "Full aperture response must not retain a concentrated point-source core");
        auto depthPoint=aperturePoint;
        for(auto& pixel:depthPoint)pixel.w=.5f;
        auto focusedDepthAperture=filledAperture;
        focusedDepthAperture.depthMode=2;focusedDepthAperture.depthChannel=4;
        focusedDepthAperture.depthFocus=.5f;
        require(maxDifference(aperturePoint,
                              render(engine,device,queue,depthPoint,width,height,focusedDepthAperture))<1e-6f,
                "Aperture depth focus plane must preserve the unblurred source");
        for(auto& pixel:depthPoint)pixel.w=.75f;
        auto partialDepthApertureOut=render(engine,device,queue,depthPoint,width,height,focusedDepthAperture);
        float partialCentre=partialDepthApertureOut[size_t(height/2)*width+width/2].x;
        float partialSurround=0;
        for(uint32_t angleIndex=0;angleIndex<16;++angleIndex) {
            float angle=float(angleIndex)*2.0f*float(M_PI)/16.0f;
            int x=int(width/2)+int(std::lround(std::cos(angle)*2.0f));
            int y=int(height/2)+int(std::lround(std::sin(angle)*2.0f));
            partialSurround+=partialDepthApertureOut[size_t(y)*width+x].x;
        }
        partialSurround/=16.0f;
        require(partialCentre<partialSurround*1.5f,
                "Depth-scaled aperture footprint must not retain a sharp point core");

        // A discontinuous map must select either side of a hard depth jump
        // without softening the explicitly focused region itself. This does not
        // claim foreground occlusion reconstruction; the dedicated 79--83
        // visual series evaluates boundary contamination and thin structures.
        std::vector<simd_float4> depthStep(width*height);
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x) {
            bool near=x<width/2;
            float value=((x/3+y/3)&1)?1.0f:.05f;
            depthStep[size_t(y)*width+x]={value,value,value,near?.2f:.8f};
        }
        auto stepAperture=circularAperture;
        stepAperture.depthMode=2;stepAperture.depthChannel=4;stepAperture.depthFocus=.2f;
        auto nearFocusedStep=render(engine,device,queue,depthStep,width,height,stepAperture);
        size_t nearProbe=size_t(height/2)*width+width/4;
        require(simd_length(simd_float3{nearFocusedStep[nearProbe].x-depthStep[nearProbe].x,
                                        nearFocusedStep[nearProbe].y-depthStep[nearProbe].y,
                                        nearFocusedStep[nearProbe].z-depthStep[nearProbe].z})<1e-6f,
                "Hard-depth near focus must preserve the selected source region");
        stepAperture.depthFocus=.8f;
        auto farFocusedStep=render(engine,device,queue,depthStep,width,height,stepAperture);
        size_t farProbe=size_t(height/2)*width+width*3/4;
        require(simd_length(simd_float3{farFocusedStep[farProbe].x-depthStep[farProbe].x,
                                        farFocusedStep[farProbe].y-depthStep[farProbe].y,
                                        farFocusedStep[farProbe].z-depthStep[farProbe].z})<1e-6f,
                "Hard-depth far focus must preserve the selected source region");
        require(maxDifference(nearFocusedStep,farFocusedStep)>.01f,
                "Hard-depth focus selection must move across a discontinuity");
        std::vector<simd_float4> boundaryPoint(width*height,simd_float4{0,0,0,.8f});
        boundaryPoint[size_t(height/2)*width+width/2-1]={5,5,5,.2f};
        stepAperture.depthFocus=.2f;stepAperture.apertureRadius=10;
        auto protectedBoundary=render(engine,device,queue,boundaryPoint,width,height,stepAperture);
        float wrongLayerLeak=0;
        for(uint32_t y=0;y<height;++y)for(uint32_t x=width/2+1;x<width;++x)
            wrongLayerLeak=std::max(wrongLayerLeak,protectedBoundary[size_t(y)*width+x].x);
        require(wrongLayerLeak<.02f,
                "Depth-aware aperture must reject bright samples across a hard layer boundary");

        std::vector<simd_float4> alignmentPoint(width*height,simd_float4{0,0,0,1});
        alignmentPoint[(height/2)*width+width*3/4]={5,5,5,1};
        auto warpedPoint=neutral; warpedPoint.distortionK1=-.28f;
        auto warpedPointOut=render(engine,device,queue,alignmentPoint,width,height,warpedPoint);
        auto warpedBloom=warpedPoint;
        warpedBloom.bloomThreshold=1; warpedBloom.bloomEnergy=.5f; warpedBloom.bloomRadius=5;
        auto warpedBloomOut=render(engine,device,queue,alignmentPoint,width,height,warpedBloom);
        uint32_t peakX=0,peakY=0; float peak=-1;
        double sum=0,sumX=0,sumY=0;
        for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
            size_t i=size_t(y)*width+x;
            if(warpedPointOut[i].x>peak){peak=warpedPointOut[i].x;peakX=x;peakY=y;}
            double energy=std::max(0.0f,warpedBloomOut[i].x-warpedPointOut[i].x);
            sum+=energy;sumX+=energy*x;sumY+=energy*y;
        }
        require(sum>0,"Distorted bloom alignment test must produce scattered energy");
        float centroidDistance=std::hypot(float(sumX/sum)-peakX,float(sumY/sum)-peakY);
        require(centroidDistance<2.5f,
                "Bloom/glare/halo scatter must remain aligned with distorted image geometry");

        std::vector<simd_float4> offAxisPoint(width*height,simd_float4{0,0,0,1});
        uint32_t pointX=width*3/4, pointY=height/2;
        offAxisPoint[pointY*width+pointX]={5,5,5,1};
        auto comaShape=neutral; comaShape.coma=1;
        auto comaShapeOut=render(engine,device,queue,offAxisPoint,width,height,comaShape);
        float comaOutward=comaShapeOut[pointY*width+pointX+6].x;
        float comaInward=comaShapeOut[pointY*width+pointX-6].x;
        require(comaOutward>comaInward+1e-4f,
                "Coma must form an asymmetric tail away from the optical center");
        for(uint32_t offset=1;offset<=8;++offset)
            require(comaShapeOut[pointY*width+pointX+offset].x>1e-6f,
                    "Coma tail must remain continuous without sampled ghost gaps");
        auto strongComa=comaShape;strongComa.coma=2;
        require(maxDifference(comaShapeOut,
                              render(engine,device,queue,offAxisPoint,width,height,strongComa))>.001f,
                "Expanded Coma range must produce additional optical character");
        auto highComaThreshold=comaShape;highComaThreshold.comaThreshold=4.0f;
        require(maxDifference(comaShapeOut,
                              render(engine,device,queue,offAxisPoint,width,height,highComaThreshold))>.001f,
                "Coma Threshold must control highlight eligibility");

        auto haloShape=neutral; haloShape.sphericalHalo=1;
        auto haloShapeOut=render(engine,device,queue,offAxisPoint,width,height,haloShape);
        float haloInner=haloShapeOut[pointY*width+pointX+4].x;
        float haloMiddle=haloShapeOut[pointY*width+pointX+8].x;
        float haloOuter=haloShapeOut[pointY*width+pointX+12].x;
        require(haloInner>haloMiddle && haloMiddle>haloOuter && haloOuter>1e-5f,
                "Spherical aberration must form a smooth decaying spatial halo");
        require(maxDifference(comaShapeOut,haloShapeOut)>.001f,
                "Coma and spherical halo must have independent spatial shapes");

        auto glareAudit=neutral;glareAudit.glareEnergy=.6f;glareAudit.glareRadius=8;glareAudit.bloomThreshold=1;
        auto glareAuditOut=render(engine,device,queue,offAxisPoint,width,height,glareAudit);
        auto glareRadiusAudit=glareAudit;glareRadiusAudit.glareRadius=24;
        auto glareTintAudit=glareAudit;glareTintAudit.glareColor={1,.3f,.2f};glareTintAudit.glareColorAmount=1;
        require(maxDifference(glareAuditOut,render(engine,device,queue,offAxisPoint,width,height,glareRadiusAudit))>.0001f,
                "Glare Radius must shape active glare");
        require(maxDifference(glareAuditOut,render(engine,device,queue,offAxisPoint,width,height,glareTintAudit))>.0001f,
                "Glare Color must tint active glare");

        std::vector<simd_float4> detailPattern(width*height);
        for (uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
            float fine = ((x+y)&1) ? .65f : .35f;
            float broad = ((x/8)&1) ? .12f : -.12f;
            detailPattern[y*width+x] = {fine+broad, fine+broad, fine+broad, .37f};
        }
        auto fineBoost = neutral;
        fineBoost.fineDetail=.7f;
        auto fineBoostOut = render(engine,device,queue,detailPattern,width,height,fineBoost);
        auto fineLoss = neutral;
        fineLoss.fineDetail=-.7f;
        auto fineLossOut = render(engine,device,queue,detailPattern,width,height,fineLoss);
        require(luminanceDeviation(fineBoostOut)>luminanceDeviation(detailPattern),
                "Fine detail boost must increase high-frequency contrast");
        require(luminanceDeviation(fineLossOut)<luminanceDeviation(detailPattern),
                "Fine detail loss must reduce high-frequency contrast");

        auto micro = neutral;
        micro.microContrast=.6f;
        auto microOut = render(engine,device,queue,detailPattern,width,height,micro);
        require(maxDifference(detailPattern,microOut)>.005f,
                "Microcontrast must alter medium-frequency transfer");
        require(maxDifference(microOut,fineBoostOut)>.005f,
                "Microcontrast and fine detail must be independent");

        auto edgeDetail = neutral;
        edgeDetail.detailEdgeFalloff=.8f;
        auto edgeDetailOut = render(engine,device,queue,detailPattern,width,height,edgeDetail);
        size_t centerDetail=(height/2)*width+width/2;
        size_t cornerDetail=2*width+2;
        require(std::abs(edgeDetailOut[cornerDetail].x-detailPattern[cornerDetail].x)
                > std::abs(edgeDetailOut[centerDetail].x-detailPattern[centerDetail].x)+.001f,
                "Detail falloff must be stronger off axis");

        auto sagittal = neutral; sagittal.sagittalDetail=.8f;
        auto tangential = neutral; tangential.tangentialDetail=.8f;
        auto sagittalOut=render(engine,device,queue,detailPattern,width,height,sagittal);
        auto tangentialOut=render(engine,device,queue,detailPattern,width,height,tangential);
        require(maxDifference(sagittalOut,tangentialOut)>.005f,
                "Sagittal and tangential transfer must be independently directional");

        auto scaleWide=micro; scaleWide.detailScale=4;
        auto scaleWideOut=render(engine,device,queue,detailPattern,width,height,scaleWide);
        require(maxDifference(microOut,scaleWideOut)>.001f,
                "Detail scale must select a different spatial-frequency response");
        require(maxAlphaDifference(detailPattern,scaleWideOut)<1e-6f,
                "Detail transfer must preserve alpha");

        std::vector<simd_float4> stepEdge(width*height);
        for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
            float v=x<width/2 ? .2f : .8f; stepEdge[y*width+x]={v,v,v,1};
        }
        auto haloLimit=neutral;
        haloLimit.microContrast=1; haloLimit.fineDetail=1; haloLimit.detailScale=2;
        auto haloLimitOut=render(engine,device,queue,stepEdge,width,height,haloLimit);
        for(const auto& p:haloLimitOut)
            require(p.x>=.15f && p.x<=.85f && p.y>=.15f && p.y<=.85f && p.z>=.15f && p.z<=.85f,
                    "Detail transfer must suppress bright and dark edge halos");

        auto compactBloom = neutral;
        compactBloom.bloomThreshold = 1.0f;
        compactBloom.bloomEnergy = 0.5f;
        compactBloom.bloomRadius = 2.0f;
        compactBloom.glareRadius = 18.0f;
        auto compactBloomOut = render(engine, device, queue, impulse, width, height, compactBloom);
        auto broadGlare = neutral;
        broadGlare.bloomThreshold = 1.0f;
        broadGlare.glareEnergy = 0.5f;
        broadGlare.glareRadius = 18.0f;
        broadGlare.bloomRadius = 2.0f;
        auto broadGlareOut = render(engine, device, queue, impulse, width, height, broadGlare);
        size_t farSample = (height / 2) * width + width / 2 + 14;
        require(broadGlareOut[farSample].x > compactBloomOut[farSample].x + 1e-6f,
                "Glare radius must be independent from bloom radius and energy");

        require(maxAlphaDifference(image, vignetteOut) < 1e-6f, "Optical processing must preserve alpha");

        const uint32_t spaces[] = {LDBWorkingColorSpaceACEScg, LDBWorkingColorSpaceACEScct,
            LDBWorkingColorSpaceDaVinciIntermediate, LDBWorkingColorSpaceARRILogC3EI800,
            LDBWorkingColorSpaceARRILogC4};
        for (uint32_t space : spaces) {
            std::vector<simd_float4> encoded(width * height);
            for (size_t i = 0; i < encoded.size(); ++i) {
                float linear = -0.01f + 4.01f * float(i) / float(encoded.size() - 1);
                simd_float3 ap1 = {linear, linear * .61f + .03f, linear * .27f - .01f};
                simd_float3 value = LDBColorReference::encode(ap1, space);
                encoded[i] = {value.x, value.y, value.z, .2f + .8f * float(i % width) / float(width - 1)};
            }
            auto roundTrip = neutral;
            roundTrip.workingColorSpace = space;
            auto roundTripOut = render(engine, device, queue, encoded, width, height, roundTrip);
            require(maxDifference(encoded, roundTripOut) < 2e-4f, "Working-space neutral round trip must preserve extended-range pixels");

            auto exactBypass = roundTrip;
            exactBypass.effectBlend = 0.0f;
            exactBypass.vignetteNatural = 1.0f;
            auto exactBypassOut = render(engine, device, queue, encoded, width, height, exactBypass);
            require(maxDifference(encoded, exactBypassOut) == 0.0f, "Zero blend must be bit-exact in every working space");

            auto grayTransmission = roundTrip;
            grayTransmission.transmissionColor = {.8f, .8f, .8f};
            grayTransmission.transmissionColorAmount = 1.0f;
            auto transmitted = render(engine, device, queue, encoded, width, height, grayTransmission);
            size_t mid = encoded.size() / 2;
            simd_float3 sourceAP1 = LDBColorReference::decode({encoded[mid].x, encoded[mid].y, encoded[mid].z}, space);
            simd_float3 resultAP1 = LDBColorReference::decode({transmitted[mid].x, transmitted[mid].y, transmitted[mid].z}, space);
            simd_float3 expected = sourceAP1 * .8f;
            require(simd_reduce_max(simd_abs(resultAP1 - expected)) < 4e-4f,
                    "Optical response must be equivalent after decoding each working space");
        }

        std::printf("PASS: neutral identity\n");
        std::printf("PASS: zero blend identity\n");
        std::printf("PASS: vignette field response\n");
        std::printf("PASS: geometric distortion\n");
        std::printf("PASS: lateral chromatic aberration\n");
        std::printf("PASS: longitudinal near/far chromatic aberration\n");
        std::printf("PASS: optional depth input interpretation and diagnostic\n");
        std::printf("PASS: transmission color\n");
        std::printf("PASS: multi-pass bloom distribution\n");
        std::printf("PASS: field swirl\n");
        std::printf("PASS: field curvature response\n");
        std::printf("PASS: normalized independent astigmatism and smear\n");
        std::printf("PASS: continuous aperture and pupil response\n");
        std::printf("PASS: independent aperture shape controls\n");
        std::printf("PASS: filled aperture footprint without directional spokes\n");
        std::printf("PASS: uniform aperture reconstruction without retained point-source core\n");
        std::printf("PASS: expanded creative focus and coma ranges\n");
        std::printf("PASS: anamorphic full-field shaping\n");
        std::printf("PASS: all UI control ranges and documented dependencies\n");
        std::printf("PASS: distortion-aligned optical scatter\n");
        std::printf("PASS: asymmetric off-axis coma tail\n");
        std::printf("PASS: continuous coma tail without ghost gaps\n");
        std::printf("PASS: smooth spatial spherical-aberration halo\n");
        std::printf("PASS: independent coma and spherical shapes\n");
        std::printf("PASS: fine-detail boost and loss\n");
        std::printf("PASS: independent microcontrast transfer\n");
        std::printf("PASS: field-dependent detail falloff\n");
        std::printf("PASS: sagittal and tangential detail transfer\n");
        std::printf("PASS: selectable detail scale\n");
        std::printf("PASS: detail-transfer halo suppression\n");
        std::printf("PASS: independent bloom and glare fields\n");
        std::printf("PASS: alpha preservation\n");
        std::printf("PASS: five-space extended-range round trips\n");
        std::printf("PASS: five-space bit-exact zero blend\n");
        std::printf("PASS: cross-space linear optical equivalence\n");
        std::printf("Metal device: %s\n", device.name.UTF8String);
    }
    return 0;
}
