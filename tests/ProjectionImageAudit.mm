#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <string>
#include <vector>

namespace fs=std::filesystem;

struct Image { size_t width=0,height=0; std::vector<uint8_t> rgba; };

static Image loadPNG(const fs::path& path) {
    NSURL* url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,nullptr);
    if(!source)throw std::runtime_error("Cannot open "+path.string());
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,nullptr);
    CFRelease(source);
    if(!image)throw std::runtime_error("Cannot decode "+path.string());
    Image result;result.width=CGImageGetWidth(image);result.height=CGImageGetHeight(image);
    result.rgba.resize(result.width*result.height*4);
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo bitmapInfo=CGBitmapInfo(uint32_t(kCGImageAlphaPremultipliedLast)|
                                         uint32_t(kCGBitmapByteOrder32Big));
    CGContextRef context=CGBitmapContextCreate(result.rgba.data(),result.width,result.height,8,
        result.width*4,space,bitmapInfo);
    CGColorSpaceRelease(space);
    CGContextDrawImage(context,CGRectMake(0,0,result.width,result.height),image);
    CGContextRelease(context);CGImageRelease(image);
    return result;
}

static void compare(const fs::path& root,const char* group,const std::string& label,
                    const fs::path& before,const fs::path& after) {
    Image a=loadPNG(root/before),b=loadPNG(root/after);
    if(a.width!=b.width||a.height!=b.height)throw std::runtime_error("Dimension mismatch: "+label);
    double absolute=0.0,squared=0.0,maximum=0.0;
    size_t changed=0,pixels=a.width*a.height;
    for(size_t i=0;i<pixels;++i) {
        bool pixelChanged=false;
        for(size_t c=0;c<3;++c) {
            double delta=std::abs(int(a.rgba[i*4+c])-int(b.rgba[i*4+c]))/255.0;
            absolute+=delta;squared+=delta*delta;maximum=std::max(maximum,delta);
            if(delta>2.0/255.0)pixelChanged=true;
        }
        if(pixelChanged)++changed;
    }
    std::printf("%-9s\t%-42s\tMAE %.5f\tRMSE %.5f\tchanged %6.2f%%\tmax %.3f\n",
        group,label.c_str(),absolute/(pixels*3),std::sqrt(squared/(pixels*3)),
        100.0*double(changed)/pixels,maximum);
}

int main(int argc,char** argv) {
    @autoreleasepool {
        if(argc!=2){std::fprintf(stderr,"usage: %s experiment-root\n",argv[0]);return 2;}
        try {
            fs::path root=argv[1];
            const char* sources[]={"iso","optical","milano1","milano2","milano3"};
            const char* models[]={"equidistant","equisolid","stereographic","orthographic"};
            std::puts("group\tpair\tmetrics");
            for(const char* framing: {"full-frame","balanced","center-scale","boundary-safe"})
                for(const char* source: {"iso","milano1"})
                    compare(root,"framing",std::string(framing)+" / "+source,
                        fs::path("images")/(std::string("baseline-geometry-")+source+".png"),
                        fs::path("images")/(std::string("framing-")+framing+"-"+source+".png"));
            for(const char* model:models)for(const char* kind: {"geometry","optical"})
                for(const char* source:sources)
                    compare(root,kind,std::string(model)+" / "+source,
                        fs::path("images")/(std::string("baseline-")+kind+"-"+source+".png"),
                        fs::path("images")/(std::string(model)+"-"+kind+"-"+source+".png"));
        } catch(const std::exception& error) {
            std::fprintf(stderr,"ERROR: %s\n",error.what());return 1;
        }
    }
    return 0;
}
