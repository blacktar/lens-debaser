#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
#include "LDBProjectionCandidateParameters.h"
#endif
#define main LDBVisualValidationMainNotUsedByGuideExamples
#include "VisualValidation.mm"
#undef main

#include <filesystem>
#include <sstream>
#include <unordered_map>

namespace fs = std::filesystem;

static std::vector<simd_float4> loadRec709Gamma24Chart(
    const char* path, uint32_t width, uint32_t height) {
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(nullptr,
        reinterpret_cast<const UInt8*>(path),std::strlen(path),false);
    CGImageSourceRef source=url?CGImageSourceCreateWithURL(url,nullptr):nullptr;
    CGImageRef image=source?CGImageSourceCreateImageAtIndex(source,0,nullptr):nullptr;
    CGColorSpaceRef colorSpace=CGColorSpaceCreateDeviceRGB();
    if(!image) {
        if(colorSpace)CGColorSpaceRelease(colorSpace);if(source)CFRelease(source);if(url)CFRelease(url);
        return {};
    }
    std::vector<uint8_t> rgba(size_t(width)*height*4,255);
    CGContextRef context=CGBitmapContextCreate(rgba.data(),width,height,8,width*4,colorSpace,
        CGBitmapInfo(kCGImageAlphaPremultipliedLast)|CGBitmapInfo(kCGBitmapByteOrder32Big));
    float sw=float(CGImageGetWidth(image)),sh=float(CGImageGetHeight(image));
    float scale=std::max(float(width)/sw,float(height)/sh);
    CGRect viewport=CGRectMake((width-sw*scale)*.5f,(height-sh*scale)*.5f,sw*scale,sh*scale);
    CGContextSetInterpolationQuality(context,kCGInterpolationHigh);
    CGContextDrawImage(context,viewport,image);
    CGContextRelease(context);CGImageRelease(image);CGColorSpaceRelease(colorSpace);CFRelease(source);CFRelease(url);
    const LDBColorReference::Matrix3 rec709ToAP1={{{.6131324224f,.3395380158f,.0474166960f},
        {.0701243808f,.9163940113f,.0134515240f},{.0205876575f,.1095745716f,.8697854040f}}};
    std::vector<simd_float4> result(size_t(width)*height);
    for(size_t i=0;i<result.size();++i) {
        simd_float3 encoded={rgba[i*4]/255.0f,rgba[i*4+1]/255.0f,rgba[i*4+2]/255.0f};
        // Invert Gamma 2.4 and the Rec.709 1.2 OOTF. Combined, the chart's
        // encoded signal maps to scene-linear Rec.709 with an exponent of 2.
        simd_float3 linear={encoded.x*encoded.x,encoded.y*encoded.y,encoded.z*encoded.z};
        simd_float3 ap1=LDBColorReference::apply(rec709ToAP1,linear);
        result[i]={ap1.x,ap1.y,ap1.z,1};
    }
    return result;
}

static std::vector<simd_float4> resizePixels(const std::vector<simd_float4>& source,
                                             uint32_t sw, uint32_t sh,
                                             uint32_t dw, uint32_t dh) {
    std::vector<simd_float4> result(size_t(dw) * dh);
    for (uint32_t y=0; y<dh; ++y) for (uint32_t x=0; x<dw; ++x) {
        float sx=(float(x)+.5f)*sw/dw-.5f, sy=(float(y)+.5f)*sh/dh-.5f;
        uint32_t x0=uint32_t(std::clamp(int(std::floor(sx)),0,int(sw)-1));
        uint32_t y0=uint32_t(std::clamp(int(std::floor(sy)),0,int(sh)-1));
        uint32_t x1=std::min(x0+1,sw-1), y1=std::min(y0+1,sh-1);
        float fx=sx-std::floor(sx), fy=sy-std::floor(sy);
        auto a=source[size_t(y0)*sw+x0]*(1-fx)+source[size_t(y0)*sw+x1]*fx;
        auto b=source[size_t(y1)*sw+x0]*(1-fx)+source[size_t(y1)*sw+x1]*fx;
        result[size_t(y)*dw+x]=a*(1-fy)+b*fy;
    }
    return result;
}

static bool writePNG(const std::string& path, const std::vector<simd_float4>& pixels,
                     uint32_t width, uint32_t height) {
    std::vector<uint8_t> rgba(pixels.size()*4);
    for (size_t i=0;i<pixels.size();++i) {
        auto p=simd_clamp(pixels[i],simd_float4{0,0,0,0},simd_float4{1,1,1,1});
        rgba[i*4]=uint8_t(std::lround(p.x*255)); rgba[i*4+1]=uint8_t(std::lround(p.y*255));
        rgba[i*4+2]=uint8_t(std::lround(p.z*255)); rgba[i*4+3]=255;
    }
    CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider=CGDataProviderCreateWithData(nullptr,rgba.data(),rgba.size(),nullptr);
    CGBitmapInfo bitmapInfo=CGBitmapInfo(uint32_t(kCGImageAlphaLast)|uint32_t(kCGBitmapByteOrderDefault));
    CGImageRef image=CGImageCreate(width,height,8,32,width*4,cs,
        bitmapInfo,provider,nullptr,false,kCGRenderingIntentDefault);
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(nullptr,
        reinterpret_cast<const UInt8*>(path.c_str()),path.size(),false);
    CGImageDestinationRef destination=CGImageDestinationCreateWithURL(url,CFSTR("public.png"),1,nullptr);
    if(destination&&image) CGImageDestinationAddImage(destination,image,nullptr);
    bool ok=destination&&CGImageDestinationFinalize(destination);
    if(destination) CFRelease(destination); if(url) CFRelease(url); if(image) CGImageRelease(image);
    if(provider) CGDataProviderRelease(provider); if(cs) CGColorSpaceRelease(cs);
    return ok;
}

static std::vector<simd_float4> guideRec709Gamma24FromAP1(
    const std::vector<simd_float4>& ap1) {
    const LDBColorReference::Matrix3 ap1ToRec709 = {{{
        1.705050993f,-.621792121f,-.083258872f},
        {-.130256418f,1.140804736f,-.010548318f},
        {-.024003356f,-.128968977f,1.152972333f}}};
    std::vector<simd_float4> result=ap1;
    for(auto& p:result) {
        simd_float3 rgb=LDBColorReference::apply(ap1ToRec709,{p.x,p.y,p.z});
        // Direct Rec.709 scene-to-display conversion: 1.2 OOTF followed by
        // Gamma 2.4 encoding. This is sqrt(scene-linear) and deliberately has
        // no added shoulder, veil or gamut desaturation.
        rgb=simd_clamp(rgb,simd_float3{0,0,0},simd_float3{1,1,1});
        p={std::sqrt(rgb.x),std::sqrt(rgb.y),std::sqrt(rgb.z),p.w};
    }
    return result;
}

