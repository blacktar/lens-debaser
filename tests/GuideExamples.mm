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
    SET(apertureRimWeight) SET(fieldAspect) SET(fieldRotation) SET(transmissionDensity)
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
    else if(key=="depthMode")p.depthMode=uint32_t(v); else if(key=="variationSeed")p.variationSeed=uint32_t(v);
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
    auto p=LDBNeutralOpticsParameters(width,height); std::ifstream in(path); std::string line;
    while(std::getline(in,line)){auto at=line.find('=');if(at==std::string::npos||line.empty()||line[0]=='#')continue;
        try{assignValue(p,line.substr(0,at),std::stof(line.substr(at+1)));}catch(...){} }
    if(p.captureFocusDistance<999.5f)p.captureFocusDistance*=.01f;
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

int main(int argc,char** argv) {
    if(argc<4||argc>5){std::fprintf(stderr,"usage: %s metallib repo-root output-dir [changed-glare]\n",argv[0]);return 2;}
    @autoreleasepool {
        const bool changedGlareOnly=argc==5&&std::string(argv[4])=="changed-glare";
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
        auto ogc=loadRec709Gamma24Chart((root/"inputs/redistributable/OGC-TERA-CHART-1.png").c_str(),chartW,chartH);
        uint32_t mw=0,mh=0; auto milano1Encoded=loadEncodedTIFF((root/"inputs/redistributable/iphone_milano_dwg_1.tif").c_str(),mw,mh);
        auto milano1=resizePixels(convertEncoding(milano1Encoded,LDBWorkingColorSpaceDaVinciIntermediate,false),mw,mh,milanoW,milanoH);
        auto milano2Encoded=loadEncodedTIFF((root/"inputs/redistributable/iphone_milano2___dwg.tif").c_str(),mw,mh);
        auto milano2=resizePixels(convertEncoding(milano2Encoded,LDBWorkingColorSpaceDaVinciIntermediate,false),mw,mh,milanoW,milanoH);
        auto milano3Encoded=loadEncodedTIFF((root/"inputs/redistributable/iphone_milano3_dwg.tif").c_str(),mw,mh);
        auto milano3=resizePixels(convertEncoding(milano3Encoded,LDBWorkingColorSpaceDaVinciIntermediate,false),mw,mh,milanoW,milanoH);
        const GuideSource sources[]={{"iso",&iso,chartW,chartH},{"ogc",&ogc,chartW,chartH},
            {"milano1",&milano1,milanoW,milanoH},{"milano2",&milano2,milanoW,milanoH},
            {"milano3",&milano3,milanoW,milanoH}};
        const ExampleGroup groups[]={
            {"presets",2},{"processing",6},{"capture",1},{"look",2},{"geometry",3},{"field-shape",4},
            {"focus-field",5},{"detail",6},{"chromatic",7},{"anamorphic",8},{"refractive",21},{"prism",31},{"aperture",9},
            {"vignette",10},{"image-circle",11},{"bloom",12},{"glare-halo",13},{"transmission",14},
            {"highlight-response",15},{"off-axis",16},{"variation",17},{"front-wear",20},
            {"internal-contamination",24},{"depth",18},{"blend",19}};
        std::unordered_set<std::string> written;
        if(!changedGlareOnly) for(const auto& source:sources){std::string beforeName=std::string(source.key)+"-before.png";
            bool milano=std::string(source.key).rfind("milano",0)==0;
            auto before=milano?guideMilanoDisplayFromAP1(*source.pixels,milanoDisplayLUT):
                guideRec709Gamma24FromAP1(*source.pixels);
            if(!writePNG((out/beforeName).string(),before,source.width,source.height))return 5;written.insert(beforeName);}
        for(const auto& group:groups){
            if(changedGlareOnly&&std::string(group.slug)!="glare-halo"&&
               std::string(group.slug)!="highlight-response")continue;
            char preset[80];std::snprintf(preset,sizeof(preset),"%02d-Demo-",group.demo);fs::path presetPath;
            for(auto& f:fs::directory_iterator(root/"presets/demonstrations"))if(f.path().filename().string().rfind(preset,0)==0){presetPath=f.path();break;}
            if(std::string(group.slug)=="blend") {
                auto p=loadPreset(presetPath,chartW,chartH);
                p.effectBlend=1.0f;
                auto full=guideRec709Gamma24FromAP1(render(engine,device,queue,iso,chartW,chartH,p));
                if(!writePNG((out/"blend-iso-100.png").string(),full,chartW,chartH))return 6;
                p.effectBlend=.5f;
                auto half=guideRec709Gamma24FromAP1(render(engine,device,queue,iso,chartW,chartH,p));
                if(!writePNG((out/"blend-iso-50.png").string(),half,chartW,chartH))return 6;
                std::printf("Wrote blend / iso / 100 and 50 percent\n");
                continue;
            }
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
                entry.path().stem().string()=="21-Bodycam-Edge-Stress"))
                mediumPresets.push_back(entry.path());
        }
        std::sort(mediumPresets.begin(),mediumPresets.end());
        for(const auto& presetPath:mediumPresets) {
            if(changedGlareOnly) {
                auto candidate=loadPreset(presetPath,chartW,chartH);
                if(candidate.glareEnergy<=0.0f)continue;
            }
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
        if(!changedGlareOnly&&mediumPresets.size()!=25) {
            std::fprintf(stderr,"Expected 24 Medium cinematic presets plus Bodycam Edge Stress, found %zu\n",mediumPresets.size());
            return 8;
        }
    }
    return 0;
}