static std::vector<simd_float4> guideMilanoDisplayFromAP1(
    const std::vector<simd_float4>& ap1, const CubeLUT& lut) {
    // Lens Debaser works in linear AP1. Re-encode that result to the LUT's
    // expected DWG/Intermediate input, then use Resolve's baked CST output
    // directly as the Rec.709 Gamma 2.4 guide image.
    auto dwgIntermediate=convertEncoding(ap1,LDBWorkingColorSpaceDaVinciIntermediate,true);
    return applyDisplayLUT(dwgIntermediate,lut);
}

static void assignValue(LDBOpticsParameters& p,const std::string& key,float v) {
#define SET(name) if(key==#name){p.name=v;return;}
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
 if(key=="finalCropAdjustment"){p.finalFramingZoom=100.0f+float(v);return;}
 SET(finalFramingMode) SET(finalFramingZoom) SET(finalFramingX) SET(finalFramingY) SET(finalFramingMargin)
#endif
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
    if(key=="effectSize") { if(v==1)p.processingFlags|=(1u<<30);else p.processingFlags&=~(1u<<30);return; }
#endif
    SET(distortionK1) SET(distortionK2) SET(moustacheK3) SET(geometryFieldAmount)
    SET(peripheralStretch) SET(peripheralWarp) SET(anamorphicSqueeze) SET(lateralCARed)
    SET(lateralCABlue) SET(chromaticFieldOnset) SET(chromaticFieldFalloff) SET(longitudinalCA)
    SET(longitudinalCARadius) SET(vignetteNatural) SET(vignetteOptical) SET(vignetteMechanical)
    SET(imageCircleSize) SET(imageCircleAspect) SET(imageCircleSoftness) SET(cornerSharpnessLoss)
    SET(astigmatism) SET(coma) SET(comaThreshold) SET(sphericalHalo) SET(fieldCurvature) SET(swirl)
    SET(radialSmear) SET(tangentialSmear) SET(microContrast) SET(fineDetail) SET(detailEdgeFalloff)
    SET(sagittalDetail) SET(tangentialDetail) SET(detailScale) SET(bloomEnergy) SET(bloomThreshold)
    SET(bloomRadius) SET(bloomHorizontalStretch) SET(glareEnergy) SET(glareThreshold) SET(glareRadius) SET(effectBlend)
    SET(transmissionColorAmount) SET(glareColorAmount) SET(apertureResponse) SET(apertureRadius)
    SET(apertureBladeCurvature) SET(apertureRotation) SET(apertureSoftness) SET(apertureCatEye)
    SET(apertureAspect) SET(apertureBokehSwirl) SET(aperturePupilShift) SET(aperturePupilClip)
    SET(apertureRimWeight) SET(opticalDriftAmount) SET(opticalDriftAngle)
    SET(fieldAspect) SET(fieldRotation) SET(transmissionDensity)
    SET(transmissionContrast) SET(transmissionHighlightSoftness) SET(anamorphicDistortion)
    SET(anamorphicAberration) SET(anamorphicFlareAmount) SET(anamorphicFlareRadius)
    SET(anamorphicFlareThreshold) SET(anamorphicFlareCoreAmount) SET(anamorphicFlareAsymmetry)
    SET(anamorphicFlareGhostAmount) SET(anamorphicFlareGhostPosition) SET(anamorphicFlareGhostScale)
    SET(anamorphicFlareGhostCount) SET(anamorphicFlareGhostSpacing) SET(anamorphicFlareGhostScaleDecay)
    SET(anamorphicFlareGhostEnergyDecay) SET(anamorphicFlareBandAmount) SET(anamorphicFlareBandSeparation)
    SET(anamorphicFlareSecondaryAmount) SET(anamorphicFlareSecondaryOffset) SET(anamorphicFlareThickness)
    SET(diffractionRayAmount) SET(diffractionRayLength) SET(variationAmount) SET(variationFieldAsymmetry)
    SET(variationPupilIrregularity) SET(variationChromaticAsymmetry) SET(variationTransmissionUnevenness)
    SET(frontHaze) SET(cleaningMarks) SET(scratchAmount) SET(scratchDirection) SET(damageScale)
    SET(coatingWear) SET(coatingWearScale) SET(internalDirtAmount) SET(internalDirtScale)
    SET(internalDirtSmear) SET(internalDirtScatter) SET(internalDirtSoftness) SET(internalDirtComplexity)
    SET(refractiveIrregularity) SET(refractiveScale) SET(refractiveEdgeBias) SET(refractiveAnisotropy)
    SET(refractiveRotation) SET(refractiveDispersion) SET(responseHighlightKnee) SET(responseFieldOnset)
    SET(prismAmount) SET(prismDirection) SET(prismDispersion) SET(prismEdgeBias) SET(prismSoftness)
    SET(responseFieldFalloff) SET(responseDefocusOnset) SET(responseDefocusFalloff)
    SET(responseScatterEdgeProtection) SET(depthEdgeSoftness) SET(captureFocalLength)
    SET(captureAperture) SET(captureFocusDistance) SET(captureInfluence) SET(lookCharacter)
    SET(lookVintageBias) SET(lookVintageCaricatureBias) SET(lookExoticBias) SET(lookAnamorphicBias)
    SET(lookInfluence) SET(depthNear) SET(depthFar) SET(depthFocus)
#undef SET
    if(key=="opticalCenterX")p.opticalCenter.x=v; else if(key=="opticalCenterY")p.opticalCenter.y=v;
    else if(key=="fieldCenterX")p.fieldCenter.x=v; else if(key=="fieldCenterY")p.fieldCenter.y=v;
    else if(key=="apertureShape")p.apertureShape=uint32_t(v); else if(key=="apertureBladeCount")p.apertureBladeCount=uint32_t(v);
    else if(key=="depthMode")p.depthMode=uint32_t(v); else if(key=="prismDistribution")p.prismDistribution=uint32_t(v); else if(key=="opticalDriftMode")p.opticalDriftMode=uint32_t(v); else if(key=="variationSeed")p.variationSeed=uint32_t(v);
    else if(key=="damageSeed")p.damageSeed=uint32_t(v); else if(key=="refractiveSeed")p.refractiveSeed=uint32_t(v);
    else if(key=="internalDirtSeed")p.internalDirtSeed=uint32_t(v);
    else if(key=="transmissionR")p.transmissionColor.x=v; else if(key=="transmissionG")p.transmissionColor.y=v; else if(key=="transmissionB")p.transmissionColor.z=v;
    else if(key=="glareR")p.glareColor.x=v; else if(key=="glareG")p.glareColor.y=v; else if(key=="glareB")p.glareColor.z=v;
    else if(key=="nearFocusR")p.nearFocusColor.x=v; else if(key=="nearFocusG")p.nearFocusColor.y=v; else if(key=="nearFocusB")p.nearFocusColor.z=v;
    else if(key=="farFocusR")p.farFocusColor.x=v; else if(key=="farFocusG")p.farFocusColor.y=v; else if(key=="farFocusB")p.farFocusColor.z=v;
    else if(key=="anamorphicFlareR")p.anamorphicFlareColor.x=v; else if(key=="anamorphicFlareG")p.anamorphicFlareColor.y=v; else if(key=="anamorphicFlareB")p.anamorphicFlareColor.z=v;
    else if(key=="anamorphicFlareGhostR")p.anamorphicFlareGhostColor.x=v; else if(key=="anamorphicFlareGhostG")p.anamorphicFlareGhostColor.y=v; else if(key=="anamorphicFlareGhostB")p.anamorphicFlareGhostColor.z=v;
    else if(key=="captureGate") { constexpr float gates[][2]={{36,24},{24.89f,18.66f},{23.6f,15.7f},{17.3f,13},{54.12f,25.58f},{12.52f,7.41f},{10.26f,7.49f},{4.8f,3.5f},{5.79f,4.01f},{9.8f,7.3f},{47.88f,24},{55.8f,24},{72,24}}; int i=std::clamp(int(v),0,12);p.captureGateWidth=gates[i][0];p.captureGateHeight=gates[i][1]; }
}

static LDBOpticsParameters loadPreset(const fs::path& path,uint32_t width,uint32_t height) {
    auto p=LDBNeutralOpticsParameters(width,height); std::ifstream in(path); std::string line; bool focusDistanceRead=false; float autoCrop=0,manualCrop=0; bool hasSeparateCrop=false;
#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
    int model=0,framing=1;double amount=0,angle=55;
#endif
    while(std::getline(in,line)){auto at=line.find('=');if(at==std::string::npos||line.empty()||line[0]=='#')continue;
        try{
            auto key=line.substr(0,at);float value=std::stof(line.substr(at+1));
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
            if(key=="finalAutoCropAdjustment"){autoCrop=value;hasSeparateCrop=true;continue;}
            if(key=="finalManualCrop"){manualCrop=value;hasSeparateCrop=true;continue;}
#endif
            if(key=="captureFocusDistance")focusDistanceRead=true;
#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
            if(key=="projectionModel")model=int(value);
            else if(key=="projectionFraming")framing=int(value);
            else if(key=="projectionAmount")amount=value;
            else if(key=="projectionFieldAngle")angle=value;
            else
#endif
            assignValue(p,key,value);
        }catch(...){} }
#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
    LDBSetProjectionCandidate(p,model,amount,angle,framing);
#endif
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
    if(hasSeparateCrop) p.finalFramingZoom=100+(p.finalFramingMode>0?autoCrop:manualCrop);
#endif
    if(focusDistanceRead) p.captureFocusDistance=p.captureFocusDistance>=999.5f?1000.0f:p.captureFocusDistance*.01f;
    return p;
}

static std::vector<simd_float4> withGuideDepth(const std::vector<simd_float4>& source,
                                               uint32_t width,uint32_t height) {
    auto result=source;
    for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
        float u=(float(x)+.5f)/width,v=(float(y)+.5f)/height;
        // Smooth foreground ellipse over a receding background plane. This is
        // deliberately deterministic and identical across the five visible
        // sources, making the Depth controls comparable without claiming that
        // the approved source images contain measured depth.
        float background=.25f+.65f*v;
        float ellipse=std::sqrt(std::pow((u-.5f)/.24f,2)+std::pow((v-.58f)/.34f,2));
        float foreground=.18f;
        float mask=1.0f-std::clamp((ellipse-.82f)/.18f,0.0f,1.0f);
        result[size_t(y)*width+x].w=background*(1-mask)+foreground*mask;
    }
    return result;
}

struct ExampleGroup { const char* slug; int demo; };
struct GuideSource {
    const char* key;
    std::vector<simd_float4>* pixels;
    uint32_t width;
    uint32_t height;
};

static std::string guideFileSlug(std::string value) {
    std::string result;
    bool separator=false;
    for(unsigned char c:value) {
        if(std::isalnum(c)) {
            if(separator&&!result.empty())result.push_back('-');
            result.push_back(char(std::tolower(c)));
            separator=false;
        } else separator=true;
    }
    return result;
}

#ifdef LDB_FACTORY_REVIEW_TOOL
#define main LDBGuideExamplesUnusedMain
#endif
int main(int argc,char** argv) {
    if(argc<4||argc>5){std::fprintf(stderr,"usage: %s metallib repo-root output-dir [changed-glare|changed-presets-166|changed-presets-166b|changed-presets-167|changed-preset-26|optical-model-validation|field-psf-validation|field-psf-library-validation|all-preset-library-validation|light-transport-validation|optical-drift-comparison|optical-drift-preset-validation|optical-drift-demo-validation|projection-model-validation|projection-balanced-validation|projection-balanced-20|projection-balanced-70|projection-angle-limits]\n",argv[0]);return 2;}
    @autoreleasepool {
        const bool changedGlareOnly=argc==5&&std::string(argv[4])=="changed-glare";
        const bool changedPresets166=argc==5&&std::string(argv[4])=="changed-presets-166";
        const bool changedPresets166b=argc==5&&std::string(argv[4])=="changed-presets-166b";
        const bool changedPresets167=argc==5&&std::string(argv[4])=="changed-presets-167";
        const bool changedPreset26=argc==5&&std::string(argv[4])=="changed-preset-26";
        const bool opticalModelValidation=
            argc==5&&std::string(argv[4])=="optical-model-validation";
        const bool fieldPSFValidation=
            argc==5&&std::string(argv[4])=="field-psf-validation";
        const bool fieldPSFLibraryValidation=
            argc==5&&std::string(argv[4])=="field-psf-library-validation";
        const bool allPresetLibraryValidation=
            argc==5&&std::string(argv[4])=="all-preset-library-validation";
        const bool lightTransportValidation=
            argc==5&&std::string(argv[4])=="light-transport-validation";
        const bool opticalDriftComparison=
            argc==5&&std::string(argv[4])=="optical-drift-comparison";
        const bool opticalDriftPresetValidation=
            argc==5&&std::string(argv[4])=="optical-drift-preset-validation";
        const bool opticalDriftDemoValidation=
            argc==5&&std::string(argv[4])=="optical-drift-demo-validation";
        const bool projectionModelValidation=
            argc==5&&std::string(argv[4])=="projection-model-validation";
        const bool projectionBalancedValidation=
            argc==5&&(std::string(argv[4])=="projection-balanced-validation"||
                     std::string(argv[4])=="projection-balanced-20"||
                     std::string(argv[4])=="projection-balanced-70");
        const float projectionStrength=argc==5&&std::string(argv[4])=="projection-balanced-20"?.20f:
            (argc==5&&std::string(argv[4])=="projection-balanced-70"?.70f:.45f);
        id<MTLDevice> device=MTLCreateSystemDefaultDevice(); if(!device){std::fprintf(stderr,"No Metal device\n");return 3;}
        NSURL* libraryURL=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        LDBOpticsEngine engine(device,libraryURL); id<MTLCommandQueue> queue=[device newCommandQueue];
        fs::path root=argv[2], out=argv[3]; fs::create_directories(out);
        CubeLUT milanoDisplayLUT;
        fs::path lutPath=root/"inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube";
        if(!milanoDisplayLUT.load(lutPath.c_str())) {
            std::fprintf(stderr,"Invalid or missing Milano display LUT: %s\n",lutPath.c_str());
            return 4;
        }
        constexpr uint32_t chartW=960,chartH=540;
        constexpr uint32_t milanoW=960,milanoH=455; // Preserve the 4224:2000 capture aspect.
        auto iso=loadRec709Gamma24Chart((root/"inputs/redistributable/ISO_12233-reschart.tif").c_str(),chartW,chartH);
        auto optical=loadRec709Gamma24Chart((root/"inputs/redistributable/LDB-Synthetic-Optical-Chart.png").c_str(),chartW,chartH);
        uint32_t mw=0,mh=0; auto milano1Encoded=loadEncodedTIFF((root/"inputs/redistributable/iphone_milano_dwg_1.tif").c_str(),mw,mh);
        const uint32_t milano1FullW=mw,milano1FullH=mh;
        auto milano1=resizePixels(convertEncoding(milano1Encoded,LDBWorkingColorSpaceDaVinciIntermediate,false),mw,mh,milanoW,milanoH);
#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
        if(argc==5&&std::string(argv[4])=="projection-resolution-comparison") {
            auto full=convertEncoding(milano1Encoded,LDBWorkingColorSpaceDaVinciIntermediate,false);
            auto neutral=LDBNeutralOpticsParameters(milano1FullW,milano1FullH);
            auto projected=loadPreset(root/"presets/experiments/projection-resolve-candidate/01-Projection-Equidistant-Subtle.ldbpreset",milano1FullW,milano1FullH);
            for(int which=0;which<2;++which) {
                auto result=render(engine,device,queue,full,milano1FullW,milano1FullH,which?projected:neutral);
                for(const auto& pixel:result)for(int c=0;c<4;++c)
                    if(!std::isfinite(pixel[c])){std::fprintf(stderr,"Nonfinite resolution test output\n");return 12;}
                auto display=guideMilanoDisplayFromAP1(result,milanoDisplayLUT);
                const char* name=which?"native-projection.png":"native-baseline.png";
                if(!writePNG((out/name).string(),display,milano1FullW,milano1FullH))return 10;
                std::printf("PASS: %s %ux%u finite; native source resolution\n",name,milano1FullW,milano1FullH);
            }
            return 0;
        }
#endif
        auto milano2Encoded=loadEncodedTIFF((root/"inputs/redistributable/iphone_milano2___dwg.tif").c_str(),mw,mh);
        auto milano2=resizePixels(convertEncoding(milano2Encoded,LDBWorkingColorSpaceDaVinciIntermediate,false),mw,mh,milanoW,milanoH);
        auto milano3Encoded=loadEncodedTIFF((root/"inputs/redistributable/iphone_milano3_dwg.tif").c_str(),mw,mh);
        auto milano3=resizePixels(convertEncoding(milano3Encoded,LDBWorkingColorSpaceDaVinciIntermediate,false),mw,mh,milanoW,milanoH);
        const GuideSource sources[]={{"iso",&iso,chartW,chartH},{"optical",&optical,chartW,chartH},
            {"milano1",&milano1,milanoW,milanoH},{"milano2",&milano2,milanoW,milanoH},
            {"milano3",&milano3,milanoW,milanoH}};

#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
        if(argc==5&&std::string(argv[4])=="projection-candidate-examples") {
            std::vector<fs::path> presets;
            for(const auto& entry:fs::directory_iterator(root/"presets/experiments/projection-resolve-candidate"))
                if(entry.path().extension()==".ldbpreset")presets.push_back(entry.path());
            std::sort(presets.begin(),presets.end());
            if(presets.size()!=6){std::fprintf(stderr,"Expected six candidate examples\n");return 12;}
            for(const auto& source:sources) {
                if(std::string(source.key)!="iso"&&std::string(source.key)!="milano1")continue;
                for(const auto& preset:presets) {
                    auto p=loadPreset(preset,source.width,source.height);
                    if(!LDBProjectionCandidateActive(p)){std::fprintf(stderr,"Inactive candidate example\n");return 12;}
                    auto result=render(engine,device,queue,*source.pixels,source.width,source.height,p);
                    for(const auto& pixel:result)for(int c=0;c<4;++c)
                        if(!std::isfinite(pixel[c])){std::fprintf(stderr,"Nonfinite candidate example\n");return 12;}
                    auto display=std::string(source.key)=="milano1"?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):guideRec709Gamma24FromAP1(result);
                    auto name=preset.stem().string()+"-"+source.key+".png";
                    if(!writePNG((out/name).string(),display,source.width,source.height))return 10;
                    std::printf("Wrote candidate example %s\n",name.c_str());
                }
            }
            return 0;
        }
#endif

        if(argc==5&&(std::string(argv[4])=="projection-angle-limits"||std::string(argv[4])=="projection-angle-zero-recheck")) {
            const bool zeroOnly=std::string(argv[4])=="projection-angle-zero-recheck";
            // Audit linear render values before display conversion can hide NaNs.
            FILE* audit=std::fopen((out.parent_path()/"render-audit.csv").c_str(),"w");
            if(!audit){std::fprintf(stderr,"Cannot open render audit\n");return 10;}
            std::fprintf(audit,"image,nonfinite_components,min_rgb,max_rgb,zero_limit_max_error\n");
            size_t invalidTotal=0;
            for(const auto& source:sources) {
                bool milano=std::string(source.key).rfind("milano",0)==0;
                auto neutral=LDBNeutralOpticsParameters(source.width,source.height);
                auto optical=neutral;
                optical.responseFieldOnset=.18f;optical.responseFieldFalloff=1.12f;
                optical.cornerSharpnessLoss=.72f;optical.fieldCurvature=.48f;
                optical.astigmatism=.18f;optical.tangentialSmear=.16f;
                optical.lateralCARed=1.8f;optical.lateralCABlue=-2.2f;
                auto neutralIdentity=neutral;neutralIdentity.distortionK1=1e-12f;
                auto opticalIdentity=optical;opticalIdentity.distortionK1=1e-12f;
                // Match the forced sampling path; neutral can otherwise blit.
                auto neutralReference=render(engine,device,queue,*source.pixels,source.width,source.height,neutralIdentity);
                auto opticalReference=render(engine,device,queue,*source.pixels,source.width,source.height,opticalIdentity);
                for(int angle:{0,1,5,15,35,55,75,82,85,88,89})
                    for(int model:{1,3})for(int framing:{0,1,2})
                        for(int strength:{20,45,100}) {
                            if(zeroOnly&&angle!=0)continue;
                            // Lower strengths only at candidate extremes.
                            if(strength!=100&&angle!=1&&angle!=82&&angle!=89)continue;
                            for(int kind:{0,1}) {
                                auto p=kind?optical:neutral;
                                p.distortionK1=1e-12f;p.reservedV4_3=float(strength)*.01f;
                                p.reservedV4_4=float(model);p.reservedV4_5=float(angle);
                                p.reservedV4_7=framing==0?0.0f:(framing==1?.55f:1.0f);
                                std::string name=std::string(model==1?"equidistant":"stereographic")+
                                    "-a"+std::to_string(angle)+"-f"+std::to_string(framing)+
                                    "-s"+std::to_string(strength)+(kind?"-optical-":"-geometry-")+source.key+".png";
                                auto result=render(engine,device,queue,*source.pixels,source.width,source.height,p);
                                size_t invalid=0;float low=INFINITY,high=-INFINITY;
                                for(const auto& pixel:result)for(int c=0;c<4;++c) {
                                    if(!std::isfinite(pixel[c]))++invalid;
                                    else if(c<3){low=std::min(low,pixel[c]);high=std::max(high,pixel[c]);}
                                }
                                invalidTotal+=invalid;
                                float zeroError=0;
                                if(angle==0) {
                                    const auto& reference=kind?opticalReference:neutralReference;
                                    for(size_t i=0;i<result.size();++i)for(int c=0;c<4;++c)
                                        zeroError=std::max(zeroError,std::abs(result[i][c]-reference[i][c]));
                                    if(zeroError>1e-6f){std::fprintf(stderr,"FAIL: zero-angle identity error %.9g\n",zeroError);++invalidTotal;}
                                }
                                std::fprintf(audit,"%s,%zu,%.9g,%.9g,%.9g\n",name.c_str(),invalid,low,high,zeroError);
                                auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):guideRec709Gamma24FromAP1(result);
                                if(!writePNG((out/name).string(),display,source.width,source.height)){std::fclose(audit);return 10;}
                            }
                        }
                std::printf("Completed angle sweep source %s\n",source.key);
                std::fflush(audit);
            }
            std::fclose(audit);
            if(invalidTotal){std::fprintf(stderr,"FAIL: %zu invalid components or zero-limit checks\n",invalidTotal);return 11;}
            return 0;
        }

        if(projectionModelValidation||projectionBalancedValidation) {
            struct Projection { int id; const char* slug; } projections[]={
                {1,"equidistant"},{2,"equisolid"},{3,"stereographic"},{4,"orthographic"}};
            for(const auto& source:sources) {
                const bool milano=std::string(source.key).rfind("milano",0)==0;
                auto save=[&](const std::string& name,const LDBOpticsParameters& p) {
                    auto result=render(engine,device,queue,*source.pixels,
                                       source.width,source.height,p);
                    auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):
                        guideRec709Gamma24FromAP1(result);
                    if(!writePNG((out/(name+"-"+source.key+".png")).string(),display,
                                 source.width,source.height))std::exit(10);
                };
                auto neutral=LDBNeutralOpticsParameters(source.width,source.height);
                if(!projectionBalancedValidation)save("baseline-geometry",neutral);
                auto opticalRecipe=neutral;
                opticalRecipe.responseFieldOnset=.18f;
                opticalRecipe.responseFieldFalloff=1.12f;
                opticalRecipe.cornerSharpnessLoss=.72f;
                opticalRecipe.fieldCurvature=.48f;
                opticalRecipe.astigmatism=.18f;
                opticalRecipe.tangentialSmear=.16f;
                opticalRecipe.lateralCARed=1.8f;
                opticalRecipe.lateralCABlue=-2.2f;
                if(!projectionBalancedValidation)save("baseline-optical",opticalRecipe);
                for(const auto& projection:projections) {
                    if(projectionBalancedValidation&&projection.id!=1&&projection.id!=3)continue;
                    auto geometry=neutral;
                    geometry.distortionK1=1e-12f;
                    geometry.reservedV4_3=projectionStrength;
                    geometry.reservedV4_4=float(projection.id);
                    geometry.reservedV4_5=55.0f;
                    geometry.reservedV4_7=projectionBalancedValidation?.55f:2.0f;
                    save(std::string(projection.slug)+"-geometry",geometry);
                    auto optics=opticalRecipe;
                    optics.reservedV4_3=geometry.reservedV4_3;
                    optics.reservedV4_4=geometry.reservedV4_4;
                    optics.reservedV4_5=geometry.reservedV4_5;
                    optics.reservedV4_7=geometry.reservedV4_7;
                    save(std::string(projection.slug)+"-optical",optics);
                    std::printf("Wrote projection experiment %s / %s\n",
                                projection.slug,source.key);
                }
                if(!projectionBalancedValidation&&(std::string(source.key)=="iso"||std::string(source.key)=="milano1")) {
                    struct Framing { const char* slug; float amount; } framings[]={
                        {"full-frame",0.0f},{"balanced",.55f},{"center-scale",1.0f},
                        {"boundary-safe",2.0f}};
                    for(const auto& framing:framings) {
                        auto p=neutral;
                        p.distortionK1=1e-12f;
                        p.reservedV4_3=.45f;p.reservedV4_4=1.0f;p.reservedV4_5=55.0f;
                        p.reservedV4_7=framing.amount;
                        save(std::string("framing-")+framing.slug,p);
                    }
                }
            }
            return 0;
        }

        if(opticalDriftComparison) {
            auto milano1Full=convertEncoding(milano1Encoded,
                LDBWorkingColorSpaceDaVinciIntermediate,false);
            auto drift=LDBNeutralOpticsParameters(milano1FullW,milano1FullH);
            drift.responseFieldOnset=.08f;
            drift.responseFieldFalloff=1.10f;
            drift.apertureResponse=1.0f;
            drift.apertureRadius=42.0f;
            drift.apertureSoftness=.24f;
            drift.apertureCatEye=.38f;
            auto saveDrift=[&](const char* name,const LDBOpticsParameters& parameters) {
                auto result=render(engine,device,queue,milano1Full,
                                   milano1FullW,milano1FullH,parameters);
                auto display=guideMilanoDisplayFromAP1(result,milanoDisplayLUT);
                if(!writePNG((out/name).string(),display,
                             milano1FullW,milano1FullH))std::exit(10);
                std::printf("Wrote optical-drift comparison / %s\n",name);
            };
            saveDrift("504-optical-drift-real-neutral.png",drift);
            drift.opticalDriftAmount=.80f;
            drift.opticalDriftMode=LDBOpticalDriftRadial;
            saveDrift("505-optical-drift-real-radial-out.png",drift);
            drift.opticalDriftAmount=-.80f;
            saveDrift("506-optical-drift-real-radial-in.png",drift);
            drift.opticalDriftAmount=.80f;
            drift.opticalDriftMode=LDBOpticalDriftTangential;
            saveDrift("507-optical-drift-real-tangential.png",drift);
            drift.opticalDriftMode=LDBOpticalDriftDirected;
            drift.opticalDriftAngle=32.0f;
            saveDrift("508-optical-drift-real-directed.png",drift);
            return 0;
        }

        if(opticalDriftPresetValidation||opticalDriftDemoValidation) {
            struct Candidate { const char* slug; fs::path path; } candidates[]={
                {"demo-32-optical-drift",root/"presets/demonstrations/32-Demo-Optical-Drift.ldbpreset"},
                {"cinematic-27-decentered-drift-prime",root/"presets/cinematic-lenses/27-Decentered-Drift-Prime.ldbpreset"},
                {"cinematic-28-spectral-radial-drift",root/"presets/cinematic-lenses/28-Spectral-Radial-Drift.ldbpreset"},
            };
            for(const auto& source:sources) {
                const bool milano=std::string(source.key).rfind("milano",0)==0;
                if(!opticalDriftDemoValidation) {
                    auto before=milano?guideMilanoDisplayFromAP1(*source.pixels,milanoDisplayLUT):
                        guideRec709Gamma24FromAP1(*source.pixels);
                    std::string beforeName=std::string("before-")+source.key+".png";
                    if(!writePNG((out/beforeName).string(),before,source.width,source.height))return 10;
                }
                for(const auto& candidate:candidates) {
                    if(opticalDriftDemoValidation&&
                       std::string(candidate.slug)!="demo-32-optical-drift")continue;
                    if(!fs::is_regular_file(candidate.path)) {
                        std::fprintf(stderr,"Missing Optical Drift preset: %s\n",candidate.path.c_str());
                        return 9;
                    }
                    auto p=loadPreset(candidate.path,source.width,source.height);
                    if(std::string(candidate.slug)=="demo-32-optical-drift") {
                        auto noDrift=p;
                        noDrift.opticalDriftAmount=0.0f;
                        auto neutralResult=render(engine,device,queue,*source.pixels,
                                                  source.width,source.height,noDrift);
                        auto neutralDisplay=milano?
                            guideMilanoDisplayFromAP1(neutralResult,milanoDisplayLUT):
                            guideRec709Gamma24FromAP1(neutralResult);
                        std::string neutralName=std::string(candidate.slug)+
                            "-drift-off-"+source.key+".png";
                        if(!writePNG((out/neutralName).string(),neutralDisplay,
                                     source.width,source.height))return 10;
                    }
                    auto result=render(engine,device,queue,*source.pixels,
                                       source.width,source.height,p);
                    auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):
                        guideRec709Gamma24FromAP1(result);
                    std::string name=std::string(candidate.slug)+"-"+source.key+".png";
                    if(!writePNG((out/name).string(),display,source.width,source.height))return 10;
                    std::printf("Wrote Optical Drift preset %s / %s\n",candidate.slug,source.key);
                }
            }
            return 0;
        }

        if(lightTransportValidation) {
            constexpr uint32_t fixtureW=960,fixtureH=540;
            std::vector<simd_float4> fixture(size_t(fixtureW)*fixtureH,
                                             simd_float4{.008f,.008f,.008f,1.0f});
            const simd_float2 positions[]={{.5f,.5f},{.72f,.5f},{.94f,.5f},
                                           {.5f,.18f},{.88f,.18f}};
            const float energies[]={8.0f,6.0f,8.0f,3.0f,12.0f};
            for(uint32_t y=0;y<fixtureH;++y)for(uint32_t x=0;x<fixtureW;++x) {
                simd_float2 uv={(float(x)+.5f)/fixtureW,(float(y)+.5f)/fixtureH};
                float value=.008f;
                for(size_t i=0;i<std::size(positions);++i) {
                    simd_float2 delta=(uv-positions[i])*
                        simd_make_float2(float(fixtureW)/fixtureH,1.0f);
                    float r2=simd_dot(delta,delta);
                    value+=energies[i]*exp(-r2/(2.0f*.0022f*.0022f));
                }
                fixture[size_t(y)*fixtureW+x]={value,value,value,1.0f};
            }
            auto field=[](uint32_t w,uint32_t h) {
                auto p=LDBNeutralOpticsParameters(w,h);
                p.apertureResponse=1.0f;p.apertureRadius=27.0f;
                p.apertureSoftness=.38f;p.astigmatism=.20f;
                p.cornerSharpnessLoss=1.42f;p.fieldAspect=1.58f;
                p.fieldCurvature=.72f;p.tangentialSmear=.28f;
                p.responseFieldOnset=.24f;p.responseFieldFalloff=.82f;
                return p;
            };
            struct AuditCase { const char* name; int kind; } cases[]={
                {"direct-field-only",0},{"aperture-psf-only",1},{"bloom-only",2},
                {"psf-plus-bloom",3},{"psf-plus-glare",4},{"psf-plus-halo",5},
                {"psf-plus-combined-scatter",6}};
            std::ofstream metrics(out/"light-transport-metrics.tsv");
            metrics<<"case\tinput_energy\toutput_energy\tpeak\n";
            constexpr simd_float3 luma={.272229f,.674082f,.053689f};
            double inputEnergy=0.0;
            for(const auto& px:fixture)inputEnergy+=px.x*luma.x+px.y*luma.y+px.z*luma.z;
            for(const auto& audit:cases) {
                auto p=field(fixtureW,fixtureH);
                if(audit.kind==0)p.apertureResponse=0.0f;
                if(audit.kind==2)p=LDBNeutralOpticsParameters(fixtureW,fixtureH);
                if(audit.kind==2||audit.kind==3||audit.kind==6) {
                    p.bloomEnergy=.55f;p.bloomThreshold=.45f;p.bloomRadius=42.0f;
                }
                if(audit.kind==4||audit.kind==6) {
                    p.glareEnergy=.45f;p.glareThreshold=.45f;p.glareRadius=72.0f;
                }
                if(audit.kind==5||audit.kind==6)p.sphericalHalo=.72f;
                auto result=render(engine,device,queue,fixture,fixtureW,fixtureH,p);
                double outputEnergy=0.0,peak=0.0;
                for(const auto& px:result) {
                    double y=px.x*luma.x+px.y*luma.y+px.z*luma.z;
                    outputEnergy+=y;peak=std::max(peak,y);
                }
                metrics<<audit.name<<'\t'<<inputEnergy<<'\t'<<outputEnergy<<'\t'<<peak<<'\n';
                auto display=guideRec709Gamma24FromAP1(result);
                std::string name=std::string("audit-")+audit.name+".png";
                if(!writePNG((out/name).string(),display,fixtureW,fixtureH))return 10;
                std::printf("Wrote light-transport audit / %s\n",audit.name);
            }
            return 0;
        }

        if(fieldPSFValidation) {
            fs::path presetPath=root/"presets/cinematic-lenses/26-Internal-Field-Edge-FX.ldbpreset";
            if(!fs::is_regular_file(presetPath)) {
                std::fprintf(stderr,"Missing Internal Field Edge FX preset: %s\n",presetPath.c_str());
                return 9;
            }
            for(const auto& source:sources) {
                auto p=loadPreset(presetPath,source.width,source.height);
                auto result=render(engine,device,queue,*source.pixels,source.width,source.height,p);
                bool milano=std::string(source.key).rfind("milano",0)==0;
                auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):
                    guideRec709Gamma24FromAP1(result);
                std::string name=std::string("26-internal-field-edge-fx-")+source.key+".png";
                if(!writePNG((out/name).string(),display,source.width,source.height))return 10;
                std::printf("Wrote field-PSF validation / %s\n",source.key);
            }
            return 0;
        }

        if(fieldPSFLibraryValidation||allPresetLibraryValidation) {
            const char* presetRootEnvironment=std::getenv("LDB_PRESET_ROOT");
            fs::path presetRoot=presetRootEnvironment&&*presetRootEnvironment?
                fs::path(presetRootEnvironment):root/"presets";
            struct PresetCollection { const char* slug; fs::path path; } collections[]={
                {"demo",presetRoot/"demonstrations"},
                {"cinematic",presetRoot/"cinematic-lenses"}};
            size_t renderedPresets=0;
            for(const auto& collection:collections) {
                std::vector<fs::path> presetPaths;
                for(const auto& entry:fs::directory_iterator(collection.path))
                    if(entry.path().extension()==".ldbpreset")presetPaths.push_back(entry.path());
                std::sort(presetPaths.begin(),presetPaths.end());
                for(const auto& presetPath:presetPaths) {
                    auto probe=loadPreset(presetPath,chartW,chartH);
                    const bool relevant=probe.apertureResponse>1e-6f||
                        probe.cornerSharpnessLoss>1e-6f||probe.fieldCurvature>1e-6f||
                        fabs(probe.astigmatism)>1e-6f||probe.radialSmear>1e-6f||
                        probe.tangentialSmear>1e-6f;
                    if(!allPresetLibraryValidation&&!relevant)continue;
                    ++renderedPresets;
                    std::string presetSlug=std::string(collection.slug)+"-"+
                        guideFileSlug(presetPath.stem().string());
                    for(const auto& source:sources) {
                        auto p=loadPreset(presetPath,source.width,source.height);
                        auto result=render(engine,device,queue,*source.pixels,
                                           source.width,source.height,p);
                        bool milano=std::string(source.key).rfind("milano",0)==0;
                        auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):
                            guideRec709Gamma24FromAP1(result);
                        std::string name=presetSlug+"-"+source.key+".png";
                        if(!writePNG((out/name).string(),display,source.width,source.height))return 10;
                        std::printf("Wrote field-PSF library %s / %s / %s\n",
                                    collection.slug,presetPath.stem().c_str(),source.key);
                    }
                }
            }
            if(renderedPresets==0) {
                std::fprintf(stderr,"No presets selected for validation.\n");
                return 11;
            }
            std::printf("Rendered %zu %s presets.\n",renderedPresets,
                        allPresetLibraryValidation?"factory":"relevant field/aperture");
            return 0;
        }

        if(opticalModelValidation) {
            constexpr int families[]={5,6,11,16,18,19,20,24};
            for(int family:families) {
                char prefix[8]; std::snprintf(prefix,sizeof(prefix),"%02d-",family);
                std::vector<fs::path> variants;
                for(const auto& entry:fs::directory_iterator(root/"presets/cinematic-lenses"))
                    if(entry.path().extension()==".ldbpreset"&&
                       entry.path().filename().string().rfind(prefix,0)==0)
                        variants.push_back(entry.path());
                std::sort(variants.begin(),variants.end());
                if(variants.size()!=3) {
                    std::fprintf(stderr,"Expected three variants for family %02d, found %zu\n",family,variants.size());
                    return 9;
                }
                for(const auto& presetPath:variants) {
                    std::string presetSlug=guideFileSlug(presetPath.stem().string());
                    for(const auto& source:sources) {
                        if(std::string(source.key)!="iso"&&std::string(source.key)!="milano1")continue;
                        auto p=loadPreset(presetPath,source.width,source.height);
                        auto result=render(engine,device,queue,*source.pixels,source.width,source.height,p);
                        bool milano=std::string(source.key)=="milano1";
                        auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):
                            guideRec709Gamma24FromAP1(result);
                        std::string name=presetSlug+"-"+source.key+".png";
                        if(!writePNG((out/name).string(),display,source.width,source.height))return 10;
                        std::printf("Wrote optical-model validation %s / %s\n",presetPath.stem().c_str(),source.key);
                    }
                }
            }
            // Decompose the three most demanding Caricature presets. These
            // renders distinguish field-kernel artifacts from aperture and
            // chromatic behavior before another subsystem is changed.
            struct Isolation { int family; const char* label; } isolations[]={
                {5,"no-aperture"},{5,"aperture-only"},
                {6,"no-aperture"},{6,"aperture-only"},
                {18,"no-chromatic"},{18,"chromatic-only"},
                {19,"no-chromatic"},{19,"chromatic-only"}};
            for(const auto& isolation:isolations) {
                char prefix[12];std::snprintf(prefix,sizeof(prefix),"%02d-",isolation.family);
                fs::path presetPath;
                for(const auto& entry:fs::directory_iterator(root/"presets/cinematic-lenses"))
                    if(entry.path().filename().string().rfind(prefix,0)==0&&
                       entry.path().stem().string().find("-3-Caricature")!=std::string::npos) {
                        presetPath=entry.path();break;
                    }
                auto p=loadPreset(presetPath,chartW,chartH);
                std::string label=isolation.label;
                if(label=="no-aperture")p.apertureResponse=0.0f;
                if(label=="aperture-only") {
                    p.cornerSharpnessLoss=p.fieldCurvature=p.astigmatism=0.0f;
                    p.radialSmear=p.tangentialSmear=p.longitudinalCA=0.0f;
                }
                if(label=="no-chromatic") {
                    p.lateralCARed=p.lateralCABlue=p.longitudinalCA=0.0f;
                    p.refractiveDispersion=0.0f;
                }
                if(label=="chromatic-only") {
                    p.cornerSharpnessLoss=p.fieldCurvature=p.astigmatism=0.0f;
                    p.radialSmear=p.tangentialSmear=0.0f;
                }
                auto result=render(engine,device,queue,iso,chartW,chartH,p);
                std::string name="isolate-"+std::to_string(isolation.family)+"-"+label+"-iso.png";
                if(!writePNG((out/name).string(),guideRec709Gamma24FromAP1(result),chartW,chartH))return 12;
                std::printf("Wrote optical-model isolation %02d / %s\n",isolation.family,isolation.label);
            }
            // A single off-axis impulse exposes separated blur lobes more
            // clearly than a photograph. Record energy and RMS spread so the
            // candidate cannot appear smoother simply by losing brightness.
            std::vector<simd_float4> impulse(size_t(chartW)*chartH,simd_float4{0,0,0,1});
            const uint32_t impulseX=120,impulseY=110;
            impulse[size_t(impulseY)*chartW+impulseX]={8,8,8,1};
            auto diagnostic=LDBNeutralOpticsParameters(chartW,chartH);
            diagnostic.cornerSharpnessLoss=2.0f;
            diagnostic.fieldCurvature=1.75f;
            diagnostic.astigmatism=.8f;
            diagnostic.radialSmear=1.25f;
            diagnostic.tangentialSmear=1.55f;
            diagnostic.responseFieldOnset=.05f;
            diagnostic.responseFieldFalloff=.95f;
            auto impulseResult=render(engine,device,queue,impulse,chartW,chartH,diagnostic);
            if(!writePNG((out/"diagnostic-impulse.png").string(),
                         guideRec709Gamma24FromAP1(impulseResult),chartW,chartH))return 11;
            double energy=0.0,weightedRadius2=0.0,peak=0.0;
            for(uint32_t y=0;y<chartH;++y)for(uint32_t x=0;x<chartW;++x){
                const auto& px=impulseResult[size_t(y)*chartW+x];
                double luma=std::max(0.0,double(px.x*.272229f+px.y*.674082f+px.z*.053689f));
                double dx=double(x)-impulseX,dy=double(y)-impulseY;
                energy+=luma; weightedRadius2+=luma*(dx*dx+dy*dy); peak=std::max(peak,luma);
            }
            std::ofstream metrics(out/"metrics.txt");
            metrics<<"Impulse input energy: 8\n"
                   <<"Impulse output energy: "<<energy<<"\n"
                   <<"Impulse energy ratio: "<<energy/8.0<<"\n"
                   <<"Impulse RMS radius px: "<<std::sqrt(weightedRadius2/std::max(energy,1e-12))<<"\n"
                   <<"Impulse peak: "<<peak<<"\n";
            std::printf("Wrote optical A/B impulse diagnostic and metrics\n");
            return 0;
        }
        const ExampleGroup groups[]={
            {"presets",2},{"processing",6},{"capture",1},{"look",2},{"geometry",3},{"field-shape",4},
            {"focus-field",5},{"detail",6},{"chromatic",7},{"anamorphic",8},{"refractive",21},{"prism",31},{"aperture",9},
            {"vignette",10},{"image-circle",11},{"bloom",12},{"glare-halo",13},{"transmission",14},
            {"highlight-response",15},{"off-axis",16},{"variation",17},{"front-wear",20},
            {"internal-contamination",24},{"depth",18},{"bokeh-swirl",25},{"petzval-field",26}};
        std::unordered_set<std::string> written;
        if(!changedGlareOnly&&!changedPresets166&&!changedPresets166b&&!changedPresets167&&!changedPreset26) for(const auto& source:sources){std::string beforeName=std::string(source.key)+"-before.png";
            bool milano=std::string(source.key).rfind("milano",0)==0;
            auto before=milano?guideMilanoDisplayFromAP1(*source.pixels,milanoDisplayLUT):
                guideRec709Gamma24FromAP1(*source.pixels);
            if(!writePNG((out/beforeName).string(),before,source.width,source.height))return 5;written.insert(beforeName);}
        for(const auto& group:groups){
            if(changedPreset26)continue;
            if(changedGlareOnly&&std::string(group.slug)!="glare-halo"&&
               std::string(group.slug)!="highlight-response")continue;
            if(changedPresets166) {
                const std::unordered_set<std::string> changed={"capture","look","field-shape",
                    "focus-field","chromatic","aperture"};
                if(!changed.count(group.slug))continue;
            }
            if(changedPresets166b) {
                const std::unordered_set<std::string> changed={"focus-field","bokeh-swirl",
                    "petzval-field"};
                if(!changed.count(group.slug))continue;
            }
            if(changedPresets167&&std::string(group.slug)!="bokeh-swirl")continue;
            char preset[80];std::snprintf(preset,sizeof(preset),"%02d-Demo-",group.demo);fs::path presetPath;
            for(auto& f:fs::directory_iterator(root/"presets/demonstrations"))if(f.path().filename().string().rfind(preset,0)==0){presetPath=f.path();break;}
            for(const auto& source:sources){
                if(std::string(group.slug)=="processing"&&std::string(source.key)!="iso")continue;
                auto input=std::string(group.slug)=="depth"?withGuideDepth(*source.pixels,source.width,source.height):*source.pixels;
                auto p=loadPreset(presetPath,source.width,source.height);
                if(std::string(group.slug)=="processing")p.processingFlags=LDBDiagnosticDifference;
                auto result=render(engine,device,queue,input,source.width,source.height,p);
                bool milano=std::string(source.key).rfind("milano",0)==0;
                auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):
                    guideRec709Gamma24FromAP1(result);
                std::string name=std::string(group.slug)+"-"+source.key+"-after.png";
                if(!writePNG((out/name).string(),display,source.width,source.height))return 6;
                std::printf("Wrote %s / %s\n",group.slug,source.key);
            }
        }
        std::vector<fs::path> mediumPresets;
        for(const auto& entry:fs::directory_iterator(root/"presets/cinematic-lenses")) {
            if(entry.path().extension()==".ldbpreset"&&
               (entry.path().stem().string().find("-2-Medium")!=std::string::npos||
                entry.path().stem().string()=="21-Bodycam-Edge-Stress"||
                entry.path().stem().string()=="26-Internal-Field-Edge-FX"))
                mediumPresets.push_back(entry.path());
        }
        std::sort(mediumPresets.begin(),mediumPresets.end());
        for(const auto& presetPath:mediumPresets) {
            if(changedGlareOnly) {
                auto candidate=loadPreset(presetPath,chartW,chartH);
                if(candidate.glareEnergy<=0.0f)continue;
            }
            if(changedPresets166||changedPresets166b||changedPresets167) {
                const std::string filename=presetPath.filename().string();
                if(changedPresets166b||changedPresets167||
                   (filename.rfind("05-",0)!=0&&filename.rfind("06-",0)!=0&&
                    filename.rfind("18-",0)!=0&&filename.rfind("19-",0)!=0))continue;
            }
            if(changedPreset26&&presetPath.filename().string().rfind("26-",0)!=0)
                continue;
            std::string presetSlug=guideFileSlug(presetPath.stem().string());
            for(const auto& source:sources) {
                auto p=loadPreset(presetPath,source.width,source.height);
                auto result=render(engine,device,queue,*source.pixels,source.width,source.height,p);
                bool milano=std::string(source.key).rfind("milano",0)==0;
                auto display=milano?guideMilanoDisplayFromAP1(result,milanoDisplayLUT):
                    guideRec709Gamma24FromAP1(result);
                std::string name="preset-"+presetSlug+"-"+source.key+"-after.png";
                if(!writePNG((out/name).string(),display,source.width,source.height))return 7;
                std::printf("Wrote preset %s / %s\n",presetPath.stem().c_str(),source.key);
            }
        }
        if(!changedGlareOnly&&!changedPresets166&&!changedPresets166b&&!changedPresets167&&!changedPreset26&&mediumPresets.size()!=26) {
            std::fprintf(stderr,"Expected 24 Medium cinematic presets plus two signature presets, found %zu\n",mediumPresets.size());
            return 8;
        }
    }
    return 0;
}
