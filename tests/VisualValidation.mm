#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <unordered_set>
#include <vector>
#include "LDBColorReference.h"
#include "LDBOpticsEngine.h"

static float decodeSRGB(float v) {
    return v <= .04045f ? v / 12.92f : std::pow((v + .055f) / 1.055f, 2.4f);
}

static simd_float3 sRGBToAP1(simd_float3 encoded) {
    simd_float3 linear = {decodeSRGB(encoded.x), decodeSRGB(encoded.y), decodeSRGB(encoded.z)};
    const LDBColorReference::Matrix3 matrix = {{{.6131324224f,.3395380158f,.0474166960f},
        {.0701243808f,.9163940113f,.0134515240f},{.0205876575f,.1095745716f,.8697854040f}}};
    return LDBColorReference::apply(matrix, linear);
}

static simd_float3 hueRampAP1(float hue) {
    float h = hue * 6.0f;
    int sector = int(floor(h)) % 6;
    float f = h - floor(h);
    simd_float3 rgb;
    switch (sector) {
        case 0: rgb = {1, f, 0}; break;
        case 1: rgb = {1-f, 1, 0}; break;
        case 2: rgb = {0, 1, f}; break;
        case 3: rgb = {0, 1-f, 1}; break;
        case 4: rgb = {f, 0, 1}; break;
        default: rgb = {1, 0, 1-f}; break;
    }
    return sRGBToAP1(rgb);
}

static simd_float3 colorCheckerPatch(int index) {
    static const uint8_t patches[24][3] = {
        {115,82,68},{194,150,130},{98,122,157},{87,108,67},{133,128,177},{103,189,170},
        {214,126,44},{80,91,166},{193,90,99},{94,60,108},{157,188,64},{224,163,46},
        {56,61,150},{70,148,73},{175,54,60},{231,199,31},{187,86,149},{8,133,161},
        {243,243,242},{200,200,200},{160,160,160},{122,122,121},{85,85,85},{52,52,52}
    };
    return sRGBToAP1(simd_float3{float(patches[index][0])/255.0f,
                                  float(patches[index][1])/255.0f,
                                  float(patches[index][2])/255.0f});
}

static std::vector<simd_float4> makeChart(uint32_t width, uint32_t height) {
    std::vector<simd_float4> image(width * height, simd_float4{0.035f, 0.035f, 0.035f, 1.0f});
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            float nx = (float(x) + 0.5f) / width;
            float ny = (float(y) + 0.5f) / height;
            bool grid = (x % 64 < 2) || (y % 64 < 2);
            bool fineGrid = (x % 16 == 0) || (y % 16 == 0);
            float checker = ((x / 8 + y / 8) & 1) ? 0.70f : 0.16f;
            simd_float3 rgb = grid ? simd_float3{0.55f, 0.55f, 0.55f}
                                   : (fineGrid ? simd_float3{0.10f, 0.10f, 0.10f}
                                               : simd_float3{0.035f, 0.035f, 0.035f});
            if (nx > 0.40f && nx < 0.60f && ny > 0.36f && ny < 0.59f) rgb = simd_float3{checker, checker, checker};
            if (nx >= .32f && nx < .68f && ny >= .35f && ny < .61f) {
                float localX = (nx - .32f) / .36f;
                float localY = (ny - .35f) / .26f;
                int column = std::min(5, int(localX * 6));
                int row = std::min(3, int(localY * 4));
                float cellX = localX * 6 - column, cellY = localY * 4 - row;
                if (cellX > .07f && cellX < .93f && cellY > .10f && cellY < .90f)
                    rgb = colorCheckerPatch(row * 6 + column);
                else rgb = {.012f, .012f, .012f};
            }
            // Scene-linear color-management references. These deliberately
            // include values above 1.0; comparison happens in AP1 before the
            // display preview is made.
            if (nx > 0.455f && nx < 0.545f && ny > 0.62f && ny < 0.69f)
                rgb = {0.18f, 0.18f, 0.18f};
            if (ny >= 0.70f && ny < 0.775f) rgb = {nx, nx, nx};
            else if (ny >= 0.79f && ny < 0.885f) rgb = hueRampAP1(nx);
            else if (ny >= 0.90f && ny < 0.98f) {
                float hdr = std::exp2(-6.0f + 10.0f * nx); // 1/64 through 16
                rgb = {hdr, hdr, hdr};
            }
            image[y * width + x] = {rgb.x, rgb.y, rgb.z, 1.0f};
        }
    }
    const simd_uint2 lights[] = {{width / 2, height / 5}, {width / 7, height / 4}, {width * 6 / 7, height / 4}};
    for (auto light : lights) {
        for (int dy = -4; dy <= 4; ++dy) for (int dx = -4; dx <= 4; ++dx) {
            int x = int(light.x) + dx, y = int(light.y) + dy;
            if (x >= 0 && y >= 0 && x < int(width) && y < int(height) && dx * dx + dy * dy <= 16)
                image[uint32_t(y) * width + uint32_t(x)] = {6.0f, 5.0f, 3.5f, 1.0f};
        }
    }
    return image;
}

static std::vector<simd_float4> makeUniformField(uint32_t width, uint32_t height, float value = .18f) {
    return std::vector<simd_float4>(size_t(width) * height, simd_float4{value, value, value, 1});
}

static std::vector<simd_float4> makePolarChart(uint32_t width, uint32_t height) {
    std::vector<simd_float4> image(size_t(width) * height);
    float aspect = float(width) / float(height);
    for (uint32_t y = 0; y < height; ++y) for (uint32_t x = 0; x < width; ++x) {
        simd_float2 uv = {(float(x)+.5f)/width, (float(y)+.5f)/height};
        simd_float2 q = {(uv.x-.5f)*aspect, uv.y-.5f};
        float radius = simd_length(q);
        float angle = std::atan2(q.y, q.x);
        float ring = std::fmod(radius * 24.0f, 1.0f);
        float spoke = std::fmod((angle + float(M_PI)) / (2*float(M_PI)) * 48.0f, 1.0f);
        bool rings = ring < .055f;
        bool spokes = spoke < .10f && radius < .58f;
        bool dots = (x % 40 < 3) && (y % 40 < 3);
        float value = (rings || spokes || dots) ? .75f : .025f;
        image[size_t(y)*width+x] = {value, value, value, 1};
    }
    return image;
}

static std::vector<simd_float4> makeHDRSources(uint32_t width, uint32_t height) {
    std::vector<simd_float4> image(size_t(width) * height, simd_float4{.002f,.002f,.002f,1});
    struct Source { float x, y, radius, intensity; simd_float3 color; };
    const Source sources[] = {
        {.50f,.50f,1.0f,16,{1,1,1}}, {.25f,.50f,2.0f,8,{1,.55f,.25f}},
        {.75f,.50f,4.0f,4,{.25f,.55f,1}}, {.08f,.12f,2.0f,12,{1,1,1}},
        {.92f,.12f,2.0f,12,{1,1,1}}, {.08f,.88f,2.0f,12,{1,1,1}},
        {.92f,.88f,2.0f,12,{1,1,1}}, {.002f,.50f,5.0f,10,{1,.8f,.55f}},
        {.998f,.50f,5.0f,10,{.55f,.75f,1}}
    };
    for (const auto& source : sources) {
        int cx=int(source.x*width), cy=int(source.y*height), r=int(std::ceil(source.radius));
        for (int dy=-r;dy<=r;++dy) for(int dx=-r;dx<=r;++dx) {
            int px=cx+dx,py=cy+dy;
            if(px>=0&&py>=0&&px<int(width)&&py<int(height)&&dx*dx+dy*dy<=source.radius*source.radius) {
                simd_float3 v=source.color*source.intensity;
                image[size_t(py)*width+px]={v.x,v.y,v.z,1};
            }
        }
    }
    return image;
}

static std::vector<simd_float4> makeFocusTransitionChart(uint32_t width,uint32_t height) {
    std::vector<simd_float4> image(size_t(width)*height,simd_float4{.018f,.018f,.018f,1});
    for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
        float u=(float(x)+.5f)/width,v=(float(y)+.5f)/height;
        float value=.018f;
        // Analytic highlight row progresses from crisp to broadly defocused.
        for(int i=0;i<9;++i) {
            float cx=.10f+.10f*i,cy=.28f;
            float sigma=(1.5f+2.0f*i)/float(height);
            float dx=(u-cx)*float(width)/float(height),dy=v-cy;
            value+=.90f*std::exp(-(dx*dx+dy*dy)/(2*sigma*sigma));
        }
        // A focus wedge exposes colored transition width without a dense grid.
        float edge=.18f+.64f*u;
        float softness=.0007f+.012f*u;
        float wedge=.5f+.5f*std::tanh((edge-v)/softness);
        if(v>.52f&&v<.88f)value=std::max(value,.035f+.72f*wedge);
        image[size_t(y)*width+x]={value,value,value,1};
    }
    return image;
}

static std::vector<simd_float4> makeDepthBoundaryChart(uint32_t width,uint32_t height) {
    // RGB is a deliberately difficult photographic proxy; alpha carries a
    // discontinuous near-black depth map. The layout combines a large curved
    // silhouette, thin occluders, crossing edges and highlights placed directly
    // beside depth jumps so contamination is easy to see.
    std::vector<simd_float4> image(size_t(width)*height);
    const float aspect=float(width)/float(height);
    for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
        float u=(float(x)+.5f)/width,v=(float(y)+.5f)/height;
        float depth=.86f;
        simd_float3 rgb={.055f+.055f*u,.065f+.045f*v,.075f+.035f*u};

        // Mid-depth wall with a hard diagonal and fine texture.
        if(v>.16f+.34f*u) {
            depth=.58f;
            float grid=((x/18+y/18)&1)?.16f:.09f;
            rgb={grid,grid*.92f,grid*.78f};
        }

        // Near curved subject silhouette with hair-like protrusions.
        simd_float2 q={(u-.48f)*aspect,v-.58f};
        bool head=simd_length(simd_float2{q.x/.18f,q.y/.25f})<1.0f;
        bool shoulders=(v>.67f)&&abs(q.x)<(.31f-(v-.67f)*.28f);
        bool hair=(v>.31f&&v<.55f)&&
            (abs(q.x-.20f)<.004f||abs(q.x-.215f)<.003f||abs(q.x+.205f)<.004f);
        if(head||shoulders||hair) {
            depth=.18f;
            float texture=.075f+.025f*std::sin(u*180.0f)*std::sin(v*130.0f);
            rgb={texture*.82f,texture*.92f,texture};
        }

        // Thin mid-depth railings pass in front of both near and far regions.
        bool verticalRail=(abs(u-.14f)<.0035f)||(abs(u-.79f)<.0035f)||(abs(u-.86f)<.0025f);
        bool diagonalRail=abs(v-(.88f-.52f*u))<.0035f;
        if(verticalRail||diagonalRail) {
            depth=.40f;
            rgb={.52f,.48f,.40f};
        }

        // Bright practicals on either side of boundaries and one on-subject.
        struct Light {float x,y,r,d;simd_float3 c;};
        const Light lights[]={
            {.285f,.42f,.010f,.86f,{5.0f,3.8f,2.2f}},
            {.675f,.43f,.010f,.58f,{2.2f,3.8f,5.0f}},
            {.375f,.52f,.007f,.18f,{5.0f,4.7f,3.8f}},
            {.705f,.69f,.006f,.40f,{4.0f,2.4f,1.4f}}
        };
        for(const auto& light:lights) {
            simd_float2 d={(u-light.x)*aspect,v-light.y};
            float distance=simd_length(d);
            float t=std::clamp((distance-light.r)/(2.0f/height),0.0f,1.0f);
            float coverage=1.0f-t*t*(3.0f-2.0f*t);
            if(coverage>0) {
                rgb=rgb*(1.0f-coverage)+light.c*coverage;
                depth=light.d;
            }
        }
        image[size_t(y)*width+x]={rgb.x,rgb.y,rgb.z,depth};
    }
    return image;
}

static std::vector<simd_float4> loadTIFFChart(const char* path, uint32_t width, uint32_t height) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(nullptr,
        reinterpret_cast<const UInt8*>(path), std::strlen(path), false);
    CGImageSourceRef source = url ? CGImageSourceCreateWithURL(url, nullptr) : nullptr;
    CGImageRef chartImage = source ? CGImageSourceCreateImageAtIndex(source, 0, nullptr) : nullptr;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!chartImage) {
        CGColorSpaceRelease(colorSpace); if (source) CFRelease(source); if (url) CFRelease(url);
        return {};
    }

    std::vector<uint8_t> rgba(size_t(width) * height * 4, 255);
    CGContextRef context = CGBitmapContextCreate(rgba.data(), width, height, 8, width * 4,
        colorSpace, CGBitmapInfo(kCGImageAlphaPremultipliedLast) | CGBitmapInfo(kCGBitmapByteOrder32Big));
    if (!context) {
        CGImageRelease(chartImage); CGColorSpaceRelease(colorSpace); CFRelease(source); CFRelease(url);
        return {};
    }
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    const float sourceWidth = float(CGImageGetWidth(chartImage));
    const float sourceHeight = float(CGImageGetHeight(chartImage));
    // Centered aspect-fill: preserve chart geometry and crop only the unavoidable
    // overflow caused by fitting the chart's 1.60:1 raster into a 16:9 viewport.
    float scale = std::max(float(width) / sourceWidth, float(height) / sourceHeight);
    CGSize fitted = CGSizeMake(sourceWidth * scale, sourceHeight * scale);
    CGRect viewport = CGRectMake((width - fitted.width) * .5f, (height - fitted.height) * .5f,
                                 fitted.width, fitted.height);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, viewport, chartImage);
    CGImageRelease(chartImage);
    CGContextRelease(context); CGColorSpaceRelease(colorSpace); CFRelease(source); CFRelease(url);
    std::vector<simd_float4> result(size_t(width) * height);
    for (uint32_t y = 0; y < height; ++y) for (uint32_t x = 0; x < width; ++x) {
        size_t source = (size_t(y) * width + x) * 4;
        simd_float3 ap1 = sRGBToAP1(simd_float3{float(rgba[source])/255.0f,
            float(rgba[source+1])/255.0f, float(rgba[source+2])/255.0f});
        result[size_t(y)*width+x] = {ap1.x,ap1.y,ap1.z,1};
    }
    return result;
}

static std::vector<simd_float4> loadEncodedTIFF(const char* path, uint32_t& width, uint32_t& height) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(nullptr,
        reinterpret_cast<const UInt8*>(path), std::strlen(path), false);
    CGImageSourceRef source = url ? CGImageSourceCreateWithURL(url, nullptr) : nullptr;
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, nullptr) : nullptr;
    if (!image) { if (source) CFRelease(source); if (url) CFRelease(url); return {}; }
    width = uint32_t(CGImageGetWidth(image)); height = uint32_t(CGImageGetHeight(image));
    CGImageRelease(image); CFRelease(source); CFRelease(url);

    // Camera fixtures are little-endian, uncompressed, chunky 16-bit RGB TIFFs
    // with their sole strip beginning at byte 8. Read samples directly so no ICC,
    // display conversion, component reordering, or precision reduction can occur.
    const size_t sampleCount = size_t(width) * height * 3;
    const uint32_t expectedIFDOffset = uint32_t(8 + sampleCount * sizeof(uint16_t));
    std::ifstream input(path, std::ios::binary);
    uint8_t header[8] = {};
    input.read(reinterpret_cast<char*>(header), sizeof(header));
    uint32_t ifdOffset = uint32_t(header[4]) | (uint32_t(header[5]) << 8) |
                         (uint32_t(header[6]) << 16) | (uint32_t(header[7]) << 24);
    if (!input || header[0]!='I' || header[1]!='I' || header[2]!=42 || header[3]!=0 ||
        ifdOffset < expectedIFDOffset) return {};
    std::vector<uint16_t> rgb(sampleCount);
    input.read(reinterpret_cast<char*>(rgb.data()), std::streamsize(rgb.size() * sizeof(uint16_t)));
    if (!input) return {};
    std::vector<simd_float4> result(size_t(width) * height);
    for (size_t i = 0; i < result.size(); ++i) {
        result[i] = {rgb[i*3]/65535.0f, rgb[i*3+1]/65535.0f, rgb[i*3+2]/65535.0f, 1};
    }
    return result;
}

static simd_float3 meanRGB(const std::vector<simd_float4>& pixels) {
    simd_double3 sum = {0,0,0};
    for (const auto& p : pixels) sum += simd_double3{p.x,p.y,p.z};
    sum /= double(pixels.size());
    return {float(sum.x), float(sum.y), float(sum.z)};
}

struct CubeLUT {
    uint32_t size = 0;
    std::vector<simd_float3> values;

    bool load(const char* path) {
        std::ifstream input(path);
        std::string line;
        while (std::getline(input, line)) {
            if (line.rfind("LUT_3D_SIZE", 0) == 0) {
                unsigned n = 0; if (std::sscanf(line.c_str(), "LUT_3D_SIZE %u", &n) == 1) size = n;
            } else if (!line.empty() && line[0] != '#' && line[0] != 'T' && line[0] != 'D' && line[0] != 'L') {
                float r,g,b; if (std::sscanf(line.c_str(), "%f %f %f", &r,&g,&b) == 3)
                    values.push_back(simd_float3{r,g,b});
            }
        }
        return size >= 2 && values.size() == size_t(size)*size*size;
    }

    simd_float3 sample(simd_float3 v) const {
        v = simd_clamp(v, simd_float3{0,0,0}, simd_float3{1,1,1}) * float(size-1);
        uint32_t x0=uint32_t(std::floor(v.x)), y0=uint32_t(std::floor(v.y)), z0=uint32_t(std::floor(v.z));
        uint32_t x1=std::min(x0+1,size-1), y1=std::min(y0+1,size-1), z1=std::min(z0+1,size-1);
        float fx=v.x-x0, fy=v.y-y0, fz=v.z-z0;
        auto at = [&](uint32_t x,uint32_t y,uint32_t z) { return values[(size_t(z)*size+y)*size+x]; };
        simd_float3 c00=at(x0,y0,z0)*(1-fx)+at(x1,y0,z0)*fx;
        simd_float3 c10=at(x0,y1,z0)*(1-fx)+at(x1,y1,z0)*fx;
        simd_float3 c01=at(x0,y0,z1)*(1-fx)+at(x1,y0,z1)*fx;
        simd_float3 c11=at(x0,y1,z1)*(1-fx)+at(x1,y1,z1)*fx;
        return (c00*(1-fy)+c10*fy)*(1-fz) + (c01*(1-fy)+c11*fy)*fz;
    }
};

static std::vector<simd_float4> render(LDBOpticsEngine& engine, id<MTLDevice> device,
                                       id<MTLCommandQueue> queue, const std::vector<simd_float4>& input,
                                       uint32_t width, uint32_t height, const LDBOpticsParameters& parameters) {
    std::vector<simd_float4> output;
    @autoreleasepool {
        NSUInteger bytes = input.size() * sizeof(simd_float4);
        id<MTLBuffer> src = [device newBufferWithBytes:input.data() length:bytes options:MTLResourceStorageModeShared];
        id<MTLBuffer> dst = [device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> command = [queue commandBuffer];
        engine.encode(command, src, dst, width, height, parameters);
        [command commit];
        [command waitUntilCompleted];
        simd_float4* values = static_cast<simd_float4*>(dst.contents);
        output.assign(values, values + input.size());
    }
    return output;
}

static bool writeTIFF(const std::string& path, const std::vector<simd_float4>& pixels,
                      uint32_t width, uint32_t height, bool tagRec709 = false) {
    std::vector<uint16_t> rgb16(pixels.size() * 3);
    for (size_t i = 0; i < pixels.size(); ++i) {
        simd_float3 rgb = simd_clamp(simd_float3{pixels[i].x, pixels[i].y, pixels[i].z},
                                     simd_float3{0,0,0}, simd_float3{1,1,1});
        rgb16[i * 3 + 0] = uint16_t(std::round(rgb.x * 65535));
        rgb16[i * 3 + 1] = uint16_t(std::round(rgb.y * 65535));
        rgb16[i * 3 + 2] = uint16_t(std::round(rgb.z * 65535));
    }

    // Minimal little-endian, single-strip, uncompressed 16-bit RGB TIFF.
    std::vector<uint8_t> icc;
    if (tagRec709) {
        std::ifstream profile("/System/Library/ColorSync/Profiles/ITU-709.icc", std::ios::binary);
        icc.assign(std::istreambuf_iterator<char>(profile), std::istreambuf_iterator<char>());
    }
    const uint16_t entryCount = icc.empty() ? 10 : 11;
    constexpr uint32_t ifdOffset = 8;
    const uint32_t ifdBytes = 2 + entryCount * 12 + 4;
    const uint32_t bitsOffset = ifdOffset + ifdBytes;
    const uint32_t sampleFormatOffset = bitsOffset + 6;
    const uint32_t iccOffset = sampleFormatOffset + 6;
    const uint32_t pixelOffset = icc.empty() ? iccOffset : iccOffset + uint32_t(icc.size()) + uint32_t(icc.size() & 1);
    const uint32_t pixelBytes = width * height * 3 * sizeof(uint16_t);
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) return false;
    auto u16 = [&](uint16_t v) { out.put(char(v & 255)); out.put(char(v >> 8)); };
    auto u32 = [&](uint32_t v) { u16(uint16_t(v)); u16(uint16_t(v >> 16)); };
    auto entry = [&](uint16_t tag, uint16_t type, uint32_t count, uint32_t value) {
        u16(tag); u16(type); u32(count); u32(value);
    };
    out.write("II", 2); u16(42); u32(ifdOffset); u16(entryCount);
    entry(256, 4, 1, width);                  // ImageWidth
    entry(257, 4, 1, height);                 // ImageLength
    entry(258, 3, 3, bitsOffset);             // BitsPerSample
    entry(259, 3, 1, 1);                      // Compression: none
    entry(262, 3, 1, 2);                      // Photometric: RGB
    entry(273, 4, 1, pixelOffset);             // StripOffsets
    entry(277, 3, 1, 3);                      // SamplesPerPixel
    entry(278, 4, 1, height);                 // RowsPerStrip
    entry(279, 4, 1, pixelBytes);              // StripByteCounts
    entry(339, 3, 3, sampleFormatOffset);      // SampleFormat: unsigned integer
    if (!icc.empty()) entry(34675, 7, uint32_t(icc.size()), iccOffset); // ICC profile
    u32(0);
    u16(16); u16(16); u16(16);
    u16(1); u16(1); u16(1);
    if (!icc.empty()) {
        out.write(reinterpret_cast<const char*>(icc.data()), std::streamsize(icc.size()));
        if (icc.size() & 1) out.put(0);
    }
    out.write(reinterpret_cast<const char*>(rgb16.data()), pixelBytes);
    return bool(out);
}

static std::vector<simd_float4> convertEncoding(const std::vector<simd_float4>& pixels,
                                                 uint32_t space, bool encode) {
    std::vector<simd_float4> result = pixels;
    for (auto& p : result) {
        simd_float3 rgb = encode ? LDBColorReference::encode({p.x, p.y, p.z}, space)
                                 : LDBColorReference::decode({p.x, p.y, p.z}, space);
        p.x = rgb.x; p.y = rgb.y; p.z = rgb.z;
    }
    return result;
}

static std::vector<simd_float4> displayPreview(const std::vector<simd_float4>& ap1) {
    const LDBColorReference::Matrix3 ap1ToSRGB = {{{1.7048586763f,-.6217160219f,-.0831426544f},
        {-.1300768242f,1.1407357748f,-.0106589502f},{-.0239640729f,-.1289755083f,1.1529395812f}}};
    std::vector<simd_float4> result = ap1;
    for (auto& p : result) {
        simd_float3 v = simd_max(LDBColorReference::apply(ap1ToSRGB, {p.x, p.y, p.z}), simd_float3{0,0,0});
        v = v / (simd_float3{1,1,1} + v); // stable inspection rendering, not a plugin output transform
        p.x = v.x <= .0031308f ? 12.92f*v.x : 1.055f*std::pow(v.x,1/2.4f)-.055f;
        p.y = v.y <= .0031308f ? 12.92f*v.y : 1.055f*std::pow(v.y,1/2.4f)-.055f;
        p.z = v.z <= .0031308f ? 12.92f*v.z : 1.055f*std::pow(v.z,1/2.4f)-.055f;
    }
    return result;
}

static std::vector<simd_float4> rec709Gamma24FromWorkingSpace(const std::vector<simd_float4>& encoded,
                                                              uint32_t workingColorSpace) {
    auto ap1 = convertEncoding(encoded, workingColorSpace, false);
    const LDBColorReference::Matrix3 ap1ToRec709 = {{{1.705050993f,-.621792121f,-.083258872f},
        {-.130256418f,1.140804736f,-.010548318f},{-.024003356f,-.128968977f,1.152972333f}}};
    for (auto& p : ap1) {
        simd_float3 rgb = simd_max(LDBColorReference::apply(ap1ToRec709, {p.x,p.y,p.z}),
                                   simd_float3{0,0,0});
        // Rec.709 scene-to-display OOTF (system gamma 1.2), followed by the
        // reference display's 2.4 EOTF encoding. This maps 18% near 42% signal.
        rgb = {std::pow(rgb.x,1.2f),std::pow(rgb.y,1.2f),std::pow(rgb.z,1.2f)};
        rgb = simd_clamp(rgb, simd_float3{0,0,0}, simd_float3{1,1,1});
        p = {std::pow(rgb.x, 1.0f/2.4f), std::pow(rgb.y, 1.0f/2.4f),
             std::pow(rgb.z, 1.0f/2.4f), p.w};
    }
    return ap1;
}

static std::vector<simd_float4> applyDisplayLUT(const std::vector<simd_float4>& encoded,
                                                const CubeLUT& lut) {
    std::vector<simd_float4> result = encoded;
    for (auto& p : result) {
        simd_float3 rgb = lut.sample({p.x,p.y,p.z});
        p = {rgb.x,rgb.y,rgb.z,p.w};
    }
    return result;
}

static bool rec709NeutralChannelRegression() {
    std::vector<simd_float4> ap1 = {simd_float4{.18f,.18f,.18f,1},
                                    simd_float4{.5f,.5f,.5f,1}};
    for (uint32_t space : {uint32_t(LDBWorkingColorSpaceDaVinciIntermediate),
                           uint32_t(LDBWorkingColorSpaceARRILogC4)}) {
        auto encoded = convertEncoding(ap1, space, true);
        auto display = rec709Gamma24FromWorkingSpace(encoded, space);
        for (const auto& p : display) {
            if (std::abs(p.x-p.y) > 1e-5f || std::abs(p.y-p.z) > 1e-5f ||
                p.x <= 0 || p.y <= 0 || p.z <= 0) return false;
        }
    }
    return true;
}

static float maxRGBDifference(const std::vector<simd_float4>& a, const std::vector<simd_float4>& b) {
    float maximum = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        simd_float3 d = simd_abs(simd_float3{a[i].x, a[i].y, a[i].z}
                               - simd_float3{b[i].x, b[i].y, b[i].z});
        maximum = std::max(maximum, std::max(d.x, std::max(d.y, d.z)));
    }
    return maximum;
}

static LDBOpticsParameters loadCookeFlareCalibration(const std::string& path,
                                                      uint32_t width,
                                                      uint32_t height) {
    auto p=LDBNeutralOpticsParameters(width,height);
    std::ifstream stream(path);
    if(!stream) { std::fprintf(stderr,"FAIL: unable to read %s\n",path.c_str()); std::exit(16); }
    std::string line;
    while(std::getline(stream,line)) {
        if(line.empty()||line[0]=='#')continue;
        auto separator=line.find('=');
        if(separator==std::string::npos)continue;
        auto key=line.substr(0,separator);
        if(key=="LensDebaserPreset")continue;
        float value=std::stof(line.substr(separator+1));
#define LDB_LOAD_FLOAT(name, member) if(key==name){p.member=value;continue;}
        LDB_LOAD_FLOAT("captureFocalLength",captureFocalLength)
        LDB_LOAD_FLOAT("anamorphicSqueeze",anamorphicSqueeze)
        LDB_LOAD_FLOAT("anamorphicFlareAmount",anamorphicFlareAmount)
        LDB_LOAD_FLOAT("anamorphicFlareRadius",anamorphicFlareRadius)
        LDB_LOAD_FLOAT("anamorphicFlareThreshold",anamorphicFlareThreshold)
        LDB_LOAD_FLOAT("anamorphicFlareThickness",anamorphicFlareThickness)
        LDB_LOAD_FLOAT("anamorphicFlareCoreAmount",anamorphicFlareCoreAmount)
        LDB_LOAD_FLOAT("anamorphicFlareAsymmetry",anamorphicFlareAsymmetry)
        LDB_LOAD_FLOAT("anamorphicFlareGhostAmount",anamorphicFlareGhostAmount)
        LDB_LOAD_FLOAT("anamorphicFlareGhostPosition",anamorphicFlareGhostPosition)
        LDB_LOAD_FLOAT("anamorphicFlareGhostScale",anamorphicFlareGhostScale)
        LDB_LOAD_FLOAT("anamorphicFlareGhostCount",anamorphicFlareGhostCount)
        LDB_LOAD_FLOAT("anamorphicFlareGhostSpacing",anamorphicFlareGhostSpacing)
        LDB_LOAD_FLOAT("anamorphicFlareGhostScaleDecay",anamorphicFlareGhostScaleDecay)
        LDB_LOAD_FLOAT("anamorphicFlareGhostEnergyDecay",anamorphicFlareGhostEnergyDecay)
        LDB_LOAD_FLOAT("anamorphicFlareBandAmount",anamorphicFlareBandAmount)
        LDB_LOAD_FLOAT("anamorphicFlareBandSeparation",anamorphicFlareBandSeparation)
        LDB_LOAD_FLOAT("anamorphicFlareSecondaryAmount",anamorphicFlareSecondaryAmount)
        LDB_LOAD_FLOAT("anamorphicFlareSecondaryOffset",anamorphicFlareSecondaryOffset)
        LDB_LOAD_FLOAT("diffractionRayAmount",diffractionRayAmount)
        LDB_LOAD_FLOAT("diffractionRayLength",diffractionRayLength)
        LDB_LOAD_FLOAT("glareEnergy",glareEnergy)
        LDB_LOAD_FLOAT("glareThreshold",glareThreshold)
        LDB_LOAD_FLOAT("glareRadius",glareRadius)
        LDB_LOAD_FLOAT("glareColorAmount",glareColorAmount)
        LDB_LOAD_FLOAT("bloomEnergy",bloomEnergy)
        LDB_LOAD_FLOAT("bloomThreshold",bloomThreshold)
        LDB_LOAD_FLOAT("bloomRadius",bloomRadius)
#undef LDB_LOAD_FLOAT
        if(key=="anamorphicFlareR")p.anamorphicFlareColor.x=value;
        else if(key=="anamorphicFlareG")p.anamorphicFlareColor.y=value;
        else if(key=="anamorphicFlareB")p.anamorphicFlareColor.z=value;
        else if(key=="anamorphicFlareGhostR")p.anamorphicFlareGhostColor.x=value;
        else if(key=="anamorphicFlareGhostG")p.anamorphicFlareGhostColor.y=value;
        else if(key=="anamorphicFlareGhostB")p.anamorphicFlareGhostColor.z=value;
        else if(key=="glareR")p.glareColor.x=value;
        else if(key=="glareG")p.glareColor.y=value;
        else if(key=="glareB")p.glareColor.z=value;
    }
    return p;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 4 || argc > 11) return 2;
        constexpr uint32_t width = 1920, height = 1080;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            fprintf(stderr, "ERROR: No Metal device is available for visual validation.\n");
            return 3;
        }
        if (!rec709NeutralChannelRegression()) {
            std::fprintf(stderr, "FAIL: Rec.709 Gamma 2.4 neutral-channel regression\n");
            return 14;
        }
        LDBOpticsEngine engine(device, [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]);
        if (!engine.valid()) return 4;
        id<MTLCommandQueue> queue = [device newCommandQueue];
        auto input = makeChart(width, height); // scene-linear AP1 reference chart
        std::string directory = argv[2];
        // Pass 60 starts the coherent-source analytic-flare validation series.
        // Continue executing the established validation calculations, but do
        // not republish hundreds of unrelated legacy review renders beside the
        // focused new outputs.
        const int passNumber=argc>=9?std::atoi(argv[7]):0;
        const bool baselineRebuild=passNumber<0;
        const int reviewOutputFloor=passNumber>=99?491:(passNumber>=98?486:(passNumber>=97?479:(passNumber>=96?472:(passNumber>=94?455:(passNumber>=93?447:(passNumber>=92?439:(passNumber>=85?384:(passNumber>=84?379:(passNumber>=83?374:(passNumber>=82?368:(passNumber>=81?357:(passNumber>=80?350:(passNumber>=79?339:(passNumber>=77?325:(passNumber>=76?317:(passNumber>=68?310:(passNumber>=67?302:(passNumber>=66?293:(passNumber>=65?281:(passNumber>=64?273:(passNumber>=63?268:(passNumber>=62?263:(passNumber>=61?258:(passNumber>=60?252:0))))))))))))))))))))))));
        const std::unordered_set<std::string> baselineOutputs = {
            // Neutral inputs and the principal optical families.
            "00-input.tiff", "01-modern.tiff", "02-vintage.tiff", "03-anamorphic.tiff",
            "10-uniform-input.tiff", "11-vignette-natural.tiff", "12-vignette-optical.tiff",
            "13-vignette-mechanical.tiff", "20-polar-input.tiff",
            "21-polar-directional-focus.tiff", "22-polar-ca-swirl.tiff",
            "23-polar-detail-boost.tiff", "24-polar-detail-vintage.tiff",
            "25-polar-longitudinal-ca.tiff", "26-polar-field-gated-geometry.tiff",
            "27-polar-peripheral-stretch-only.tiff", "28-polar-peripheral-warp-only.tiff",
            "29-polar-refractive-irregularity.tiff", "29b-polar-refractive-dispersion.tiff",
            // Highlight transfer and aberration primitives.
            "30-hdr-sources-input.tiff", "31-hdr-bloom.tiff", "32-hdr-glare.tiff",
            "33-hdr-anamorphic.tiff", "34-hdr-coma.tiff", "35-hdr-spherical-halo.tiff",
            "36-hdr-coma-halo.tiff",
            // Resolution and real-camera colour-pipeline checks.
            "40-iso12233-input.tiff", "41-iso12233-modern.tiff", "42-iso12233-vintage.tiff",
            "43-iso12233-directional-focus.tiff", "44-iso12233-ca-swirl.tiff",
            "50-iphone-dwg-neutral-rec709-g24.tiff", "52-iphone-vintage-rec709-g24.tiff",
            "60-arri-logc4-neutral-rec709-g24.tiff", "62-arri-vintage-rec709-g24.tiff",
            "64-final-arri-bodycam-optical-field-rec709-g24.tiff",
            // Current aperture, depth and bokeh behavior.
            "70-aperture-chart-input.tiff", "71-aperture-chart-circular.tiff",
            "72-aperture-chart-polygon.tiff", "73-aperture-chart-oval.tiff",
            "74-aperture-chart-cat-eye.tiff", "76-aperture-extreme-filled-cat-eye.tiff",
            "77-aperture-depth-focus-mid.tiff", "78-aperture-depth-focus-near.tiff",
            "79-depth-boundaries-input.tiff", "80-depth-boundaries-map.tiff",
            "81-depth-boundaries-focus-near.tiff", "82-depth-boundaries-focus-rails.tiff",
            "83-depth-boundaries-focus-far.tiff", "84-depth-boundaries-bloom-depth-free.tiff",
            "85-depth-boundaries-bloom-occluded.tiff", "86-depth-boundaries-glare-occluded.tiff",
            "87-depth-boundaries-scatter-diagnostic.tiff",
            "88-focus-transitions-depth-spherical-halo.tiff",
            "89-focus-transitions-depth-spherical-halo-near.tiff",
            "90-aperture-bokeh-swirl.tiff", "91-aperture-bokeh-swirl-elliptical.tiff",
            "93-depth-boundaries-defocus-diagnostic.tiff",
            "94-depth-boundaries-rejection-diagnostic.tiff",
            // Internal contamination remains supported; front-element dirt does not.
            "112-hdr-internal-cloud-control.tiff", "113-chart-internal-cloud-control.tiff",
            "115-arri-internal-dirt-rec709-g24.tiff",
            "117-hdr-internal-contamination-with-bloom-glare.tiff",
            "118-depth-internal-contamination-with-focus-protection.tiff",
            // Lens references and current pupil behavior.
            "164-hawk-55mm-t22-reference.tiff", "165-hawk-bokeh-chart-source.tiff",
            "166-hawk-bokeh-vertical-oval-baseline.tiff", "167-hawk-bokeh-restrained-cat-eye.tiff",
            "168-hawk-bokeh-restrained-cat-eye-rotation.tiff",
            "198-cooke-special-50mm-t23-reference.tiff", "199-cooke-special-bokeh-chart-source.tiff",
            "200-cooke-special-filled-oval-baseline.tiff", "201-cooke-special-visible-cat-eye.tiff",
            "202-cooke-special-clean-character-transfer.tiff",
            // New coherent-source model and current profile compiler outputs.
            "252-analytic-flare-source.tiff", "253-analytic-broad-streak.tiff",
            "254-cooke-analytic-medium.tiff", "255-analytic-ghost-primitive.tiff",
            "256-complex-practicals-source-rejection.tiff", "257-cooke-close-focus-bokeh.tiff",
            "268-cooke-path-calibration-source.tiff", "269-cooke-path-calibration-32mm.tiff",
            "270-cooke-path-calibration-50mm.tiff", "271-cooke-path-calibration-75mm.tiff",
            "272-cooke-path-calibration-100mm.tiff"
        };
        auto publishOutput = [&](const std::string& name) {
            if (!baselineRebuild) return true;
            if (name.rfind("75-aperture-polygon-", 0) == 0) return true;
            return baselineOutputs.count(name) != 0;
        };
        if (argc >= 9) {
            const std::string passID = argv[7];
            const std::string passLabel = argv[8];
            const std::string markerPath = directory + "/VISUAL-PASS-" + passID + ".txt";
            std::ofstream marker(markerPath);
            if (!marker) {
                std::fprintf(stderr, "FAIL: unable to write %s\n", markerPath.c_str());
                return 15;
            }
            marker << passLabel << "\n"
                   << "All TIFF files in this folder were generated by this pass.\n"
                   << "Primary review files:\n";
            if(baselineRebuild) marker
                   << "  Curated current-architecture regression catalogue\n"
                   << "  Current analytic flare primitives: 252-257\n"
                   << "  Current Cooke focal profile calibration: 268-272\n"
                   << "  Retired and superseded development renders are intentionally omitted.\n";
            else if(passNumber>=99) marker
                   << "  491-bokeh-swirl-range-source.tiff\n"
                   << "  492-bokeh-swirl-00.tiff\n"
                   << "  493-bokeh-swirl-03.tiff\n"
                   << "  494-bokeh-swirl-06.tiff\n"
                   << "  495-bokeh-swirl-09.tiff\n"
                   << "  496-bokeh-swirl-12.tiff\n";
            else if(passNumber>=98) marker
                   << "  486-bokeh-boundary-chart-source.tiff\n"
                   << "  487-demo-bokeh-swirl-strengthened.tiff\n"
                   << "  488-maximum-bokeh-boundary-stress.tiff\n"
                   << "  489-bokeh-boundary-real-source.tiff\n"
                   << "  490-demo-bokeh-swirl-real.tiff\n";
            else if(passNumber>=97) marker
                   << "  479-expanded-aperture-chart-source.tiff\n"
                   << "  480-former-aperture-range-ceiling.tiff\n"
                   << "  481-extended-aperture-range-ceiling.tiff\n"
                   << "  482-demo-bokeh-swirl-revised.tiff\n"
                   << "  483-demo-petzval-field-revised.tiff\n"
                   << "  484-expanded-aperture-real-source.tiff\n"
                   << "  485-expanded-aperture-real-result.tiff\n";
            else if(passNumber>=96) marker
                   << "  472-causal-optical-chart-source.tiff\n"
                   << "  473-continuous-field-blur.tiff\n"
                   << "  474-chromatic-after-field-blur.tiff\n"
                   << "  475-shaped-aperture-after-field-blur.tiff\n"
                   << "  476-combined-causal-optics.tiff\n"
                   << "  477-causal-optical-real-source.tiff\n"
                   << "  478-combined-causal-optics-real.tiff\n";
            else if(passNumber>=95) marker
                   << "  463-prism-distribution-chart-source.tiff\n"
                   << "  464-prism-linear-edge.tiff\n"
                   << "  465-prism-uniform.tiff\n"
                   << "  466-prism-bilateral-field.tiff\n"
                   << "  467-prism-radial-field.tiff\n"
                   << "  468-prism-inverse-field.tiff\n"
                   << "  469-peripheral-prism-defocus-chart.tiff\n"
                   << "  470-peripheral-prism-defocus-real-source.tiff\n"
                   << "  471-peripheral-prism-defocus-real.tiff\n";
            else if(passNumber>=94) marker
                   << "  455-glare-halo-chart-source.tiff\n"
                   << "  456-glare-halo-hdr-source.tiff\n"
                   << "  457-demo-glare-and-halo-chart.tiff\n"
                   << "  458-demo-glare-and-halo-hdr.tiff\n"
                   << "  459-glare-only-scatter.tiff\n"
                   << "  460-halo-only-scatter.tiff\n"
                   << "  461-demo-highlight-response-chart.tiff\n"
                   << "  462-independent-bloom-glare-wear.tiff\n";
            else if(passNumber>=93) marker
                   << "  447-glare-halo-chart-source.tiff\n"
                   << "  448-glare-halo-hdr-source.tiff\n"
                   << "  449-demo-glare-and-halo-chart.tiff\n"
                   << "  450-demo-glare-and-halo-hdr.tiff\n"
                   << "  451-glare-only-scatter.tiff\n"
                   << "  452-halo-only-scatter.tiff\n"
                   << "  453-demo-highlight-response-chart.tiff\n"
                   << "  454-independent-bloom-glare-wear.tiff\n";
            else if(passNumber>=92) marker
                   << "  439-glare-halo-chart-source.tiff\n"
                   << "  440-glare-halo-hdr-source.tiff\n"
                   << "  441-demo-glare-and-halo-chart.tiff\n"
                   << "  442-demo-glare-and-halo-hdr.tiff\n"
                   << "  443-glare-only-scatter.tiff\n"
                   << "  444-halo-only-scatter.tiff\n"
                   << "  445-demo-highlight-response-chart.tiff\n"
                   << "  446-independent-bloom-glare-wear.tiff\n";
            else if(passNumber>=91) marker
                   << "  429-front-wear-chart-source.tiff\n"
                   << "  430-front-wear-haze-isolated.tiff\n"
                   << "  431-front-wear-cleaning-marks-isolated.tiff\n"
                   << "  432-front-wear-scratches-isolated.tiff\n"
                   << "  433-front-wear-coating-isolated.tiff\n"
                   << "  434-front-wear-combined-moderate.tiff\n"
                   << "  435-front-wear-combined-strong.tiff\n"
                   << "  436-front-wear-real-source.tiff\n"
                   << "  437-front-wear-real-combined-moderate.tiff\n"
                   << "  438-front-wear-real-combined-strong.tiff\n";
            else if(passNumber>=90) marker
                   << "  419-front-wear-chart-source.tiff\n"
                   << "  420-front-wear-haze-isolated.tiff\n"
                   << "  421-front-wear-cleaning-marks-isolated.tiff\n"
                   << "  422-front-wear-scratches-isolated.tiff\n"
                   << "  423-front-wear-coating-isolated.tiff\n"
                   << "  424-front-wear-combined-moderate.tiff\n"
                   << "  425-front-wear-combined-strong.tiff\n"
                   << "  426-front-wear-real-source.tiff\n"
                   << "  427-front-wear-real-combined-moderate.tiff\n"
                   << "  428-front-wear-real-combined-strong.tiff\n";
            else if(passNumber>=89) marker
                   << "  409-front-wear-chart-source.tiff\n"
                   << "  410-front-wear-haze-isolated.tiff\n"
                   << "  411-front-wear-cleaning-marks-isolated.tiff\n"
                   << "  412-front-wear-scratches-isolated.tiff\n"
                   << "  413-front-wear-coating-isolated.tiff\n"
                   << "  414-front-wear-combined-moderate.tiff\n"
                   << "  415-front-wear-combined-strong.tiff\n"
                   << "  416-front-wear-real-source.tiff\n"
                   << "  417-front-wear-real-combined-moderate.tiff\n"
                   << "  418-front-wear-real-combined-strong.tiff\n";
            else if(passNumber>=88) marker
                   << "  401-internal-strength-chart-source.tiff\n"
                   << "  402-internal-strength-amount-2-5.tiff\n"
                   << "  403-internal-strength-amount-4.tiff\n"
                   << "  404-internal-strength-amount-6.tiff\n"
                   << "  405-internal-strength-real-source.tiff\n"
                   << "  406-internal-strength-real-amount-2-5.tiff\n"
                   << "  407-internal-strength-real-amount-4.tiff\n"
                   << "  408-internal-strength-real-amount-6.tiff\n";
            else if(passNumber>=87) marker
                   << "  397-internal-contamination-chart-source.tiff\n"
                   << "  398-internal-contamination-localized.tiff\n"
                   << "  399-internal-contamination-real-source.tiff\n"
                   << "  400-internal-contamination-real-localized.tiff\n";
            else if(passNumber>=86) marker
                   << "  389-highlight-wear-chart-source.tiff\n"
                   << "  390-highlight-response-shadow-safe.tiff\n"
                   << "  391-front-element-wear-retuned.tiff\n"
                   << "  392-internal-contamination-retuned.tiff\n"
                   << "  393-highlight-wear-real-source.tiff\n"
                   << "  394-highlight-response-real-shadow-safe.tiff\n"
                   << "  395-front-element-wear-real-retuned.tiff\n"
                   << "  396-internal-contamination-real-retuned.tiff\n";
            else if(passNumber>=85) marker
                   << "  384-prism-chart-source.tiff\n"
                   << "  385-prism-conservative-inward.tiff\n"
                   << "  386-prism-medium-inward.tiff\n"
                   << "  387-prism-extreme-inward.tiff\n"
                   << "  388-prism-opposite-direction-inward.tiff\n";
            else if(passNumber>=84) marker
                   << "  379-prism-chart-source.tiff\n"
                   << "  380-prism-conservative.tiff\n"
                   << "  381-prism-medium.tiff\n"
                   << "  382-prism-extreme.tiff\n"
                   << "  383-prism-opposite-direction.tiff\n";
            else if(passNumber>=83) marker
                   << "  374-bubble-bokeh-point-source.tiff\n"
                   << "  375-filled-pupil-reference.tiff\n"
                   << "  376-demo-bubble-rim-filled-final.tiff\n"
                   << "  377-bubble-bokeh-triplet-medium.tiff\n"
                   << "  378-bubble-bokeh-triplet-caricature.tiff\n";
            else if(passNumber>=82) marker
                   << "  368-integrated-night-scope-source.tiff\n"
                   << "  369-corrected-pupil-source.tiff\n"
                   << "  370-demo-pupil-decenter-clipping-corrected.tiff\n"
                   << "  371-demo-bubble-rim-filled-corrected.tiff\n"
                   << "  372-prismatic-night-scope-medium-integrated.tiff\n"
                   << "  373-prismatic-night-scope-caricature-integrated.tiff\n";
            else if(passNumber>=81) marker
                   << "  357-compact-flare-source.tiff\n"
                   << "  358-demo-structured-anamorphic-flare.tiff\n"
                   << "  359-demo-diffraction-rays.tiff\n"
                   << "  360-isolated-pupil-source.tiff\n"
                   << "  361-demo-pupil-decenter-clipping.tiff\n"
                   << "  362-demo-bubble-rim-bokeh.tiff\n"
                   << "  363-real-footage-source.tiff\n"
                   << "  364-decentered-dream-glass-medium.tiff\n"
                   << "  365-decentered-dream-glass-caricature.tiff\n"
                   << "  366-prismatic-night-scope-medium.tiff\n"
                   << "  367-prismatic-night-scope-caricature.tiff\n";
            else if(passNumber>=80) marker
                   << "  350-bokeh-petzval-point-source.tiff\n"
                   << "  351-bokeh-swirl-conservative-filled.tiff\n"
                   << "  352-bokeh-swirl-medium-filled.tiff\n"
                   << "  353-bokeh-swirl-extreme-filled.tiff\n"
                   << "  354-petzval-pupil-conservative-filled.tiff\n"
                   << "  355-petzval-pupil-medium-filled.tiff\n"
                   << "  356-petzval-pupil-extreme-filled.tiff\n";
            else if(passNumber>=79) marker
                   << "  339-bokeh-petzval-point-source.tiff\n"
                   << "  340-bokeh-swirl-conservative.tiff\n"
                   << "  341-bokeh-swirl-medium.tiff\n"
                   << "  342-bokeh-swirl-extreme.tiff\n"
                   << "  343-petzval-pupil-conservative.tiff\n"
                   << "  344-petzval-pupil-medium.tiff\n"
                   << "  345-petzval-pupil-extreme.tiff\n"
                   << "  346-petzval-iso-source.tiff\n"
                   << "  347-petzval-field-conservative-iso.tiff\n"
                   << "  348-petzval-field-medium-iso.tiff\n"
                   << "  349-petzval-field-extreme-iso.tiff\n";
            else if(passNumber>=77) marker
                   << "  325-stage-depth-alignment-source.tiff\n"
                   << "  326-stage-depth-alignment-map.tiff\n"
                   << "  327-stage-depth-free-aperture.tiff\n"
                   << "  328-stage-depth-aware-aperture.tiff\n"
                   << "  329-stage-depth-free-scatter.tiff\n"
                   << "  330-stage-depth-aware-scatter.tiff\n"
                   << "  331-preset-golden-portrait-real-source.tiff\n"
                   << "  332-preset-golden-portrait-subtle-real.tiff\n"
                   << "  333-preset-golden-portrait-medium-real.tiff\n"
                   << "  334-preset-golden-portrait-caricature-real.tiff\n"
                   << "  335-preset-close-focus-macro-iso-source.tiff\n"
                   << "  336-preset-close-focus-macro-subtle-iso.tiff\n"
                   << "  337-preset-close-focus-macro-medium-iso.tiff\n"
                   << "  338-preset-close-focus-macro-caricature-iso.tiff\n";
            else if(passNumber>=76) marker
                   << "  317-cloud-amount-uniform-source.tiff\n"
                   << "  318-cloud-amount-conservative.tiff\n"
                   << "  319-cloud-amount-medium.tiff\n"
                   << "  320-cloud-amount-extreme.tiff\n"
                   << "  321-cloud-amount-real-source.tiff\n"
                   << "  322-cloud-amount-real-conservative.tiff\n"
                   << "  323-cloud-amount-real-medium.tiff\n"
                   << "  324-cloud-amount-real-extreme.tiff\n";
            else if(passNumber>=68) marker
                   << "  310-cloud-density-source.tiff\n"
                   << "  311-cloud-density-broad.tiff\n"
                   << "  312-cloud-density-complex.tiff\n"
                   << "  313-cloud-density-diagnostic.tiff\n"
                   << "  314-cloud-real-source.tiff\n"
                   << "  315-cloud-real-smooth-broad.tiff\n"
                   << "  316-cloud-real-smooth-complex.tiff\n";
            else if(passNumber>=67) marker
                   << "  302-cloud-density-broad-continuous.tiff\n"
                   << "  303-cloud-density-complex-continuous.tiff\n"
                   << "  304-cloud-hdr-source.tiff\n"
                   << "  305-cloud-hdr-broad-veil.tiff\n"
                   << "  306-cloud-hdr-complex-veil.tiff\n"
                   << "  307-cloud-real-source.tiff\n"
                   << "  308-cloud-real-broad-veil.tiff\n"
                   << "  309-cloud-real-complex-veil.tiff\n";
            else if(passNumber>=66) marker
                   << "  293-cloud-density-broad-diagnostic.tiff\n"
                   << "  294-cloud-density-multiscale-diagnostic.tiff\n"
                   << "  295-cloud-hdr-broad-veil.tiff\n"
                   << "  296-cloud-hdr-multiscale-veil.tiff\n"
                   << "  297-pupil-rim-source.tiff\n"
                   << "  298-pupil-rim-moderate.tiff\n"
                   << "  299-pupil-rim-strong.tiff\n"
                   << "  300-cloud-real-source.tiff\n"
                   << "  301-cloud-real-multiscale.tiff\n";
            else if(passNumber>=65) marker
                   << "  281-cloud-uniform-source.tiff\n"
                   << "  282-cloud-uniform-transmission.tiff\n"
                   << "  283-cloud-density-amplified-diagnostic.tiff\n"
                   << "  284-cloud-hdr-source.tiff\n"
                   << "  285-cloud-hdr-base-veil.tiff\n"
                   << "  286-cloud-hdr-soft-multiscale-veil.tiff\n"
                   << "  287-pupil-isolated-points-source.tiff\n"
                   << "  288-pupil-isolated-symmetric.tiff\n"
                   << "  289-pupil-isolated-shift-clip.tiff\n"
                   << "  290-pupil-isolated-rim-energy.tiff\n"
                   << "  291-cloud-real-source.tiff\n"
                   << "  292-cloud-real-soft-multiscale.tiff\n";
            else if(passNumber>=64) marker
                   << "  273-pupil-model-source.tiff\n"
                   << "  274-pupil-model-symmetric.tiff\n"
                   << "  275-pupil-model-shift-clip.tiff\n"
                   << "  276-pupil-model-rim-energy.tiff\n"
                   << "  277-cloud-model-source.tiff\n"
                   << "  278-cloud-model-base.tiff\n"
                   << "  279-cloud-model-soft.tiff\n"
                   << "  280-cloud-model-multiscale.tiff\n";
            else if(passNumber>=63) marker
                   << "  268-cooke-path-calibration-source.tiff\n"
                   << "  269-cooke-path-calibration-32mm.tiff\n"
                   << "  270-cooke-path-calibration-50mm.tiff\n"
                   << "  271-cooke-path-calibration-75mm.tiff\n"
                   << "  272-cooke-path-calibration-100mm.tiff\n";
            else if(passNumber>=62) marker
                   << "  263-cooke-reflection-train-source.tiff\n"
                   << "  264-cooke-reflection-train-32mm.tiff\n"
                   << "  265-cooke-reflection-train-50mm.tiff\n"
                   << "  266-cooke-reflection-train-75mm.tiff\n"
                   << "  267-cooke-reflection-train-100mm.tiff\n";
            else if(passNumber>=61) marker
                   << "  258-cooke-focal-calibration-source.tiff\n"
                   << "  259-cooke-profile-32mm.tiff\n"
                   << "  260-cooke-profile-50mm.tiff\n"
                   << "  261-cooke-profile-75mm.tiff\n"
                   << "  262-cooke-profile-100mm.tiff\n";
            else marker
                   << "  252-analytic-flare-source.tiff\n"
                   << "  253-analytic-broad-streak.tiff\n"
                   << "  254-cooke-analytic-medium.tiff\n"
                   << "  255-analytic-ghost-primitive.tiff\n"
                   << "  256-complex-practicals-source-rejection.tiff\n"
                   << "  257-cooke-close-focus-bokeh.tiff\n";
        }
        auto save = [&](const std::string& name, const std::vector<simd_float4>& pixels) {
            if(!publishOutput(name)) return;
            if(reviewOutputFloor>0&&std::atoi(name.c_str())<reviewOutputFloor)
                return;
            std::string path = directory + "/" + name;
            if (!writeTIFF(path, pixels, width, height)) {
                std::fprintf(stderr, "FAIL: unable to write %s\n", path.c_str());
                std::exit(7);
            }
        };
        auto inputPreview = displayPreview(input);
        simd_float4 neutralProbe = inputPreview[10 * width + 10];
        if (!(neutralProbe.x > 0 && neutralProbe.y > 0 && neutralProbe.z > 0)) {
            std::fprintf(stderr, "FAIL: display preview lost one or more RGB channels\n");
            return 6;
        }
        save("00-input.tiff", inputPreview);

        auto modern = LDBNeutralOpticsParameters(width, height);
        modern.distortionK1 = -0.015f; modern.cornerSharpnessLoss = .12f; modern.vignetteNatural = 0.08f;
        save("01-modern.tiff", displayPreview(render(engine, device, queue, input, width, height, modern)));

        auto vintage = LDBNeutralOpticsParameters(width, height);
        vintage.distortionK1 = -0.06f; vintage.vignetteNatural = 0.35f; vintage.vignetteOptical = 0.18f;
        vintage.cornerSharpnessLoss = .50f; vintage.astigmatism = .45f; vintage.coma = .35f;
        vintage.sphericalHalo = .30f; vintage.lateralCARed = 0.18f; vintage.lateralCABlue = -0.22f;
        vintage.bloomThreshold = 1.0f; vintage.bloomEnergy = 0.25f; vintage.bloomRadius = 10.0f;
        vintage.glareColor = {1.0f, 0.72f, 0.48f}; vintage.glareColorAmount = 0.45f;
        vintage.transmissionColor = {1.0f, 0.94f, 0.82f}; vintage.transmissionColorAmount = 0.18f;
        auto vintageReference = render(engine, device, queue, input, width, height, vintage);
        save("02-vintage.tiff", displayPreview(vintageReference));

        auto anamorphic = vintage;
        anamorphic.anamorphicSqueeze = 2.0f; anamorphic.bloomHorizontalStretch = 4.0f;
        anamorphic.bloomEnergy = 0.35f; anamorphic.bloomRadius = 7.0f;
        save("03-anamorphic.tiff", displayPreview(render(engine, device, queue, input, width, height, anamorphic)));

        auto exotic = vintage;
        exotic.swirl = 0.9f; exotic.fieldCurvature = 0.8f; exotic.radialSmear = .70f;
        exotic.vignetteMechanical = 0.45f; exotic.imageCircleSize = 0.92f; exotic.imageCircleSoftness = 0.16f;
        save("04-exotic.tiff", displayPreview(render(engine, device, queue, input, width, height, exotic)));

        auto uniform = makeUniformField(width, height);
        save("10-uniform-input.tiff", displayPreview(uniform));
        auto naturalVignette = LDBNeutralOpticsParameters(width, height);
        naturalVignette.vignetteNatural = .8f;
        save("11-vignette-natural.tiff", displayPreview(render(engine, device, queue, uniform, width, height, naturalVignette)));
        auto opticalVignette = LDBNeutralOpticsParameters(width, height);
        opticalVignette.vignetteOptical = 1.2f;
        save("12-vignette-optical.tiff", displayPreview(render(engine, device, queue, uniform, width, height, opticalVignette)));
        auto mechanicalVignette = LDBNeutralOpticsParameters(width, height);
        mechanicalVignette.vignetteMechanical = 1; mechanicalVignette.imageCircleSize = .92f;
        mechanicalVignette.imageCircleAspect = 1.35f; mechanicalVignette.imageCircleSoftness = .10f;
        mechanicalVignette.opticalCenter = {.47f,.53f};
        save("13-vignette-mechanical.tiff", displayPreview(render(engine, device, queue, uniform, width, height, mechanicalVignette)));

        auto polar = makePolarChart(width, height);
        save("20-polar-input.tiff", displayPreview(polar));
        auto directional = LDBNeutralOpticsParameters(width, height);
        directional.cornerSharpnessLoss = .55f; directional.fieldCurvature = .35f;
        directional.astigmatism = .65f; directional.radialSmear = .60f; directional.tangentialSmear = .35f;
        save("21-polar-directional-focus.tiff", displayPreview(render(engine, device, queue, polar, width, height, directional)));
        auto polarCA = LDBNeutralOpticsParameters(width, height);
        polarCA.lateralCARed = .35f; polarCA.lateralCABlue = -.35f; polarCA.swirl = .65f;
        save("22-polar-ca-swirl.tiff", displayPreview(render(engine, device, queue, polar, width, height, polarCA)));
        auto gatedGeometry=LDBNeutralOpticsParameters(width,height);
        gatedGeometry.distortionK1=.035f;gatedGeometry.distortionK2=.055f;
        gatedGeometry.moustacheK3=.07f;gatedGeometry.geometryFieldAmount=1;
        gatedGeometry.opticalCenter={.46f,.54f};
        gatedGeometry.responseFieldOnset=.24f;
        gatedGeometry.responseFieldFalloff=1.55f;
        save("26-polar-field-gated-geometry.tiff",
             displayPreview(render(engine,device,queue,polar,width,height,gatedGeometry)));
        auto stretchOnly=LDBNeutralOpticsParameters(width,height);
        stretchOnly.geometryFieldAmount=1;stretchOnly.peripheralStretch=.72f;
        stretchOnly.responseFieldOnset=.20f;stretchOnly.responseFieldFalloff=1.6f;
        save("27-polar-peripheral-stretch-only.tiff",
             displayPreview(render(engine,device,queue,polar,width,height,stretchOnly)));
        auto warpOnly=stretchOnly;warpOnly.peripheralStretch=0;warpOnly.peripheralWarp=.9f;
        save("28-polar-peripheral-warp-only.tiff",
             displayPreview(render(engine,device,queue,polar,width,height,warpOnly)));
        auto refractive=LDBNeutralOpticsParameters(width,height);
        refractive.refractiveIrregularity=2.0f;refractive.refractiveScale=.55f;
        refractive.refractiveEdgeBias=.28f;refractive.refractiveAnisotropy=.82f;
        refractive.refractiveRotation=28;refractive.refractiveSeed=27182;
        save("29-polar-refractive-irregularity.tiff",
             displayPreview(render(engine,device,queue,polar,width,height,refractive)));
        refractive.refractiveDispersion=.85f;
        save("29b-polar-refractive-dispersion.tiff",
             displayPreview(render(engine,device,queue,polar,width,height,refractive)));
        auto detailBoost = LDBNeutralOpticsParameters(width, height);
        detailBoost.microContrast=.25f; detailBoost.fineDetail=.30f; detailBoost.detailScale=1.25f;
        save("23-polar-detail-boost.tiff", displayPreview(render(engine,device,queue,polar,width,height,detailBoost)));
        auto detailVintage = LDBNeutralOpticsParameters(width, height);
        detailVintage.microContrast=-.12f; detailVintage.fineDetail=-.18f;
        detailVintage.detailEdgeFalloff=.55f; detailVintage.sagittalDetail=-.18f;
        detailVintage.tangentialDetail=-.42f; detailVintage.detailScale=1.5f;
        save("24-polar-detail-vintage.tiff", displayPreview(render(engine,device,queue,polar,width,height,detailVintage)));
        auto longitudinalCA = LDBNeutralOpticsParameters(width,height);
        longitudinalCA.longitudinalCA=1.4f; longitudinalCA.longitudinalCARadius=9.0f;
        save("25-polar-longitudinal-ca.tiff",displayPreview(render(engine,device,queue,polar,width,height,longitudinalCA)));
        auto focusTransitions=makeFocusTransitionChart(width,height);
        save("26-focus-transitions-input.tiff",displayPreview(focusTransitions));
        save("27-focus-transitions-longitudinal-ca.tiff",displayPreview(render(engine,device,queue,focusTransitions,width,height,longitudinalCA)));
        auto depthFocusTransitions=focusTransitions;
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x)
            depthFocusTransitions[y*width+x].w=float(x)/float(width-1);
        auto depthLongitudinalCA=longitudinalCA;
        depthLongitudinalCA.depthMode=2;depthLongitudinalCA.depthChannel=4;
        depthLongitudinalCA.depthFocus=.5f;
        save("28-focus-transitions-depth-ca-mid.tiff",displayPreview(render(engine,device,queue,depthFocusTransitions,width,height,depthLongitudinalCA)));
        depthLongitudinalCA.depthFocus=.2f;
        save("29-focus-transitions-depth-ca-near.tiff",displayPreview(render(engine,device,queue,depthFocusTransitions,width,height,depthLongitudinalCA)));

        auto hdr = makeHDRSources(width, height);
        save("30-hdr-sources-input.tiff", displayPreview(hdr));
        auto bloomOnly = LDBNeutralOpticsParameters(width, height);
        bloomOnly.bloomThreshold = 1; bloomOnly.bloomEnergy = .45f; bloomOnly.bloomRadius = 16;
        save("31-hdr-bloom.tiff", displayPreview(render(engine, device, queue, hdr, width, height, bloomOnly)));
        auto glareOnly = LDBNeutralOpticsParameters(width, height);
        glareOnly.bloomThreshold = 1; glareOnly.glareEnergy = .30f; glareOnly.glareRadius = 42;
        glareOnly.glareColor = {1,.72f,.45f}; glareOnly.glareColorAmount = .5f;
        save("32-hdr-glare.tiff", displayPreview(render(engine, device, queue, hdr, width, height, glareOnly)));
        auto anamorphicLight = bloomOnly;
        anamorphicLight.bloomHorizontalStretch = 5; anamorphicLight.bloomRadius = 13;
        save("33-hdr-anamorphic.tiff", displayPreview(render(engine, device, queue, hdr, width, height, anamorphicLight)));
        auto hawkFlareBaseline=LDBNeutralOpticsParameters(width,height);
        hawkFlareBaseline.anamorphicFlareAmount=1.15f;
        hawkFlareBaseline.anamorphicFlareRadius=210;
        hawkFlareBaseline.anamorphicFlareThreshold=.55f;
        hawkFlareBaseline.anamorphicFlareColor={.14f,.38f,1.0f};
        save("129-hdr-source-driven-flare-streak.tiff",
             displayPreview(render(engine,device,queue,hdr,width,height,hawkFlareBaseline)));
        auto hawkFlareCore=hawkFlareBaseline;
        hawkFlareCore.anamorphicFlareCoreAmount=.75f;
        hawkFlareCore.anamorphicFlareAsymmetry=-.32f;
        save("130-hdr-source-driven-flare-core.tiff",
             displayPreview(render(engine,device,queue,hdr,width,height,hawkFlareCore)));
        auto hawkFlare=hawkFlareCore;
        hawkFlare.anamorphicFlareGhostAmount=.48f;
        hawkFlare.anamorphicFlareGhostPosition=-.72f;
        hawkFlare.anamorphicFlareGhostScale=.82f;
        hawkFlare.anamorphicFlareGhostColor={.62f,.20f,1.0f};
        save("131-hdr-bounded-soft-hawk-ghost.tiff",
             displayPreview(render(engine,device,queue,hdr,width,height,hawkFlare)));
        auto comaOnly = LDBNeutralOpticsParameters(width, height);
        comaOnly.coma=.80f;
        save("34-hdr-coma.tiff",displayPreview(render(engine,device,queue,hdr,width,height,comaOnly)));
        auto haloOnly = LDBNeutralOpticsParameters(width, height);
        haloOnly.sphericalHalo=.65f;
        save("35-hdr-spherical-halo.tiff",displayPreview(render(engine,device,queue,hdr,width,height,haloOnly)));
        auto comaHalo=comaOnly; comaHalo.sphericalHalo=.65f;
        save("36-hdr-coma-halo.tiff",displayPreview(render(engine,device,queue,hdr,width,height,comaHalo)));
        auto wear=LDBNeutralOpticsParameters(width,height);
        wear.frontHaze=1.15f;wear.cleaningMarks=1.6f;wear.scratchAmount=1.35f;
        wear.scratchDirection=28;wear.damageScale=1.25f;wear.coatingWear=1.25f;
        wear.coatingWearScale=1.4f;wear.damageSeed=31415;
        save("37-hdr-front-element-wear.tiff",
             displayPreview(render(engine,device,queue,hdr,width,height,wear)));
        save("38-chart-front-element-wear.tiff",
             displayPreview(render(engine,device,queue,input,width,height,wear)));
        auto internalDirt=LDBNeutralOpticsParameters(width,height);
        internalDirt.internalDirtAmount=1.8f;internalDirt.internalDirtScale=1.45f;
        internalDirt.internalDirtSmear=.12f;internalDirt.internalDirtScatter=1.4f;
        internalDirt.internalDirtSeed=16180;
        save("112-hdr-internal-cloud-control.tiff",
             displayPreview(render(engine,device,queue,hdr,width,height,internalDirt)));
        auto internalSmear=internalDirt;internalSmear.internalDirtScale=2.4f;
        internalSmear.internalDirtSmear=.9f;internalSmear.internalDirtSeed=14142;
        save("113-chart-internal-cloud-control.tiff",
             displayPreview(render(engine,device,queue,input,width,height,internalSmear)));
        auto internalWithWear=internalSmear;
        internalWithWear.frontHaze=.65f;internalWithWear.cleaningMarks=.8f;
        internalWithWear.scratchAmount=.55f;internalWithWear.scratchDirection=28;
        internalWithWear.damageScale=1.25f;internalWithWear.coatingWear=.75f;
        internalWithWear.coatingWearScale=1.4f;internalWithWear.damageSeed=31415;
        save("116-chart-internal-contamination-with-front-wear.tiff",
             displayPreview(render(engine,device,queue,input,width,height,internalWithWear)));
        auto internalWithScatter=internalDirt;
        internalWithScatter.bloomThreshold=.65f;internalWithScatter.bloomEnergy=.55f;
        internalWithScatter.bloomRadius=18;internalWithScatter.glareEnergy=.32f;
        internalWithScatter.glareRadius=44;
        save("117-hdr-internal-contamination-with-bloom-glare.tiff",
             displayPreview(render(engine,device,queue,hdr,width,height,internalWithScatter)));
        auto apertureChart=loadTIFFChart(argv[3],width,height);
        if(apertureChart.empty()) {
            std::fprintf(stderr,"FAIL: unable to load aperture chart %s\n",argv[3]);
            return 16;
        }
        save("70-aperture-chart-input.tiff",displayPreview(apertureChart));
        auto apertureCircular=LDBNeutralOpticsParameters(width,height);
        apertureCircular.apertureResponse=1;apertureCircular.apertureRadius=24;
        save("71-aperture-chart-circular.tiff",displayPreview(render(engine,device,queue,apertureChart,width,height,apertureCircular)));
        auto aperturePolygon=apertureCircular;aperturePolygon.apertureShape=1;
        aperturePolygon.apertureBladeCount=6;aperturePolygon.apertureBladeCurvature=0;
        aperturePolygon.apertureSoftness=0;
        save("72-aperture-chart-polygon.tiff",displayPreview(render(engine,device,queue,apertureChart,width,height,aperturePolygon)));
        auto apertureOval=apertureCircular;apertureOval.apertureShape=2;apertureOval.apertureAspect=2;
        save("73-aperture-chart-oval.tiff",displayPreview(render(engine,device,queue,apertureChart,width,height,apertureOval)));
        auto apertureCatEye=apertureOval;apertureCatEye.apertureCatEye=1;
        save("74-aperture-chart-cat-eye.tiff",displayPreview(render(engine,device,queue,apertureChart,width,height,apertureCatEye)));
        const uint32_t isolatedBladeCounts[] = {3,5,6,8,16};
        for(uint32_t blades:isolatedBladeCounts) {
            auto isolated=apertureCircular;isolated.apertureShape=1;isolated.apertureBladeCount=blades;
            isolated.apertureBladeCurvature=0;isolated.apertureSoftness=0;isolated.apertureCatEye=0;
            isolated.apertureAspect=1;isolated.apertureRotation=0;
            save(std::string("75-aperture-polygon-")+std::to_string(blades)+"-blades.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,isolated)));
        }
        auto isolatedCatEye=apertureCircular;isolatedCatEye.apertureShape=2;
        isolatedCatEye.apertureAspect=.25f;isolatedCatEye.apertureCatEye=.75f;
        isolatedCatEye.apertureSoftness=0;isolatedCatEye.apertureRotation=-114;
        save("76-aperture-extreme-filled-cat-eye.tiff",
             displayPreview(render(engine,device,queue,apertureChart,width,height,isolatedCatEye)));
        auto depthApertureChart=apertureChart;
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x)
            depthApertureChart[size_t(y)*width+x].w=float(x)/float(width-1);
        auto depthApertureMid=apertureCircular;
        depthApertureMid.depthMode=2;depthApertureMid.depthChannel=4;depthApertureMid.depthFocus=.5f;
        save("77-aperture-depth-focus-mid.tiff",
             displayPreview(render(engine,device,queue,depthApertureChart,width,height,depthApertureMid)));
        depthApertureMid.depthFocus=.2f;
        save("78-aperture-depth-focus-near.tiff",
             displayPreview(render(engine,device,queue,depthApertureChart,width,height,depthApertureMid)));

        auto bokehSwirl=apertureCircular;
        bokehSwirl.apertureBokehSwirl=2.0f;
        bokehSwirl.apertureCatEye=.30f;
        bokehSwirl.responseFieldOnset=.22f;
        bokehSwirl.responseFieldFalloff=.82f;
        save("90-aperture-bokeh-swirl.tiff",
             displayPreview(render(engine,device,queue,apertureChart,width,height,bokehSwirl)));
        auto ellipticalBokehSwirl=bokehSwirl;
        ellipticalBokehSwirl.fieldAspect=1.55f;
        ellipticalBokehSwirl.fieldRotation=18.0f;
        save("91-aperture-bokeh-swirl-elliptical.tiff",
             displayPreview(render(engine,device,queue,apertureChart,width,height,ellipticalBokehSwirl)));
        // This remains the current bokeh/field-PSF review set until a later
        // pass explicitly replaces it. The manifest likewise carries these
        // files forward for pass 99 and newer.
        if(passNumber>=99) {
            save("491-bokeh-swirl-range-source.tiff",displayPreview(apertureChart));
            const float swirlValues[]={0.0f,3.0f,6.0f,9.0f,12.0f};
            const char* swirlNames[]={"492-bokeh-swirl-00.tiff",
                                      "493-bokeh-swirl-03.tiff",
                                      "494-bokeh-swirl-06.tiff",
                                      "495-bokeh-swirl-09.tiff",
                                      "496-bokeh-swirl-12.tiff"};
            for(int i=0;i<5;++i) {
                auto progressive=LDBNeutralOpticsParameters(width,height);
                progressive.responseFieldOnset=.09f;
                progressive.responseFieldFalloff=.92f;
                progressive.apertureResponse=1.0f;
                progressive.apertureRadius=21.0f;
                progressive.apertureSoftness=.18f;
                progressive.apertureCatEye=.76f;
                progressive.apertureBokehSwirl=swirlValues[i];
                save(swirlNames[i],displayPreview(render(
                    engine,device,queue,apertureChart,width,height,progressive)));
            }
        }
        if(passNumber>=79) {
            save("339-bokeh-petzval-point-source.tiff",displayPreview(apertureChart));
            auto bokehConservative=LDBNeutralOpticsParameters(width,height);
            bokehConservative.apertureResponse=.55f;
            bokehConservative.apertureRadius=14.0f;
            bokehConservative.apertureSoftness=.16f;
            bokehConservative.apertureCatEye=.22f;
            bokehConservative.apertureBokehSwirl=1.2f;
            bokehConservative.responseFieldOnset=.16f;
            bokehConservative.responseFieldFalloff=1.10f;
            save("340-bokeh-swirl-conservative.tiff",displayPreview(render(
                engine,device,queue,apertureChart,width,height,bokehConservative)));
            auto bokehMedium=bokehConservative;
            bokehMedium.apertureResponse=.78f;
            bokehMedium.apertureRadius=18.0f;
            bokehMedium.apertureCatEye=.42f;
            bokehMedium.apertureBokehSwirl=3.2f;
            bokehMedium.responseFieldOnset=.14f;
            save("341-bokeh-swirl-medium.tiff",displayPreview(render(
                engine,device,queue,apertureChart,width,height,bokehMedium)));
            auto bokehExtreme=bokehMedium;
            bokehExtreme.apertureResponse=1.0f;
            bokehExtreme.apertureRadius=22.0f;
            bokehExtreme.apertureSoftness=.12f;
            bokehExtreme.apertureCatEye=.72f;
            bokehExtreme.apertureBokehSwirl=6.0f;
            bokehExtreme.responseFieldOnset=.10f;
            bokehExtreme.responseFieldFalloff=1.05f;
            save("342-bokeh-swirl-extreme.tiff",displayPreview(render(
                engine,device,queue,apertureChart,width,height,bokehExtreme)));
            auto petzvalPupil=bokehConservative;
            petzvalPupil.apertureShape=1;
            petzvalPupil.apertureBladeCount=8;
            petzvalPupil.apertureBladeCurvature=.72f;
            petzvalPupil.apertureAspect=1.04f;
            petzvalPupil.apertureCatEye=.24f;
            save("343-petzval-pupil-conservative.tiff",displayPreview(render(
                engine,device,queue,apertureChart,width,height,petzvalPupil)));
            petzvalPupil.apertureResponse=.52f;
            petzvalPupil.apertureRadius=12.0f;
            petzvalPupil.apertureAspect=1.10f;
            petzvalPupil.apertureCatEye=.52f;
            petzvalPupil.apertureBokehSwirl=3.2f;
            petzvalPupil.responseFieldOnset=.16f;
            petzvalPupil.responseFieldFalloff=1.16f;
            save("344-petzval-pupil-medium.tiff",displayPreview(render(
                engine,device,queue,apertureChart,width,height,petzvalPupil)));
            petzvalPupil.apertureResponse=.78f;
            petzvalPupil.apertureRadius=16.0f;
            petzvalPupil.apertureBladeCurvature=.66f;
            petzvalPupil.apertureAspect=1.18f;
            petzvalPupil.apertureCatEye=.88f;
            petzvalPupil.apertureBokehSwirl=6.0f;
            petzvalPupil.responseFieldOnset=.12f;
            petzvalPupil.responseFieldFalloff=1.10f;
            save("345-petzval-pupil-extreme.tiff",displayPreview(render(
                engine,device,queue,apertureChart,width,height,petzvalPupil)));
            if(passNumber>=80) {
                save("350-bokeh-petzval-point-source.tiff",displayPreview(apertureChart));
                auto filledConservative=bokehConservative;
                filledConservative.apertureResponse=1.0f;
                filledConservative.responseFieldFalloff=.72f;
                save("351-bokeh-swirl-conservative-filled.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,filledConservative)));
                auto filledMedium=bokehMedium;
                filledMedium.apertureResponse=1.0f;
                filledMedium.responseFieldFalloff=.72f;
                save("352-bokeh-swirl-medium-filled.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,filledMedium)));
                auto filledExtreme=bokehExtreme;
                filledExtreme.apertureResponse=1.0f;
                filledExtreme.responseFieldFalloff=.72f;
                save("353-bokeh-swirl-extreme-filled.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,filledExtreme)));
                auto filledPetzval=petzvalPupil;
                filledPetzval.apertureResponse=1.0f;
                filledPetzval.apertureRadius=9.0f;
                filledPetzval.apertureBladeCurvature=.72f;
                filledPetzval.apertureAspect=1.04f;
                filledPetzval.apertureCatEye=.24f;
                filledPetzval.apertureBokehSwirl=1.2f;
                filledPetzval.responseFieldOnset=.18f;
                filledPetzval.responseFieldFalloff=.72f;
                save("354-petzval-pupil-conservative-filled.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,filledPetzval)));
                filledPetzval.apertureRadius=12.0f;
                filledPetzval.apertureAspect=1.10f;
                filledPetzval.apertureCatEye=.52f;
                filledPetzval.apertureBokehSwirl=3.2f;
                filledPetzval.responseFieldOnset=.16f;
                save("355-petzval-pupil-medium-filled.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,filledPetzval)));
                filledPetzval.apertureRadius=16.0f;
                filledPetzval.apertureBladeCurvature=.66f;
                filledPetzval.apertureAspect=1.18f;
                filledPetzval.apertureCatEye=.88f;
                filledPetzval.apertureBokehSwirl=6.0f;
                filledPetzval.responseFieldOnset=.12f;
                save("356-petzval-pupil-extreme-filled.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,filledPetzval)));
            }
        }

        auto depthBoundaryChart=makeDepthBoundaryChart(width,height);
        save("79-depth-boundaries-input.tiff",displayPreview(depthBoundaryChart));
        auto depthBoundaryDiagnostic=LDBNeutralOpticsParameters(width,height);
        depthBoundaryDiagnostic.depthMode=2;depthBoundaryDiagnostic.depthChannel=4;
        depthBoundaryDiagnostic.processingFlags=LDBDiagnosticDepth;
        save("80-depth-boundaries-map.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,depthBoundaryDiagnostic)));
        auto boundaryAperture=apertureCircular;
        boundaryAperture.depthMode=2;boundaryAperture.depthChannel=4;
        boundaryAperture.depthFocus=.18f;
        save("81-depth-boundaries-focus-near.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,boundaryAperture)));
        boundaryAperture.depthFocus=.40f;
        save("82-depth-boundaries-focus-rails.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,boundaryAperture)));
        boundaryAperture.depthFocus=.86f;
        save("83-depth-boundaries-focus-far.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,boundaryAperture)));

        auto boundaryBloom=LDBNeutralOpticsParameters(width,height);
        boundaryBloom.bloomThreshold=.7f;boundaryBloom.bloomEnergy=.8f;
        boundaryBloom.bloomRadius=18.0f;
        save("84-depth-boundaries-bloom-depth-free.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,boundaryBloom)));
        boundaryBloom.depthMode=2;boundaryBloom.depthChannel=4;
        save("85-depth-boundaries-bloom-occluded.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,boundaryBloom)));
        auto boundaryGlare=boundaryBloom;
        boundaryGlare.bloomEnergy=0.0f;boundaryGlare.glareEnergy=.55f;
        boundaryGlare.glareRadius=42.0f;
        save("86-depth-boundaries-glare-occluded.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,boundaryGlare)));
        auto boundaryScatterDiagnostic=boundaryBloom;
        boundaryScatterDiagnostic.processingFlags=LDBDiagnosticScatter;
        save("87-depth-boundaries-scatter-diagnostic.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,boundaryScatterDiagnostic)));

        auto depthHaloTransitions=focusTransitions;
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x)
            depthHaloTransitions[size_t(y)*width+x].w=float(x)/float(width-1);
        auto depthHalo=LDBNeutralOpticsParameters(width,height);
        depthHalo.depthMode=2;depthHalo.depthChannel=4;depthHalo.depthFocus=.5f;
        depthHalo.sphericalHalo=.85f;
        save("88-focus-transitions-depth-spherical-halo.tiff",
             displayPreview(render(engine,device,queue,depthHaloTransitions,width,height,depthHalo)));
        depthHalo.depthFocus=.2f;
        save("89-focus-transitions-depth-spherical-halo-near.tiff",
             displayPreview(render(engine,device,queue,depthHaloTransitions,width,height,depthHalo)));

        auto edgeProtectionOff=boundaryBloom;
        edgeProtectionOff.responseScatterEdgeProtection=0.0f;
        save("90-depth-boundaries-protection-off.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,edgeProtectionOff)));
        auto edgeSoftnessCrisp=boundaryBloom;
        edgeSoftnessCrisp.depthEdgeSoftness=0.0f;
        save("91-depth-boundaries-softness-crisp.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,edgeSoftnessCrisp)));
        auto edgeSoftnessSoft=boundaryBloom;
        edgeSoftnessSoft.depthEdgeSoftness=1.0f;
        save("92-depth-boundaries-softness-soft.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,edgeSoftnessSoft)));
        auto defocusDiagnostic=boundaryAperture;
        defocusDiagnostic.processingFlags=LDBDiagnosticDefocus;
        save("93-depth-boundaries-defocus-diagnostic.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,defocusDiagnostic)));
        auto rejectionDiagnostic=boundaryAperture;
        rejectionDiagnostic.processingFlags=LDBDiagnosticDepthRejection;
        save("94-depth-boundaries-rejection-diagnostic.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,rejectionDiagnostic)));
        auto internalDepth=boundaryAperture;
        internalDepth.depthFocus=.18f;internalDepth.internalDirtAmount=1.35f;
        internalDepth.internalDirtScale=1.5f;internalDepth.internalDirtSmear=.35f;
        internalDepth.internalDirtScatter=1.1f;internalDepth.internalDirtSeed=16180;
        save("118-depth-internal-contamination-with-focus-protection.tiff",
             displayPreview(render(engine,device,queue,depthBoundaryChart,width,height,internalDepth)));

        struct Space { uint32_t value; const char* name; };
        const Space spaces[] = {{LDBWorkingColorSpaceACEScct,"acescct"},
            {LDBWorkingColorSpaceDaVinciIntermediate,"dwg-intermediate"},
            {LDBWorkingColorSpaceARRILogC3EI800,"logc3-ei800"},
            {LDBWorkingColorSpaceARRILogC4,"logc4"}};
        bool equivalent = true;
        for (const auto& space : spaces) {
            auto encodedInput = convertEncoding(input, space.value, true);
            auto configured = vintage;
            configured.workingColorSpace = space.value;
            auto encodedResult = render(engine, device, queue, encodedInput, width, height, configured);
            auto commonResult = convertEncoding(encodedResult, space.value, false);
            float error = maxRGBDifference(vintageReference, commonResult);
            std::printf("Cross-space max AP1 error (%s): %.8f\n", space.name, error);
            equivalent = equivalent && error < .003f;
            save(std::string("02-vintage-") + space.name + ".tiff", displayPreview(commonResult));
        }
        if (!equivalent) {
            std::fprintf(stderr, "FAIL: visual cross-space AP1 error exceeded tolerance\n");
            return 5;
        }

        if (argc >= 5) {
            constexpr uint32_t isoWidth = 1920, isoHeight = 1080;
            auto iso = loadTIFFChart(argv[4], isoWidth, isoHeight);
            if (iso.empty()) {
                std::fprintf(stderr, "FAIL: unable to rasterize ISO chart %s\n", argv[4]);
                return 8;
            }
            auto saveISO = [&](const std::string& name, const std::vector<simd_float4>& pixels) {
                if(!publishOutput(name))return;
                if(reviewOutputFloor>0&&std::atoi(name.c_str())<reviewOutputFloor)return;
                if (!writeTIFF(directory + "/" + name, pixels, isoWidth, isoHeight)) std::exit(9);
            };
            saveISO("40-iso12233-input.tiff", displayPreview(iso));
            auto isoModern = LDBNeutralOpticsParameters(isoWidth, isoHeight);
            isoModern.distortionK1=-.015f; isoModern.cornerSharpnessLoss=.12f; isoModern.vignetteNatural=.08f;
            saveISO("41-iso12233-modern.tiff", displayPreview(render(engine, device, queue, iso, isoWidth, isoHeight, isoModern)));
            auto isoVintage = vintage;
            saveISO("42-iso12233-vintage.tiff", displayPreview(render(engine, device, queue, iso, isoWidth, isoHeight, isoVintage)));
            auto isoDirectional = directional;
            saveISO("43-iso12233-directional-focus.tiff", displayPreview(render(engine, device, queue, iso, isoWidth, isoHeight, isoDirectional)));
            auto isoCA = polarCA;
            saveISO("44-iso12233-ca-swirl.tiff", displayPreview(render(engine, device, queue, iso, isoWidth, isoHeight, isoCA)));
            if(passNumber==96) {
                saveISO("472-causal-optical-chart-source.tiff",displayPreview(iso));
                auto fieldBlur=LDBNeutralOpticsParameters(isoWidth,isoHeight);
                fieldBlur.responseFieldOnset=.05f;
                fieldBlur.responseFieldFalloff=.95f;
                fieldBlur.cornerSharpnessLoss=2.0f;
                fieldBlur.fieldCurvature=1.65f;
                fieldBlur.astigmatism=.72f;
                fieldBlur.radialSmear=.82f;
                fieldBlur.tangentialSmear=1.15f;
                saveISO("473-continuous-field-blur.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,fieldBlur)));
                auto chromatic=fieldBlur;
                chromatic.lateralCARed=1.45f;
                chromatic.lateralCABlue=-1.90f;
                chromatic.longitudinalCA=.78f;
                saveISO("474-chromatic-after-field-blur.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,chromatic)));
                auto aperture=fieldBlur;
                aperture.apertureResponse=.78f;
                aperture.apertureRadius=17.0f;
                aperture.apertureShape=1;
                aperture.apertureBladeCount=7;
                aperture.apertureBladeCurvature=.62f;
                aperture.apertureSoftness=.18f;
                aperture.apertureCatEye=.48f;
                aperture.apertureBokehSwirl=3.2f;
                saveISO("475-shaped-aperture-after-field-blur.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,aperture)));
                auto combined=aperture;
                combined.lateralCARed=1.10f;
                combined.lateralCABlue=-1.45f;
                combined.longitudinalCA=.58f;
                saveISO("476-combined-causal-optics.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,combined)));
            }
            if(passNumber==97) {
                saveISO("479-expanded-aperture-chart-source.tiff",displayPreview(iso));
                auto formerCeiling=LDBNeutralOpticsParameters(isoWidth,isoHeight);
                formerCeiling.responseFieldOnset=.10f;
                formerCeiling.responseFieldFalloff=.72f;
                formerCeiling.apertureResponse=1.0f;
                formerCeiling.apertureRadius=24.0f;
                formerCeiling.apertureSoftness=.12f;
                formerCeiling.apertureCatEye=.82f;
                formerCeiling.apertureBokehSwirl=6.0f;
                saveISO("480-former-aperture-range-ceiling.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,formerCeiling)));
                auto extendedCeiling=formerCeiling;
                extendedCeiling.apertureRadius=40.0f;
                extendedCeiling.apertureBokehSwirl=12.0f;
                saveISO("481-extended-aperture-range-ceiling.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,extendedCeiling)));
                auto bokehSwirl=LDBNeutralOpticsParameters(isoWidth,isoHeight);
                bokehSwirl.responseFieldOnset=.11f;
                bokehSwirl.responseFieldFalloff=1.06f;
                bokehSwirl.apertureResponse=.90f;
                bokehSwirl.apertureRadius=18.0f;
                bokehSwirl.apertureSoftness=.20f;
                bokehSwirl.apertureCatEye=.68f;
                bokehSwirl.apertureBokehSwirl=5.0f;
                saveISO("482-demo-bokeh-swirl-revised.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,bokehSwirl)));
                auto petzval=LDBNeutralOpticsParameters(isoWidth,isoHeight);
                petzval.responseFieldOnset=.11f;
                petzval.responseFieldFalloff=1.12f;
                petzval.fieldCenter={.48f,.52f};
                petzval.cornerSharpnessLoss=1.6f;
                petzval.fieldCurvature=1.7f;
                petzval.astigmatism=.78f;
                petzval.tangentialSmear=.72f;
                petzval.apertureResponse=.88f;
                petzval.apertureRadius=18.0f;
                petzval.apertureShape=1;
                petzval.apertureBladeCount=8;
                petzval.apertureBladeCurvature=.72f;
                petzval.apertureSoftness=.20f;
                petzval.apertureCatEye=.80f;
                petzval.apertureAspect=1.16f;
                petzval.apertureBokehSwirl=5.0f;
                saveISO("483-demo-petzval-field-revised.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,petzval)));
            }
            if(passNumber==98) {
                saveISO("486-bokeh-boundary-chart-source.tiff",displayPreview(iso));
                auto revised=LDBNeutralOpticsParameters(isoWidth,isoHeight);
                revised.responseFieldOnset=.09f;
                revised.responseFieldFalloff=.92f;
                revised.apertureResponse=.96f;
                revised.apertureRadius=21.0f;
                revised.apertureSoftness=.18f;
                revised.apertureCatEye=.76f;
                revised.apertureBokehSwirl=8.0f;
                saveISO("487-demo-bokeh-swirl-strengthened.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,revised)));
                auto stress=revised;
                stress.responseFieldOnset=0.0f;
                stress.responseFieldFalloff=.55f;
                stress.apertureResponse=1.0f;
                stress.apertureRadius=48.0f;
                stress.apertureSoftness=.08f;
                stress.apertureCatEye=1.0f;
                stress.apertureBokehSwirl=12.0f;
                saveISO("488-maximum-bokeh-boundary-stress.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,stress)));
            }
            if(passNumber>=79) {
                saveISO("346-petzval-iso-source.tiff",displayPreview(iso));
                auto petzvalField=LDBNeutralOpticsParameters(isoWidth,isoHeight);
                petzvalField.fieldCenter={.48f,.52f};
                petzvalField.responseFieldOnset=.18f;
                petzvalField.responseFieldFalloff=1.16f;
                petzvalField.cornerSharpnessLoss=.42f;
                petzvalField.fieldCurvature=.38f;
                petzvalField.astigmatism=.10f;
                petzvalField.tangentialSmear=.08f;
                petzvalField.apertureResponse=.30f;
                petzvalField.apertureRadius=9.0f;
                petzvalField.apertureShape=1;
                petzvalField.apertureBladeCount=8;
                petzvalField.apertureBladeCurvature=.72f;
                petzvalField.apertureAspect=1.04f;
                petzvalField.apertureCatEye=.24f;
                petzvalField.apertureBokehSwirl=1.2f;
                saveISO("347-petzval-field-conservative-iso.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,petzvalField)));
                petzvalField.responseFieldOnset=.16f;
                petzvalField.cornerSharpnessLoss=.82f;
                petzvalField.fieldCurvature=.82f;
                petzvalField.astigmatism=.30f;
                petzvalField.tangentialSmear=.24f;
                petzvalField.apertureResponse=.52f;
                petzvalField.apertureRadius=12.0f;
                petzvalField.apertureAspect=1.10f;
                petzvalField.apertureCatEye=.52f;
                petzvalField.apertureBokehSwirl=3.2f;
                saveISO("348-petzval-field-medium-iso.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,petzvalField)));
                petzvalField.responseFieldOnset=.12f;
                petzvalField.responseFieldFalloff=1.10f;
                petzvalField.cornerSharpnessLoss=1.32f;
                petzvalField.fieldCurvature=1.35f;
                petzvalField.astigmatism=.65f;
                petzvalField.tangentialSmear=.58f;
                petzvalField.apertureResponse=.78f;
                petzvalField.apertureRadius=16.0f;
                petzvalField.apertureBladeCurvature=.66f;
                petzvalField.apertureAspect=1.18f;
                petzvalField.apertureCatEye=.88f;
                petzvalField.apertureBokehSwirl=6.0f;
                saveISO("349-petzval-field-extreme-iso.tiff",displayPreview(render(
                    engine,device,queue,iso,isoWidth,isoHeight,petzvalField)));
            }
            if(passNumber>=78) {
                saveISO("335-preset-close-focus-macro-iso-source.tiff",displayPreview(iso));
                auto macroSubtle=LDBNeutralOpticsParameters(isoWidth,isoHeight);
                macroSubtle.captureInfluence=.70f;
                macroSubtle.captureFocalLength=100.0f;
                macroSubtle.captureAperture=2.0f;
                macroSubtle.captureFocusDistance=28.0f;
                macroSubtle.cornerSharpnessLoss=.48f;
                macroSubtle.fieldCurvature=.40f;
                macroSubtle.astigmatism=.10f;
                macroSubtle.fineDetail=.10f;
                macroSubtle.microContrast=.12f;
                macroSubtle.longitudinalCA=.28f;
                macroSubtle.responseFieldOnset=.18f;
                macroSubtle.responseFieldFalloff=1.52f;
                macroSubtle.sphericalHalo=.12f;
                saveISO("336-preset-close-focus-macro-subtle-iso.tiff",
                        displayPreview(render(engine,device,queue,iso,isoWidth,isoHeight,macroSubtle)));
                auto macroMedium=macroSubtle;
                macroMedium.captureInfluence=.90f;
                macroMedium.cornerSharpnessLoss=1.10f;
                macroMedium.fieldCurvature=1.05f;
                macroMedium.astigmatism=.26f;
                macroMedium.radialSmear=.15f;
                macroMedium.fineDetail=.18f;
                macroMedium.microContrast=.22f;
                macroMedium.longitudinalCA=.82f;
                macroMedium.sphericalHalo=.30f;
                macroMedium.apertureResponse=.28f;
                macroMedium.apertureRadius=8.5f;
                saveISO("337-preset-close-focus-macro-medium-iso.tiff",
                        displayPreview(render(engine,device,queue,iso,isoWidth,isoHeight,macroMedium)));
                auto macroCaricature=macroMedium;
                macroCaricature.captureInfluence=1.0f;
                macroCaricature.cornerSharpnessLoss=1.65f;
                macroCaricature.fieldCurvature=1.55f;
                macroCaricature.astigmatism=.52f;
                macroCaricature.radialSmear=.38f;
                macroCaricature.tangentialSmear=.32f;
                macroCaricature.fineDetail=.26f;
                macroCaricature.microContrast=.34f;
                macroCaricature.longitudinalCA=1.40f;
                macroCaricature.sphericalHalo=1.0f;
                macroCaricature.apertureResponse=.45f;
                macroCaricature.apertureRadius=10.0f;
                macroCaricature.apertureCatEye=.38f;
                saveISO("338-preset-close-focus-macro-caricature-iso.tiff",
                        displayPreview(render(engine,device,queue,iso,isoWidth,isoHeight,macroCaricature)));
            }
        }

        if (argc >= 6) {
            uint32_t realWidth = 0, realHeight = 0;
            auto real = loadEncodedTIFF(argv[5], realWidth, realHeight);
            if (real.empty()) { std::fprintf(stderr, "FAIL: unable to load real camera TIFF %s\n", argv[5]); return 10; }
            simd_float3 realMean = meanRGB(real);
            std::printf("iPhone encoded RGB means: %.6f %.6f %.6f\n", realMean.x, realMean.y, realMean.z);
            auto saveReal = [&](const std::string& name, const std::vector<simd_float4>& encoded) {
                if(!publishOutput(name))return;
                if(reviewOutputFloor>0&&std::atoi(name.c_str())<reviewOutputFloor)return;
                if (!writeTIFF(directory + "/" + name,
                               rec709Gamma24FromWorkingSpace(encoded, LDBWorkingColorSpaceDaVinciIntermediate),
                               realWidth, realHeight, true)) std::exit(11);
            };
            auto neutralReal = LDBNeutralOpticsParameters(realWidth, realHeight);
            neutralReal.workingColorSpace = LDBWorkingColorSpaceDaVinciIntermediate;
            if(passNumber==96) {
                saveReal("477-causal-optical-real-source.tiff",real);
                auto combined=neutralReal;
                combined.responseFieldOnset=.10f;
                combined.responseFieldFalloff=.95f;
                combined.cornerSharpnessLoss=1.35f;
                combined.fieldCurvature=1.05f;
                combined.astigmatism=.36f;
                combined.radialSmear=.28f;
                combined.tangentialSmear=.46f;
                combined.lateralCARed=.72f;
                combined.lateralCABlue=-.94f;
                combined.longitudinalCA=.38f;
                combined.apertureResponse=.48f;
                combined.apertureRadius=11.0f;
                combined.apertureShape=1;
                combined.apertureBladeCount=7;
                combined.apertureBladeCurvature=.62f;
                combined.apertureSoftness=.22f;
                combined.apertureCatEye=.32f;
                combined.apertureBokehSwirl=1.8f;
                saveReal("478-combined-causal-optics-real.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,combined));
            }
            if(passNumber==97) {
                saveReal("484-expanded-aperture-real-source.tiff",real);
                auto extended=neutralReal;
                extended.responseFieldOnset=.11f;
                extended.responseFieldFalloff=1.06f;
                extended.apertureResponse=.90f;
                extended.apertureRadius=18.0f;
                extended.apertureSoftness=.20f;
                extended.apertureCatEye=.68f;
                extended.apertureBokehSwirl=5.0f;
                saveReal("485-expanded-aperture-real-result.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,extended));
            }
            if(passNumber==98) {
                saveReal("489-bokeh-boundary-real-source.tiff",real);
                auto revised=neutralReal;
                revised.responseFieldOnset=.09f;
                revised.responseFieldFalloff=.92f;
                revised.apertureResponse=.96f;
                revised.apertureRadius=21.0f;
                revised.apertureSoftness=.18f;
                revised.apertureCatEye=.76f;
                revised.apertureBokehSwirl=8.0f;
                saveReal("490-demo-bokeh-swirl-real.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,revised));
            }
            if(passNumber==95) {
                saveReal("470-peripheral-prism-defocus-real-source.tiff",real);
                auto reconstruction=neutralReal;
                reconstruction.prismDistribution=LDBPrismRadialField;
                reconstruction.prismAmount=.46f;
                reconstruction.prismDispersion=.36f;
                reconstruction.fieldAspect=1.72f;
                reconstruction.responseFieldOnset=.30f;
                reconstruction.responseFieldFalloff=.88f;
                reconstruction.cornerSharpnessLoss=1.12f;
                reconstruction.fieldCurvature=.48f;
                reconstruction.astigmatism=.18f;
                reconstruction.tangentialSmear=.18f;
                reconstruction.lateralCARed=.55f;
                reconstruction.lateralCABlue=-.72f;
                reconstruction.microContrast=-.18f;
                reconstruction.fineDetail=-.10f;
                saveReal("471-peripheral-prism-defocus-real.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,reconstruction));
            }
            if(passNumber>=89&&passNumber<=91) {
                const bool revisedWear=passNumber>=90;
                const bool refinedWear=passNumber==91;
                saveReal(refinedWear?"436-front-wear-real-source.tiff"
                         :(revisedWear?"426-front-wear-real-source.tiff"
                                      :"416-front-wear-real-source.tiff"),real);
                auto combined=neutralReal;
                combined.frontHaze=.75f;
                combined.cleaningMarks=revisedWear?.95f:.80f;
                combined.scratchAmount=refinedWear?.40f:(revisedWear?.60f:.45f);
                combined.scratchDirection=28.0f;
                combined.damageScale=1.35f;
                combined.coatingWear=refinedWear?1.05f:(revisedWear?.80f:.65f);
                combined.coatingWearScale=1.45f;
                combined.damageSeed=31415;
                saveReal(refinedWear?"437-front-wear-real-combined-moderate.tiff"
                         :(revisedWear?"427-front-wear-real-combined-moderate.tiff"
                                      :"417-front-wear-real-combined-moderate.tiff"),render(
                    engine,device,queue,real,realWidth,realHeight,combined));
                combined.frontHaze=1.35f;
                combined.cleaningMarks=1.45f;
                combined.scratchAmount=refinedWear?.75f:1.0f;
                combined.coatingWear=refinedWear?1.55f:1.25f;
                saveReal(refinedWear?"438-front-wear-real-combined-strong.tiff"
                         :(revisedWear?"428-front-wear-real-combined-strong.tiff"
                                      :"418-front-wear-real-combined-strong.tiff"),render(
                    engine,device,queue,real,realWidth,realHeight,combined));
            }
            if(passNumber==88) {
                saveReal("405-internal-strength-real-source.tiff",real);
                auto contamination=neutralReal;
                contamination.internalDirtScale=.62f;
                contamination.internalDirtSmear=.52f;
                contamination.internalDirtScatter=1.45f;
                contamination.internalDirtSoftness=.78f;
                contamination.internalDirtComplexity=.78f;
                contamination.internalDirtSeed=16180;
                contamination.internalDirtAmount=2.5f;
                saveReal("406-internal-strength-real-amount-2-5.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,contamination));
                contamination.internalDirtAmount=4.0f;
                saveReal("407-internal-strength-real-amount-4.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,contamination));
                contamination.internalDirtAmount=6.0f;
                saveReal("408-internal-strength-real-amount-6.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,contamination));
            }
            if(passNumber==95) {
                save("463-prism-distribution-chart-source.tiff",displayPreview(input));
                auto prism=LDBNeutralOpticsParameters(width,height);
                prism.prismAmount=.72f;
                prism.prismDirection=12.0f;
                prism.prismDispersion=.48f;
                prism.prismEdgeBias=.55f;
                prism.prismSoftness=.38f;
                save("464-prism-linear-edge.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prism)));
                prism.prismDistribution=LDBPrismUniform;
                save("465-prism-uniform.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prism)));
                prism.prismDistribution=LDBPrismBilateral;
                prism.fieldAspect=1.65f;
                prism.fieldRotation=8.0f;
                prism.responseFieldOnset=.22f;
                prism.responseFieldFalloff=.78f;
                save("466-prism-bilateral-field.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prism)));
                prism.prismDistribution=LDBPrismRadialField;
                prism.prismDirection=0.0f;
                save("467-prism-radial-field.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prism)));
                prism.prismDistribution=LDBPrismInverseField;
                prism.prismDirection=12.0f;
                save("468-prism-inverse-field.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prism)));
                auto reconstruction=LDBNeutralOpticsParameters(width,height);
                reconstruction.prismDistribution=LDBPrismRadialField;
                reconstruction.prismAmount=.46f;
                reconstruction.prismDispersion=.36f;
                reconstruction.fieldAspect=1.72f;
                reconstruction.responseFieldOnset=.30f;
                reconstruction.responseFieldFalloff=.88f;
                reconstruction.cornerSharpnessLoss=1.12f;
                reconstruction.fieldCurvature=.48f;
                reconstruction.astigmatism=.18f;
                reconstruction.tangentialSmear=.18f;
                reconstruction.lateralCARed=.55f;
                reconstruction.lateralCABlue=-.72f;
                reconstruction.microContrast=-.18f;
                reconstruction.fineDetail=-.10f;
                save("469-peripheral-prism-defocus-chart.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,reconstruction)));
            }

            if(passNumber==87) {
                saveReal("399-internal-contamination-real-source.tiff",real);
                auto contamination=neutralReal;
                contamination.internalDirtAmount=1.95f;
                contamination.internalDirtScale=.62f;
                contamination.internalDirtSmear=.52f;
                contamination.internalDirtScatter=1.45f;
                contamination.internalDirtSoftness=.78f;
                contamination.internalDirtComplexity=.78f;
                contamination.internalDirtSeed=16180;
                saveReal("400-internal-contamination-real-localized.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,contamination));
            }
            if(passNumber==86) {
                saveReal("393-highlight-wear-real-source.tiff",real);
                auto highlightResponse=neutralReal;
                highlightResponse.responseHighlightKnee=.72f;
                highlightResponse.bloomEnergy=.38f;
                highlightResponse.bloomThreshold=.72f;
                highlightResponse.bloomRadius=28.0f;
                highlightResponse.glareEnergy=.24f;
                highlightResponse.glareRadius=44.0f;
                highlightResponse.sphericalHalo=.20f;
                highlightResponse.coma=.14f;
                highlightResponse.comaThreshold=.68f;
                saveReal("394-highlight-response-real-shadow-safe.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,highlightResponse));
                auto frontWear=neutralReal;
                frontWear.frontHaze=.90f;
                frontWear.cleaningMarks=1.15f;
                frontWear.scratchAmount=.68f;
                frontWear.scratchDirection=28.0f;
                frontWear.damageScale=1.35f;
                frontWear.coatingWear=.88f;
                frontWear.coatingWearScale=1.45f;
                frontWear.damageSeed=31415;
                saveReal("395-front-element-wear-real-retuned.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,frontWear));
                auto contamination=neutralReal;
                contamination.internalDirtAmount=1.8f;
                contamination.internalDirtScale=1.55f;
                contamination.internalDirtSmear=.38f;
                contamination.internalDirtScatter=1.05f;
                contamination.internalDirtSoftness=.72f;
                contamination.internalDirtComplexity=.72f;
                contamination.internalDirtSeed=16180;
                saveReal("396-internal-contamination-real-retuned.tiff",render(
                    engine,device,queue,real,realWidth,realHeight,contamination));
            }
            if(passNumber>=77) {
                std::vector<simd_float4> stageSource(size_t(width)*height,
                                                     simd_float4{.015f,.018f,.022f,.82f});
                std::vector<simd_float4> stageDepth(size_t(width)*height,
                                                    simd_float4{.82f,.82f,.82f,1.0f});
                for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
                    bool nearLayer=x<width/2;
                    float depth=nearLayer?.18f:.82f;
                    stageSource[size_t(y)*width+x].w=depth;
                    stageDepth[size_t(y)*width+x]={depth,depth,depth,1.0f};
                    if((x%80u)<2u||(y%80u)<2u) {
                        float level=nearLayer?.10f:.055f;
                        stageSource[size_t(y)*width+x].xyz={level,level,level};
                    }
                }
                const int pointX[4]={int(width*.30f),int(width*.492f),
                                     int(width*.508f),int(width*.72f)};
                const int pointY[4]={int(height*.34f),int(height*.52f),
                                     int(height*.48f),int(height*.66f)};
                for(int point=0;point<4;++point)
                    for(int oy=-3;oy<=3;++oy) for(int ox=-3;ox<=3;++ox) {
                        int x=pointX[point]+ox,y=pointY[point]+oy;
                        float falloff=std::exp(-float(ox*ox+oy*oy)*.24f);
                        auto& pixel=stageSource[size_t(y)*width+size_t(x)];
                        pixel.xyz+=simd_float3{6.0f,5.2f,4.4f}*falloff;
                    }
                save("325-stage-depth-alignment-source.tiff",displayPreview(stageSource));
                save("326-stage-depth-alignment-map.tiff",displayPreview(stageDepth));

                auto staged=LDBNeutralOpticsParameters(width,height);
                staged.depthMode=2;
                staged.depthChannel=4;
                staged.depthFocus=.18f;
                staged.depthEdgeSoftness=.12f;
                staged.responseScatterEdgeProtection=1.0f;
                staged.distortionK1=-.16f;
                staged.distortionK2=.05f;
                staged.geometryFieldAmount=1.0f;
                staged.peripheralWarp=.42f;
                staged.responseFieldOnset=.12f;
                staged.responseFieldFalloff=.80f;
                staged.apertureResponse=1.0f;
                staged.apertureRadius=18.0f;
                staged.apertureShape=2;
                staged.apertureSoftness=.42f;
                auto depthFreeAperture=staged;
                depthFreeAperture.depthMode=0;
                save("327-stage-depth-free-aperture.tiff",displayPreview(render(
                    engine,device,queue,stageSource,width,height,depthFreeAperture)));
                save("328-stage-depth-aware-aperture.tiff",displayPreview(render(
                    engine,device,queue,stageSource,width,height,staged)));

                staged.apertureResponse=0.0f;
                staged.bloomEnergy=.85f;
                staged.bloomThreshold=.55f;
                staged.bloomRadius=28.0f;
                auto depthFreeScatter=staged;
                depthFreeScatter.depthMode=0;
                save("329-stage-depth-free-scatter.tiff",displayPreview(render(
                    engine,device,queue,stageSource,width,height,depthFreeScatter)));
                save("330-stage-depth-aware-scatter.tiff",displayPreview(render(
                    engine,device,queue,stageSource,width,height,staged)));

                // Golden Portrait's field/detail/tonal progression is judged
                // on detailed real footage. Close-Focus Macro uses the ISO
                // chart above so centre-versus-field transfer remains legible.
                saveReal("331-preset-golden-portrait-real-source.tiff",real);
                auto goldenSubtle=neutralReal;
                goldenSubtle.cornerSharpnessLoss=.18f;
                goldenSubtle.fieldCurvature=.10f;
                goldenSubtle.fineDetail=.05f;
                goldenSubtle.microContrast=.12f;
                goldenSubtle.responseFieldOnset=.28f;
                goldenSubtle.responseFieldFalloff=1.62f;
                goldenSubtle.lateralCARed=.12f;
                goldenSubtle.lateralCABlue=-.15f;
                goldenSubtle.glareEnergy=.05f;
                goldenSubtle.glareRadius=34.0f;
                goldenSubtle.transmissionColorAmount=.10f;
                goldenSubtle.transmissionColor={1.0f,.96f,.86f};
                saveReal("332-preset-golden-portrait-subtle-real.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,goldenSubtle));

                auto goldenMedium=goldenSubtle;
                goldenMedium.cornerSharpnessLoss=.58f;
                goldenMedium.fieldCurvature=.34f;
                goldenMedium.astigmatism=.08f;
                goldenMedium.fineDetail=.09f;
                goldenMedium.microContrast=.25f;
                goldenMedium.lateralCARed=.24f;
                goldenMedium.lateralCABlue=-.30f;
                goldenMedium.longitudinalCA=.10f;
                goldenMedium.glareEnergy=.18f;
                goldenMedium.glareRadius=40.0f;
                goldenMedium.sphericalHalo=.07f;
                goldenMedium.transmissionColorAmount=.28f;
                goldenMedium.transmissionHighlightSoftness=.22f;
                saveReal("333-preset-golden-portrait-medium-real.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,goldenMedium));

                auto goldenCaricature=goldenMedium;
                goldenCaricature.cornerSharpnessLoss=.95f;
                goldenCaricature.fieldCurvature=.62f;
                goldenCaricature.astigmatism=.16f;
                goldenCaricature.fineDetail=.12f;
                goldenCaricature.microContrast=.38f;
                goldenCaricature.lateralCARed=.40f;
                goldenCaricature.lateralCABlue=-.50f;
                goldenCaricature.longitudinalCA=.38f;
                goldenCaricature.glareEnergy=.38f;
                goldenCaricature.glareRadius=46.0f;
                goldenCaricature.sphericalHalo=.32f;
                goldenCaricature.transmissionColorAmount=.48f;
                goldenCaricature.transmissionHighlightSoftness=.42f;
                saveReal("334-preset-golden-portrait-caricature-real.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,goldenCaricature));
            }

            if(passNumber>=76) {
                saveReal("321-cloud-amount-real-source.tiff",real);
                auto cloudAmount=neutralReal;
                cloudAmount.internalDirtScale=1.0f;
                cloudAmount.internalDirtSmear=.34f;
                cloudAmount.internalDirtScatter=0.0f;
                cloudAmount.internalDirtSoftness=.72f;
                cloudAmount.internalDirtComplexity=.75f;
                cloudAmount.internalDirtSeed=16180;
                cloudAmount.internalDirtAmount=1.0f;
                saveReal("322-cloud-amount-real-conservative.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudAmount));
                cloudAmount.internalDirtAmount=5.0f;
                saveReal("323-cloud-amount-real-medium.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudAmount));
                cloudAmount.internalDirtAmount=10.0f;
                saveReal("324-cloud-amount-real-extreme.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudAmount));
            }
            if(passNumber>=68) {
                saveReal("314-cloud-real-source.tiff",real);
                auto cloudBroad=neutralReal;
                cloudBroad.internalDirtAmount=1.35f;
                cloudBroad.internalDirtScale=1.0f;
                cloudBroad.internalDirtSmear=.34f;
                cloudBroad.internalDirtScatter=0.0f;
                cloudBroad.internalDirtSoftness=.74f;
                cloudBroad.internalDirtComplexity=0.0f;
                cloudBroad.internalDirtSeed=16180;
                saveReal("315-cloud-real-smooth-broad.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudBroad));
                auto cloudComplex=cloudBroad;
                cloudComplex.internalDirtComplexity=1.0f;
                saveReal("316-cloud-real-smooth-complex.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudComplex));
            }
            if(passNumber>=67) {
                saveReal("307-cloud-real-source.tiff",real);
                auto cloudBroad=neutralReal;
                cloudBroad.internalDirtAmount=1.35f;
                cloudBroad.internalDirtScale=1.0f;
                cloudBroad.internalDirtSmear=.34f;
                cloudBroad.internalDirtScatter=1.15f;
                cloudBroad.internalDirtSoftness=.74f;
                cloudBroad.internalDirtComplexity=0.0f;
                cloudBroad.internalDirtSeed=16180;
                saveReal("308-cloud-real-broad-veil.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudBroad));
                auto cloudComplex=cloudBroad;
                cloudComplex.internalDirtComplexity=1.0f;
                saveReal("309-cloud-real-complex-veil.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudComplex));
            }
            if(passNumber>=66) {
                saveReal("300-cloud-real-source.tiff",real);
                auto cloudReal=neutralReal;
                cloudReal.internalDirtAmount=1.5f;
                cloudReal.internalDirtScale=1.0f;
                cloudReal.internalDirtSmear=.38f;
                cloudReal.internalDirtScatter=1.1f;
                cloudReal.internalDirtSoftness=.72f;
                cloudReal.internalDirtComplexity=1.0f;
                cloudReal.internalDirtSeed=16180;
                saveReal("301-cloud-real-multiscale.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudReal));
            }
            if(passNumber>=65) {
                saveReal("291-cloud-real-source.tiff",real);
                auto cloudReal=neutralReal;
                cloudReal.internalDirtAmount=1.35f;
                cloudReal.internalDirtScale=1.1f;
                cloudReal.internalDirtSmear=.42f;
                cloudReal.internalDirtScatter=.82f;
                cloudReal.internalDirtSoftness=.78f;
                cloudReal.internalDirtComplexity=1.0f;
                cloudReal.internalDirtSeed=16180;
                saveReal("292-cloud-real-soft-multiscale.tiff",
                         render(engine,device,queue,real,realWidth,realHeight,cloudReal));
            }
            saveReal("50-iphone-dwg-neutral-rec709-g24.tiff", real);
            saveReal("132-iphone-hawk-integration-source.tiff",real);
            auto hawkCoreReal=neutralReal;
            hawkCoreReal.anamorphicFlareAmount=.72f;
            hawkCoreReal.anamorphicFlareRadius=190.0f;
            hawkCoreReal.anamorphicFlareThreshold=.48f;
            hawkCoreReal.anamorphicFlareColor={.16f,.38f,1.0f};
            hawkCoreReal.anamorphicFlareCoreAmount=.42f;
            hawkCoreReal.anamorphicFlareAsymmetry=-.24f;
            saveReal("133-iphone-hawk-flare-core-integration.tiff",
                     render(engine,device,queue,real,realWidth,realHeight,hawkCoreReal));
            auto hawkFullReal=hawkCoreReal;
            hawkFullReal.anamorphicFlareGhostAmount=.20f;
            hawkFullReal.anamorphicFlareGhostPosition=-.72f;
            hawkFullReal.anamorphicFlareGhostScale=.88f;
            hawkFullReal.anamorphicFlareGhostColor={.48f,.18f,.82f};
            saveReal("134-iphone-hawk-full-flare-integration.tiff",
                     render(engine,device,queue,real,realWidth,realHeight,hawkFullReal));
            auto modernReal = neutralReal;
            modernReal.distortionK1=-.012f; modernReal.vignetteNatural=.05f;
            modernReal.cornerSharpnessLoss=.12f;
            modernReal.microContrast=.10f; modernReal.fineDetail=.08f;
            modernReal.bloomThreshold=.45f; modernReal.bloomEnergy=.10f; modernReal.bloomRadius=7;
            saveReal("51-iphone-modern-rec709-g24.tiff", render(engine, device, queue, real, realWidth, realHeight, modernReal));
            auto vintageReal = neutralReal;
            vintageReal.distortionK1=-.045f; vintageReal.distortionK2=.012f;
            vintageReal.vignetteNatural=.12f; vintageReal.vignetteOptical=.05f;
            vintageReal.cornerSharpnessLoss=.50f; vintageReal.astigmatism=.40f; vintageReal.coma=.30f;
            vintageReal.sphericalHalo=.25f; vintageReal.fieldCurvature=.35f;
            vintageReal.microContrast=-.08f; vintageReal.fineDetail=-.12f;
            vintageReal.detailEdgeFalloff=.45f; vintageReal.sagittalDetail=-.12f;
            vintageReal.tangentialDetail=-.30f; vintageReal.detailScale=1.5f;
            vintageReal.lateralCARed=.20f; vintageReal.lateralCABlue=-.24f;
            vintageReal.bloomThreshold=.35f; vintageReal.bloomEnergy=.22f; vintageReal.bloomRadius=14;
            vintageReal.transmissionColor={1,.94f,.82f}; vintageReal.transmissionColorAmount=.14f;
            saveReal("52-iphone-vintage-rec709-g24.tiff", render(engine, device, queue, real, realWidth, realHeight, vintageReal));
            auto anamorphicReal = vintageReal;
            anamorphicReal.bloomHorizontalStretch=5; anamorphicReal.bloomEnergy=.30f;
            anamorphicReal.glareEnergy=.14f; anamorphicReal.glareRadius=36;
            saveReal("53-iphone-anamorphic-rec709-g24.tiff", render(engine, device, queue, real, realWidth, realHeight, anamorphicReal));
        }
        if (argc >= 7) {
            uint32_t arriWidth = 0, arriHeight = 0;
            auto arri = loadEncodedTIFF(argv[6], arriWidth, arriHeight);
            if (arri.empty()) { std::fprintf(stderr, "FAIL: unable to load ARRI TIFF %s\n", argv[6]); return 12; }
            simd_float3 arriMean = meanRGB(arri);
            std::printf("ARRI encoded RGB means: %.6f %.6f %.6f\n", arriMean.x, arriMean.y, arriMean.z);
            CubeLUT arriReveal;
            constexpr const char* arriRevealPath = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT/Arri/ARRI_LogC4_v1_LUT_Package/LUTs/ARRI_LogC4-to-Gamma24_Rec709-D65_v1-65.cube";
            if (!arriReveal.load(arriRevealPath)) {
                std::fprintf(stderr, "FAIL: unable to load ARRI REVEAL LUT %s\n", arriRevealPath); return 15;
            }
            std::printf("ARRI display LUT: ARRI_LogC4-to-Gamma24_Rec709-D65_v1-65.cube\n");
            auto saveARRI = [&](const std::string& name, const std::vector<simd_float4>& encoded) {
                if(!publishOutput(name))return;
                if(reviewOutputFloor>0&&std::atoi(name.c_str())<reviewOutputFloor)return;
                if (!writeTIFF(directory + "/" + name,
                               applyDisplayLUT(encoded, arriReveal),
                               arriWidth, arriHeight, true)) std::exit(13);
            };
            auto neutralARRI = LDBNeutralOpticsParameters(arriWidth, arriHeight);
            neutralARRI.workingColorSpace = LDBWorkingColorSpaceARRILogC4;
            saveARRI("60-arri-logc4-neutral-rec709-g24.tiff", arri);
            auto modernARRI = neutralARRI;
            modernARRI.distortionK1=-.012f; modernARRI.vignetteNatural=.05f;
            modernARRI.cornerSharpnessLoss=.12f;
            modernARRI.microContrast=.10f; modernARRI.fineDetail=.08f;
            modernARRI.bloomThreshold=.45f; modernARRI.bloomEnergy=.10f; modernARRI.bloomRadius=7;
            saveARRI("61-arri-modern-rec709-g24.tiff", render(engine, device, queue, arri, arriWidth, arriHeight, modernARRI));
            auto vintageARRI = neutralARRI;
            vintageARRI.distortionK1=-.045f; vintageARRI.distortionK2=.012f;
            vintageARRI.vignetteNatural=.12f; vintageARRI.vignetteOptical=.05f;
            vintageARRI.cornerSharpnessLoss=.50f; vintageARRI.astigmatism=.40f; vintageARRI.coma=.30f;
            vintageARRI.sphericalHalo=.25f; vintageARRI.fieldCurvature=.35f;
            vintageARRI.microContrast=-.08f; vintageARRI.fineDetail=-.12f;
            vintageARRI.detailEdgeFalloff=.45f; vintageARRI.sagittalDetail=-.12f;
            vintageARRI.tangentialDetail=-.30f; vintageARRI.detailScale=1.5f;
            vintageARRI.lateralCARed=.20f; vintageARRI.lateralCABlue=-.24f;
            vintageARRI.bloomThreshold=.35f; vintageARRI.bloomEnergy=.22f; vintageARRI.bloomRadius=14;
            vintageARRI.transmissionColor={1,.94f,.82f}; vintageARRI.transmissionColorAmount=.14f;
            saveARRI("62-arri-vintage-rec709-g24.tiff", render(engine, device, queue, arri, arriWidth, arriHeight, vintageARRI));
            auto exoticARRI = vintageARRI;
            exoticARRI.swirl=.35f; exoticARRI.fieldCurvature=.45f;
            exoticARRI.radialSmear=.65f; exoticARRI.tangentialSmear=.35f;
            saveARRI("63-arri-exotic-rec709-g24.tiff", render(engine, device, queue, arri, arriWidth, arriHeight, exoticARRI));
            auto bodycamARRI = neutralARRI;
            bodycamARRI.geometryFieldAmount=1;
            bodycamARRI.peripheralStretch=.12f; bodycamARRI.peripheralWarp=.22f;
            bodycamARRI.distortionK1=-.006f; bodycamARRI.distortionK2=.020f; bodycamARRI.moustacheK3=.03f;
            bodycamARRI.responseFieldOnset=.34f; bodycamARRI.responseFieldFalloff=1.72f;
            bodycamARRI.cornerSharpnessLoss=1.20f; bodycamARRI.fieldCurvature=.96f;
            bodycamARRI.radialSmear=.28f; bodycamARRI.tangentialSmear=.34f;
            bodycamARRI.lateralCARed=1.55f; bodycamARRI.lateralCABlue=-1.95f;
            bodycamARRI.longitudinalCA=.28f;
            bodycamARRI.apertureResponse=.20f; bodycamARRI.apertureRadius=7.5f;
            bodycamARRI.apertureCatEye=.28f;
            bodycamARRI.vignetteMechanical=.50f; bodycamARRI.imageCircleSize=.94f;
            bodycamARRI.imageCircleAspect=1; bodycamARRI.imageCircleSoftness=.36f;
            bodycamARRI.refractiveIrregularity=.55f; bodycamARRI.refractiveScale=1.35f;
            bodycamARRI.refractiveEdgeBias=.84f; bodycamARRI.refractiveAnisotropy=.36f;
            bodycamARRI.refractiveRotation=-12; bodycamARRI.refractiveDispersion=.55f;
            bodycamARRI.refractiveSeed=28052023;
            bodycamARRI.frontHaze=.12f; bodycamARRI.coatingWear=.18f;
            bodycamARRI.damageScale=1.6f; bodycamARRI.damageSeed=28052023;
            saveARRI("64-arri-bodycam-edge-stress-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamARRI));
            auto bodycamAnnular = neutralARRI;
            bodycamAnnular.geometryFieldAmount=1;
            bodycamAnnular.peripheralStretch=.03f;
            bodycamAnnular.distortionK1=-.012f; bodycamAnnular.distortionK2=.040f;
            bodycamAnnular.moustacheK3=.06f;
            bodycamAnnular.responseFieldOnset=.20f; bodycamAnnular.responseFieldFalloff=1.15f;
            bodycamAnnular.cornerSharpnessLoss=1.80f; bodycamAnnular.fieldCurvature=1.45f;
            bodycamAnnular.radialSmear=.40f; bodycamAnnular.tangentialSmear=.52f;
            bodycamAnnular.lateralCARed=1.80f; bodycamAnnular.lateralCABlue=-2.25f;
            bodycamAnnular.longitudinalCA=.30f;
            bodycamAnnular.apertureResponse=.75f; bodycamAnnular.apertureRadius=16.0f;
            bodycamAnnular.apertureCatEye=.30f;
            bodycamAnnular.vignetteMechanical=1; bodycamAnnular.imageCircleSize=1.30f;
            bodycamAnnular.imageCircleAspect=1; bodycamAnnular.imageCircleSoftness=.10f;
            bodycamAnnular.frontHaze=.10f; bodycamAnnular.coatingWear=.12f;
            bodycamAnnular.damageScale=1.6f; bodycamAnnular.damageSeed=28052023;
            saveARRI("64a-arri-bodycam-strong-annular-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamAnnular));
            auto bodycamRefractive = bodycamAnnular;
            bodycamRefractive.peripheralWarp=.03f;
            bodycamRefractive.refractiveIrregularity=.15f; bodycamRefractive.refractiveScale=1.45f;
            bodycamRefractive.refractiveEdgeBias=.90f; bodycamRefractive.refractiveAnisotropy=.25f;
            bodycamRefractive.refractiveRotation=-12; bodycamRefractive.refractiveDispersion=.32f;
            bodycamRefractive.refractiveSeed=28052023;
            saveARRI("64b-arri-bodycam-annular-refraction-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamRefractive));
            auto bodycamHeavyEdge = bodycamRefractive;
            bodycamHeavyEdge.responseFieldOnset=.16f; bodycamHeavyEdge.responseFieldFalloff=1.10f;
            bodycamHeavyEdge.cornerSharpnessLoss=2.0f; bodycamHeavyEdge.fieldCurvature=1.75f;
            bodycamHeavyEdge.radialSmear=.55f; bodycamHeavyEdge.tangentialSmear=.72f;
            bodycamHeavyEdge.apertureResponse=1.0f; bodycamHeavyEdge.apertureRadius=20.0f;
            bodycamHeavyEdge.vignetteMechanical=1; bodycamHeavyEdge.imageCircleSize=1.28f;
            bodycamHeavyEdge.imageCircleSoftness=.06f;
            bodycamHeavyEdge.lateralCARed=2.65f; bodycamHeavyEdge.lateralCABlue=-3.35f;
            saveARRI("64c-arri-bodycam-maximum-annular-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamHeavyEdge));
            saveARRI("64-final-arri-bodycam-optical-field-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamHeavyEdge));
            auto bodycamAmplified = bodycamHeavyEdge;
            bodycamAmplified.responseFieldOnset=.13f; bodycamAmplified.responseFieldFalloff=1.02f;
            bodycamAmplified.radialSmear=.90f; bodycamAmplified.tangentialSmear=1.10f;
            bodycamAmplified.apertureRadius=24.0f;
            bodycamAmplified.lateralCARed=4.0f; bodycamAmplified.lateralCABlue=-5.0f;
            bodycamAmplified.refractiveIrregularity=.30f; bodycamAmplified.refractiveEdgeBias=1.0f;
            bodycamAmplified.refractiveDispersion=.60f;
            saveARRI("65a-arri-bodycam-amplified-balanced-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamAmplified));
            auto bodycamAmplifiedRefraction = bodycamAmplified;
            bodycamAmplifiedRefraction.refractiveIrregularity=.65f;
            bodycamAmplifiedRefraction.refractiveScale=.85f;
            bodycamAmplifiedRefraction.refractiveAnisotropy=.38f;
            bodycamAmplifiedRefraction.refractiveDispersion=1.10f;
            saveARRI("65b-arri-bodycam-amplified-refraction-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamAmplifiedRefraction));
            auto bodycamAmplifiedMaximum = bodycamAmplified;
            bodycamAmplifiedMaximum.responseFieldOnset=.10f; bodycamAmplifiedMaximum.responseFieldFalloff=.92f;
            bodycamAmplifiedMaximum.radialSmear=1.25f; bodycamAmplifiedMaximum.tangentialSmear=1.55f;
            bodycamAmplifiedMaximum.lateralCARed=6.0f; bodycamAmplifiedMaximum.lateralCABlue=-7.0f;
            bodycamAmplifiedMaximum.refractiveIrregularity=.45f;
            bodycamAmplifiedMaximum.refractiveDispersion=.90f;
            saveARRI("65c-arri-bodycam-amplified-maximum-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamAmplifiedMaximum));
            auto bodycamEdgeCAStrong = bodycamAmplifiedMaximum;
            bodycamEdgeCAStrong.lateralCARed=4.0f; bodycamEdgeCAStrong.lateralCABlue=-5.0f;
            bodycamEdgeCAStrong.refractiveDispersion=.60f;
            saveARRI("66a-arri-bodycam-edge-ca-strong-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamEdgeCAStrong));
            auto bodycamEdgeCAPronounced = bodycamAmplifiedMaximum;
            bodycamEdgeCAPronounced.lateralCARed=6.0f; bodycamEdgeCAPronounced.lateralCABlue=-7.0f;
            bodycamEdgeCAPronounced.refractiveDispersion=.90f;
            saveARRI("66b-arri-bodycam-edge-ca-pronounced-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamEdgeCAPronounced));
            auto bodycamEdgeCAMaximum = bodycamAmplifiedMaximum;
            bodycamEdgeCAMaximum.lateralCARed=9.0f; bodycamEdgeCAMaximum.lateralCABlue=-10.0f;
            bodycamEdgeCAMaximum.refractiveDispersion=1.40f;
            saveARRI("66c-arri-bodycam-edge-ca-maximum-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamEdgeCAMaximum));
            saveARRI("67a-arri-bodycam-chromatic-defocus-strong-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamEdgeCAStrong));
            saveARRI("67b-arri-bodycam-chromatic-defocus-pronounced-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamEdgeCAPronounced));
            auto bodycamLocalizedWide=bodycamEdgeCAStrong;
            bodycamLocalizedWide.responseFieldOnset=.18f;
            bodycamLocalizedWide.responseFieldFalloff=.84f;
            saveARRI("68a-arri-bodycam-localized-ca-wide-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamLocalizedWide));
            auto bodycamLocalizedPerimeter=bodycamEdgeCAPronounced;
            bodycamLocalizedPerimeter.responseFieldOnset=.26f;
            bodycamLocalizedPerimeter.responseFieldFalloff=.74f;
            saveARRI("68b-arri-bodycam-localized-ca-perimeter-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamLocalizedPerimeter));
            auto bodycamIndependentWide=bodycamEdgeCAStrong;
            bodycamIndependentWide.chromaticFieldOnset=.22f;
            bodycamIndependentWide.chromaticFieldFalloff=.68f;
            saveARRI("69a-arri-bodycam-independent-ca-wide-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamIndependentWide));
            auto bodycamIndependentPerimeter=bodycamEdgeCAPronounced;
            bodycamIndependentPerimeter.chromaticFieldOnset=.32f;
            bodycamIndependentPerimeter.chromaticFieldFalloff=.54f;
            saveARRI("69b-arri-bodycam-independent-ca-perimeter-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamIndependentPerimeter));
            saveARRI("70a-arri-bodycam-soft-ca-wide-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamIndependentWide));
            saveARRI("70b-arri-bodycam-soft-ca-perimeter-rec709-g24.tiff",
                     render(engine, device, queue, arri, arriWidth, arriHeight, bodycamIndependentPerimeter));
            auto internalDirtARRI=LDBNeutralOpticsParameters(arriWidth,arriHeight);
            internalDirtARRI.workingColorSpace=LDBWorkingColorSpaceARRILogC4;
            internalDirtARRI.internalDirtAmount=1.65f;internalDirtARRI.internalDirtScale=1.7f;
            internalDirtARRI.internalDirtSmear=.45f;internalDirtARRI.internalDirtScatter=1.35f;
            internalDirtARRI.internalDirtSeed=16180;
            saveARRI("115-arri-internal-dirt-rec709-g24.tiff",
                     render(engine,device,queue,arri,arriWidth,arriHeight,internalDirtARRI));
            auto internalWearARRI=internalDirtARRI;
            internalWearARRI.frontHaze=.6f;internalWearARRI.cleaningMarks=.7f;
            internalWearARRI.scratchAmount=.45f;internalWearARRI.scratchDirection=28;
            internalWearARRI.damageScale=1.25f;internalWearARRI.coatingWear=.7f;
            internalWearARRI.coatingWearScale=1.4f;internalWearARRI.damageSeed=31415;
            saveARRI("119-arri-internal-contamination-with-front-wear-rec709-g24.tiff",
                     render(engine,device,queue,arri,arriWidth,arriHeight,internalWearARRI));
        }
        if(argc>=10) {
            auto hawkReference=loadTIFFChart(argv[9],width,height);
            if(hawkReference.empty()) {
                std::fprintf(stderr,"FAIL: unable to load Hawk reference TIFF %s\n",argv[9]);
                return 16;
            }
            // Keep flare and pupil calibration independent. The reference frame
            // shows the real 55 mm lens wide open; the synthetic point chart then
            // exposes ovality, peripheral cat-eye closure and tangential rotation
            // without flare energy obscuring the pupil footprint.
            save("164-hawk-55mm-t22-reference.tiff",displayPreview(hawkReference));
            save("165-hawk-bokeh-chart-source.tiff",displayPreview(apertureChart));
            auto hawkBokehOval=LDBNeutralOpticsParameters(width,height);
            hawkBokehOval.anamorphicSqueeze=2.0f;
            hawkBokehOval.apertureResponse=1.0f;
            hawkBokehOval.apertureRadius=24.0f;
            hawkBokehOval.apertureShape=2;
            hawkBokehOval.apertureAspect=.48f;
            hawkBokehOval.apertureSoftness=.30f;
            hawkBokehOval.responseFieldOnset=.20f;
            hawkBokehOval.responseFieldFalloff=1.58f;
            save("166-hawk-bokeh-vertical-oval-baseline.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,hawkBokehOval)));
            auto hawkBokehCatEye=hawkBokehOval;
            hawkBokehCatEye.apertureCatEye=.22f;
            hawkBokehCatEye.apertureSoftness=.26f;
            save("167-hawk-bokeh-restrained-cat-eye.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,hawkBokehCatEye)));
            auto hawkBokehVintage=hawkBokehCatEye;
            hawkBokehVintage.apertureCatEye=.32f;
            hawkBokehVintage.apertureBokehSwirl=.28f;
            save("168-hawk-bokeh-restrained-cat-eye-rotation.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,hawkBokehVintage)));
            // The supplied Hawk TIFF is a photographed bokeh/portrait plate, not a
            // direct-light flare test. Add one compact, scene-linear lamp so this pass
            // tests the flare hierarchy against the ShareGrid 55 mm T4 reference:
            // white core, continuous cyan streak, cool veil, restrained violet ghosts.
            auto hawkDirectLight=hawkReference;
            const float lampX=.155f*float(width), lampY=.165f*float(height);
            for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
                const float dx=float(x)-lampX,dy=float(y)-lampY;
                const float core=18.0f*std::exp(-(dx*dx+dy*dy)/(2.0f*9.0f*9.0f));
                const float halo=3.5f*std::exp(-(dx*dx+dy*dy)/(2.0f*34.0f*34.0f));
                const simd_float3 lamp={core+halo,(core+halo)*.98f,(core+halo)*.90f};
                hawkDirectLight[size_t(y)*width+x].x+=lamp.x;
                hawkDirectLight[size_t(y)*width+x].y+=lamp.y;
                hawkDirectLight[size_t(y)*width+x].z+=lamp.z;
            }
            save("188-hawk-tight-flare-source.tiff",displayPreview(hawkDirectLight));
            auto hawkMatch=LDBNeutralOpticsParameters(width,height);
            hawkMatch.anamorphicFlareAmount=1.42f;
            hawkMatch.anamorphicFlareRadius=2200.0f;
            hawkMatch.anamorphicFlareThreshold=.42f;
            hawkMatch.anamorphicFlareColor={.22f,.52f,1.0f};
            hawkMatch.anamorphicFlareCoreAmount=.38f;
            hawkMatch.anamorphicFlareAsymmetry=.08f;
            hawkMatch.anamorphicFlareGhostAmount=.075f;
            hawkMatch.anamorphicFlareGhostPosition=-.70f;
            hawkMatch.anamorphicFlareGhostScale=.72f;
            hawkMatch.anamorphicFlareGhostColor={.30f,.18f,.68f};
            hawkMatch.anamorphicFlareThickness=.18f;
            save("189-hawk-tight-primary-streak.tiff",
                 displayPreview(render(engine,device,queue,hawkDirectLight,width,height,hawkMatch)));
            auto hawkBands70=hawkMatch;
            hawkBands70.anamorphicFlareBandAmount=2.0f;
            hawkBands70.anamorphicFlareBandSeparation=45.0f;
            save("190-hawk-tight-high-energy-bands.tiff",
                 displayPreview(render(engine,device,queue,hawkDirectLight,width,height,hawkBands70)));
            auto hawkSecondary=hawkBands70;
            hawkSecondary.anamorphicFlareSecondaryAmount=.68f;
            hawkSecondary.anamorphicFlareSecondaryOffset=230.0f;
            save("191-hawk-tight-secondary-streak.tiff",
                 displayPreview(render(engine,device,queue,hawkDirectLight,width,height,hawkSecondary)));
            auto hawkIntegrated=hawkSecondary;
            hawkIntegrated.glareEnergy=.62f;
            hawkIntegrated.glareRadius=500.0f;
            hawkIntegrated.glareColorAmount=.82f;
            hawkIntegrated.glareColor={.18f,.42f,1.0f};
            hawkIntegrated.bloomThreshold=.44f;
            hawkIntegrated.bloomEnergy=.10f;
            hawkIntegrated.bloomRadius=58.0f;
            auto hawkWideVeil=hawkIntegrated;
            hawkWideVeil.anamorphicFlareAmount=1.55f;
            hawkWideVeil.glareEnergy=.78f;
            hawkWideVeil.glareRadius=680.0f;
            hawkWideVeil.anamorphicFlareBandAmount=1.72f;
            hawkWideVeil.anamorphicFlareBandSeparation=48.0f;
            hawkWideVeil.anamorphicFlareSecondaryAmount=.62f;
            save("192-hawk-tight-reference-balance.tiff",
                 displayPreview(render(engine,device,queue,hawkDirectLight,width,height,hawkWideVeil)));
            auto hawkWithRays=hawkWideVeil;
            hawkWithRays.diffractionRayAmount=.08f;
            hawkWithRays.diffractionRayLength=145.0f;
            save("229-hawk-v-lite-restrained-rays.tiff",
                 displayPreview(render(engine,device,queue,hawkDirectLight,width,height,hawkWithRays)));
        }
        if(argc>=11) {
            auto cookeReference=loadTIFFChart(argv[10],width,height);
            if(cookeReference.empty()) {
                std::fprintf(stderr,"FAIL: unable to load Cooke Special reference TIFF %s\n",argv[10]);
                return 17;
            }
            save("198-cooke-special-50mm-t23-reference.tiff",displayPreview(cookeReference));
            save("199-cooke-special-bokeh-chart-source.tiff",displayPreview(apertureChart));

            // Cooke Special Flare is substantially more orderly than the Hawk:
            // a clean 2x oval pupil, soft rim, and little tangential rotation.
            auto cookeOval=LDBNeutralOpticsParameters(width,height);
            cookeOval.anamorphicSqueeze=2.0f;
            cookeOval.apertureResponse=1.0f;
            cookeOval.apertureRadius=23.0f;
            cookeOval.apertureShape=2;
            cookeOval.apertureAspect=.52f;
            cookeOval.apertureSoftness=.22f;
            // Reach full pupil reconstruction quickly enough to remove the
            // chart's pin-point cores while retaining only a small sharp island.
            cookeOval.responseFieldOnset=0.0f;
            cookeOval.responseFieldFalloff=.24f;
            save("200-cooke-special-filled-oval-baseline.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,cookeOval)));

            auto cookeCatEye=cookeOval;
            cookeCatEye.apertureCatEye=.26f;
            cookeCatEye.apertureBokehSwirl=.06f;
            save("201-cooke-special-visible-cat-eye.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,cookeCatEye)));

            auto cookeCharacter=cookeCatEye;
            // The photographed reference is already optically defocused and
            // contains baked letterbox bars. Do not convolve it a second time:
            // that incorrectly drags black bar pixels into the photographed image.
            cookeCharacter.apertureResponse=0.0f;
            cookeCharacter.fieldCurvature=.11f;
            cookeCharacter.astigmatism=.08f;
            cookeCharacter.cornerSharpnessLoss=.16f;
            cookeCharacter.microContrast=.94f;
            cookeCharacter.transmissionColor={1.035f,1.0f,.965f};
            cookeCharacter.transmissionColorAmount=.22f;
            cookeCharacter.sphericalHalo=.10f;
            save("202-cooke-special-clean-character-transfer.tiff",
                 displayPreview(render(engine,device,queue,cookeReference,width,height,cookeCharacter)));

            // ShareGrid's Cooke 50 mm T4 flare reference has a white source in
            // the upper-left, a thin cyan-blue streak, broad blue wash, one
            // prominent green ghost and a smaller blue-violet ghost. Keep each
            // component isolated before evaluating the combined hierarchy.
            auto cookeDirectLight=cookeReference;
            // The supplied flare references place the lamp roughly 28% down
            // the active frame. Keep it clear of this plate's baked upper bar
            // so both vertical diffraction lobes remain visible.
            const float cookeLampX=.155f*float(width),cookeLampY=.285f*float(height);
            for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
                const float dx=float(x)-cookeLampX,dy=float(y)-cookeLampY;
                const float core=19.0f*std::exp(-(dx*dx+dy*dy)/(2.0f*4.5f*4.5f));
                const float halo=2.2f*std::exp(-(dx*dx+dy*dy)/(2.0f*14.0f*14.0f));
                const simd_float3 lamp={core+halo,(core+halo)*.99f,(core+halo)*.94f};
                cookeDirectLight[size_t(y)*width+x].x+=lamp.x;
                cookeDirectLight[size_t(y)*width+x].y+=lamp.y;
                cookeDirectLight[size_t(y)*width+x].z+=lamp.z;
            }
            // The supplied 2.39 plate contains baked presentation bars. They are
            // not photographed scene energy, so restore them after the optical
            // render instead of allowing flare energy to illuminate them.
            auto protectCookeBars=[&](std::vector<simd_float4> rendered) {
                constexpr uint32_t protectedRows=140;
                for(uint32_t y=0;y<protectedRows;++y)
                    for(uint32_t x=0;x<width;++x)
                        rendered[size_t(y)*width+x]=cookeReference[size_t(y)*width+x];
                for(uint32_t y=height-protectedRows;y<height;++y)
                    for(uint32_t x=0;x<width;++x)
                        rendered[size_t(y)*width+x]=cookeReference[size_t(y)*width+x];
                return rendered;
            };
            save("224-cooke-special-tight-flare-source.tiff",displayPreview(cookeDirectLight));

            auto cookeFlare=LDBNeutralOpticsParameters(width,height);
            cookeFlare.anamorphicFlareAmount=.86f;
            cookeFlare.anamorphicFlareRadius=1900.0f;
            cookeFlare.anamorphicFlareThreshold=.46f;
            cookeFlare.anamorphicFlareColor={.16f,.58f,1.0f};
            cookeFlare.anamorphicFlareCoreAmount=.30f;
            cookeFlare.anamorphicFlareAsymmetry=.04f;
            cookeFlare.anamorphicFlareThickness=.075f;
            cookeFlare.anamorphicFlareBandAmount=.24f;
            cookeFlare.anamorphicFlareBandSeparation=18.0f;
            save("225-cooke-special-thin-streak-no-rays.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cookeFlare))));

            auto cookeRays=cookeFlare;
            cookeRays.diffractionRayAmount=.68f;
            cookeRays.diffractionRayLength=260.0f;
            save("226-cooke-special-tapered-rays-isolated.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cookeRays))));

            auto cookeLongRays=cookeRays;
            cookeLongRays.diffractionRayLength=430.0f;
            save("227-cooke-special-ray-length-comparison.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cookeLongRays))));

            auto cookeGhost=cookeFlare;
            cookeGhost.anamorphicFlareGhostAmount=.50f;
            cookeGhost.anamorphicFlareGhostPosition=.30f;
            cookeGhost.anamorphicFlareGhostScale=1.65f;
            cookeGhost.anamorphicFlareGhostColor={.22f,.82f,.42f};
            cookeGhost.anamorphicFlareSecondaryAmount=.08f;
            cookeGhost.anamorphicFlareSecondaryOffset=165.0f;
            auto cookeWash=cookeGhost;
            cookeWash.glareEnergy=.42f;
            cookeWash.glareRadius=650.0f;
            cookeWash.glareColorAmount=.66f;
            cookeWash.glareColor={.12f,.42f,.82f};
            cookeWash.bloomThreshold=.48f;
            cookeWash.bloomEnergy=.075f;
            cookeWash.bloomRadius=54.0f;
            auto cookeBalanced=cookeWash;
            cookeBalanced.anamorphicFlareAmount=.78f;
            cookeBalanced.anamorphicFlareBandAmount=.30f;
            cookeBalanced.anamorphicFlareGhostAmount=.44f;
            cookeBalanced.glareEnergy=.48f;
            cookeBalanced.glareRadius=720.0f;
            cookeBalanced.diffractionRayAmount=.62f;
            cookeBalanced.diffractionRayLength=245.0f;
            save("228-cooke-special-balanced-with-rays.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cookeBalanced))));

            save("230-cooke-special-preset-source.tiff",displayPreview(cookeDirectLight));
            auto cookePresetSubtle=cookeBalanced;
            cookePresetSubtle.anamorphicFlareAmount=.40f;
            cookePresetSubtle.anamorphicFlareRadius=1550.0f;
            cookePresetSubtle.anamorphicFlareThreshold=.62f;
            cookePresetSubtle.anamorphicFlareCoreAmount=.18f;
            cookePresetSubtle.anamorphicFlareGhostAmount=.18f;
            cookePresetSubtle.anamorphicFlareGhostScale=1.42f;
            cookePresetSubtle.anamorphicFlareBandAmount=.10f;
            cookePresetSubtle.diffractionRayAmount=.24f;
            cookePresetSubtle.diffractionRayLength=170.0f;
            cookePresetSubtle.glareEnergy=.16f;
            cookePresetSubtle.glareRadius=480.0f;
            cookePresetSubtle.bloomEnergy=.035f;
            save("231-cooke-special-preset-subtle.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cookePresetSubtle))));
            save("232-cooke-special-preset-medium-reference.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cookeBalanced))));
            auto cookePresetCaricature=cookeBalanced;
            cookePresetCaricature.anamorphicFlareAmount=1.18f;
            cookePresetCaricature.anamorphicFlareRadius=2250.0f;
            cookePresetCaricature.anamorphicFlareThreshold=.28f;
            cookePresetCaricature.anamorphicFlareThickness=.09f;
            cookePresetCaricature.anamorphicFlareCoreAmount=.46f;
            cookePresetCaricature.anamorphicFlareGhostAmount=.72f;
            cookePresetCaricature.anamorphicFlareGhostPosition=.34f;
            cookePresetCaricature.anamorphicFlareGhostScale=1.82f;
            cookePresetCaricature.anamorphicFlareBandAmount=.62f;
            cookePresetCaricature.anamorphicFlareBandSeparation=24.0f;
            cookePresetCaricature.anamorphicFlareSecondaryAmount=.18f;
            cookePresetCaricature.diffractionRayAmount=1.0f;
            cookePresetCaricature.diffractionRayLength=330.0f;
            cookePresetCaricature.glareEnergy=.82f;
            cookePresetCaricature.glareRadius=900.0f;
            cookePresetCaricature.bloomEnergy=.15f;
            save("233-cooke-special-preset-caricature.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cookePresetCaricature))));
            auto cookeMediumBokeh=cookeOval;
            cookeMediumBokeh.apertureResponse=.18f;
            cookeMediumBokeh.apertureRadius=7.0f;
            cookeMediumBokeh.apertureCatEye=.26f;
            cookeMediumBokeh.apertureBokehSwirl=.06f;
            save("234-cooke-special-medium-bokeh.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,cookeMediumBokeh)));

            save("235-cooke-special-preset-source.tiff",displayPreview(cookeDirectLight));
            auto cooke57Subtle=cookePresetSubtle;
            cooke57Subtle.anamorphicFlareAmount=.65f;
            cooke57Subtle.anamorphicFlareGhostAmount=.12f;
            cooke57Subtle.anamorphicFlareBandAmount=.18f;
            cooke57Subtle.diffractionRayAmount=.18f;
            save("236-cooke-special-preset-subtle.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cooke57Subtle))));
            auto cooke57Medium=cookeBalanced;
            cooke57Medium.anamorphicFlareAmount=1.30f;
            cooke57Medium.anamorphicFlareGhostAmount=.26f;
            cooke57Medium.anamorphicFlareBandAmount=.38f;
            cooke57Medium.diffractionRayAmount=.40f;
            save("237-cooke-special-preset-medium-reference.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cooke57Medium))));
            auto cooke57Caricature=cookePresetCaricature;
            cooke57Caricature.anamorphicFlareAmount=1.80f;
            cooke57Caricature.anamorphicFlareGhostAmount=.42f;
            cooke57Caricature.anamorphicFlareBandAmount=.75f;
            cooke57Caricature.diffractionRayAmount=.70f;
            save("238-cooke-special-preset-caricature.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDirectLight,width,height,cooke57Caricature))));
            save("239-cooke-special-medium-bokeh-literal.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,cookeMediumBokeh)));
            auto cookeCloseFocusBokeh=cookeMediumBokeh;
            cookeCloseFocusBokeh.apertureResponse=1.0f;
            cookeCloseFocusBokeh.apertureRadius=23.0f;
            save("240-cooke-special-close-focus-bokeh-shape.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,cookeCloseFocusBokeh)));

            // Match the supplied ShareGrid flare-room exposure rather than the
            // bright portrait plate. This makes streak, veil and ghost hierarchy
            // directly readable against a dark photographed environment.
            auto cookeDarkSource=cookeReference;
            for(auto& px:cookeDarkSource) {
                px.x*=.16f; px.y*=.16f; px.z*=.16f;
            }
            for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
                const float dx=float(x)-cookeLampX,dy=float(y)-cookeLampY;
                const float core=22.0f*std::exp(-(dx*dx+dy*dy)/(2.0f*4.0f*4.0f));
                const float halo=2.0f*std::exp(-(dx*dx+dy*dy)/(2.0f*15.0f*15.0f));
                cookeDarkSource[size_t(y)*width+x].x+=core+halo;
                cookeDarkSource[size_t(y)*width+x].y+=(core+halo)*.99f;
                cookeDarkSource[size_t(y)*width+x].z+=(core+halo)*.96f;
            }

            if(passNumber==85) {
                save("384-prism-chart-source.tiff",displayPreview(input));
                auto prismConservative=LDBNeutralOpticsParameters(width,height);
                prismConservative.prismAmount=.35f;
                prismConservative.prismDirection=12.0f;
                prismConservative.prismDispersion=.25f;
                prismConservative.prismEdgeBias=.62f;
                prismConservative.prismSoftness=.38f;
                save("385-prism-conservative-inward.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prismConservative)));
                auto prismMedium=prismConservative;
                prismMedium.prismAmount=.90f;
                prismMedium.prismDirection=16.0f;
                prismMedium.prismDispersion=.75f;
                prismMedium.prismEdgeBias=.52f;
                prismMedium.prismSoftness=.32f;
                save("386-prism-medium-inward.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prismMedium)));
                auto prismExtreme=prismMedium;
                prismExtreme.prismAmount=1.70f;
                prismExtreme.prismDirection=20.0f;
                prismExtreme.prismDispersion=1.50f;
                prismExtreme.prismEdgeBias=.38f;
                prismExtreme.prismSoftness=.22f;
                save("387-prism-extreme-inward.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prismExtreme)));
                auto prismOpposite=prismMedium;
                prismOpposite.prismDirection=-164.0f;
                save("388-prism-opposite-direction-inward.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,prismOpposite)));
            }

            if(passNumber==86) {
                save("389-highlight-wear-chart-source.tiff",displayPreview(input));
                auto highlightResponse=LDBNeutralOpticsParameters(width,height);
                highlightResponse.responseHighlightKnee=.72f;
                highlightResponse.bloomEnergy=.38f;
                highlightResponse.bloomThreshold=.72f;
                highlightResponse.bloomRadius=28.0f;
                highlightResponse.glareEnergy=.24f;
                highlightResponse.glareRadius=44.0f;
                highlightResponse.sphericalHalo=.20f;
                highlightResponse.coma=.14f;
                highlightResponse.comaThreshold=.68f;
                save("390-highlight-response-shadow-safe.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,highlightResponse)));
                auto frontWear=LDBNeutralOpticsParameters(width,height);
                frontWear.frontHaze=.90f;
                frontWear.cleaningMarks=1.15f;
                frontWear.scratchAmount=.68f;
                frontWear.scratchDirection=28.0f;
                frontWear.damageScale=1.35f;
                frontWear.coatingWear=.88f;
                frontWear.coatingWearScale=1.45f;
                frontWear.damageSeed=31415;
                save("391-front-element-wear-retuned.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,frontWear)));
                auto contamination=LDBNeutralOpticsParameters(width,height);
                contamination.internalDirtAmount=1.8f;
                contamination.internalDirtScale=1.55f;
                contamination.internalDirtSmear=.38f;
                contamination.internalDirtScatter=1.05f;
                contamination.internalDirtSoftness=.72f;
                contamination.internalDirtComplexity=.72f;
                contamination.internalDirtSeed=16180;
                save("392-internal-contamination-retuned.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,contamination)));
            }

            if(passNumber>=92&&passNumber<=94) {
                const int glareOutputBase=passNumber==94?455:(passNumber==93?447:439);
                auto glareOutput=[&](int offset,const char* suffix) {
                    return std::to_string(glareOutputBase+offset)+suffix;
                };
                save(glareOutput(0,"-glare-halo-chart-source.tiff"),displayPreview(input));
                save(glareOutput(1,"-glare-halo-hdr-source.tiff"),displayPreview(hdr));
                auto glareHalo=LDBNeutralOpticsParameters(width,height);
                glareHalo.glareEnergy=.58f;
                glareHalo.glareThreshold=.45f;
                glareHalo.glareRadius=74.0f;
                glareHalo.glareColor={1.0f,.72f,.46f};
                glareHalo.glareColorAmount=.34f;
                glareHalo.sphericalHalo=.58f;
                save(glareOutput(2,"-demo-glare-and-halo-chart.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,glareHalo)));
                save(glareOutput(3,"-demo-glare-and-halo-hdr.tiff"),displayPreview(render(
                    engine,device,queue,hdr,width,height,glareHalo)));
                auto glareOnly=glareHalo;
                glareOnly.sphericalHalo=0.0f;
                save(glareOutput(4,"-glare-only-scatter.tiff"),displayPreview(render(
                    engine,device,queue,hdr,width,height,glareOnly)));
                auto haloOnly=glareHalo;
                haloOnly.glareEnergy=0.0f;
                save(glareOutput(5,"-halo-only-scatter.tiff"),displayPreview(render(
                    engine,device,queue,hdr,width,height,haloOnly)));
                auto highlightResponse=LDBNeutralOpticsParameters(width,height);
                highlightResponse.responseHighlightKnee=.72f;
                highlightResponse.bloomEnergy=.38f;
                highlightResponse.bloomThreshold=.72f;
                highlightResponse.bloomRadius=28.0f;
                highlightResponse.glareEnergy=.24f;
                highlightResponse.glareThreshold=.72f;
                highlightResponse.glareRadius=44.0f;
                highlightResponse.sphericalHalo=.20f;
                highlightResponse.coma=.14f;
                highlightResponse.comaThreshold=.68f;
                save(glareOutput(6,"-demo-highlight-response-chart.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,highlightResponse)));
                auto combined=glareHalo;
                combined.bloomEnergy=.42f;
                combined.bloomThreshold=.72f;
                combined.bloomRadius=30.0f;
                combined.frontHaze=.75f;
                save(glareOutput(7,"-independent-bloom-glare-wear.tiff"),displayPreview(render(
                    engine,device,queue,hdr,width,height,combined)));
            }

            if(passNumber==87) {
                save("397-internal-contamination-chart-source.tiff",displayPreview(input));
                auto contamination=LDBNeutralOpticsParameters(width,height);
                contamination.internalDirtAmount=1.95f;
                contamination.internalDirtScale=.62f;
                contamination.internalDirtSmear=.52f;
                contamination.internalDirtScatter=1.45f;
                contamination.internalDirtSoftness=.78f;
                contamination.internalDirtComplexity=.78f;
                contamination.internalDirtSeed=16180;
                save("398-internal-contamination-localized.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,contamination)));
            }

            if(passNumber==88) {
                save("401-internal-strength-chart-source.tiff",displayPreview(input));
                auto contamination=LDBNeutralOpticsParameters(width,height);
                contamination.internalDirtScale=.62f;
                contamination.internalDirtSmear=.52f;
                contamination.internalDirtScatter=1.45f;
                contamination.internalDirtSoftness=.78f;
                contamination.internalDirtComplexity=.78f;
                contamination.internalDirtSeed=16180;
                contamination.internalDirtAmount=2.5f;
                save("402-internal-strength-amount-2-5.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,contamination)));
                contamination.internalDirtAmount=4.0f;
                save("403-internal-strength-amount-4.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,contamination)));
                contamination.internalDirtAmount=6.0f;
                save("404-internal-strength-amount-6.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,contamination)));
            }

            if(passNumber>=89&&passNumber<=91) {
                const bool revisedWear=passNumber>=90;
                const bool refinedWear=passNumber==91;
                save(refinedWear?"429-front-wear-chart-source.tiff"
                     :(revisedWear?"419-front-wear-chart-source.tiff"
                                  :"409-front-wear-chart-source.tiff"),displayPreview(input));
                auto haze=LDBNeutralOpticsParameters(width,height);
                haze.frontHaze=1.0f;
                save(refinedWear?"430-front-wear-haze-isolated.tiff"
                     :(revisedWear?"420-front-wear-haze-isolated.tiff"
                                  :"410-front-wear-haze-isolated.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,haze)));
                auto marks=LDBNeutralOpticsParameters(width,height);
                marks.cleaningMarks=1.0f;
                marks.damageScale=1.35f;
                marks.damageSeed=31415;
                save(refinedWear?"431-front-wear-cleaning-marks-isolated.tiff"
                     :(revisedWear?"421-front-wear-cleaning-marks-isolated.tiff"
                                  :"411-front-wear-cleaning-marks-isolated.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,marks)));
                auto scratches=LDBNeutralOpticsParameters(width,height);
                scratches.scratchAmount=1.0f;
                scratches.scratchDirection=28.0f;
                scratches.damageScale=1.35f;
                scratches.damageSeed=31415;
                save(refinedWear?"432-front-wear-scratches-isolated.tiff"
                     :(revisedWear?"422-front-wear-scratches-isolated.tiff"
                                  :"412-front-wear-scratches-isolated.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,scratches)));
                auto coating=LDBNeutralOpticsParameters(width,height);
                coating.coatingWear=1.0f;
                coating.coatingWearScale=1.45f;
                coating.damageSeed=31415;
                save(refinedWear?"433-front-wear-coating-isolated.tiff"
                     :(revisedWear?"423-front-wear-coating-isolated.tiff"
                                  :"413-front-wear-coating-isolated.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,coating)));
                auto combined=LDBNeutralOpticsParameters(width,height);
                combined.frontHaze=.75f;
                combined.cleaningMarks=revisedWear?.95f:.80f;
                combined.scratchAmount=refinedWear?.40f:(revisedWear?.60f:.45f);
                combined.scratchDirection=28.0f;
                combined.damageScale=1.35f;
                combined.coatingWear=refinedWear?1.05f:(revisedWear?.80f:.65f);
                combined.coatingWearScale=1.45f;
                combined.damageSeed=31415;
                save(refinedWear?"434-front-wear-combined-moderate.tiff"
                     :(revisedWear?"424-front-wear-combined-moderate.tiff"
                                  :"414-front-wear-combined-moderate.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,combined)));
                combined.frontHaze=1.35f;
                combined.cleaningMarks=1.45f;
                combined.scratchAmount=refinedWear?.75f:1.0f;
                combined.coatingWear=refinedWear?1.55f:1.25f;
                save(refinedWear?"435-front-wear-combined-strong.tiff"
                     :(revisedWear?"425-front-wear-combined-strong.tiff"
                                  :"415-front-wear-combined-strong.tiff"),displayPreview(render(
                    engine,device,queue,input,width,height,combined)));
            }

            if(passNumber==83) {
                std::vector<simd_float4> bubblePoints(size_t(width)*height,
                                                       simd_float4{0,0,0,1});
                for(int row=0;row<5;++row) for(int column=0;column<7;++column) {
                    int x=int((column+.5f)*float(width)/7.0f);
                    int y=int((row+.5f)*float(height)/5.0f);
                    bubblePoints[size_t(y)*width+size_t(x)]={8,8,8,1};
                }
                save("374-bubble-bokeh-point-source.tiff",displayPreview(bubblePoints));
                auto filledReference=LDBNeutralOpticsParameters(width,height);
                filledReference.responseFieldOnset=.08f;
                filledReference.responseFieldFalloff=.72f;
                filledReference.apertureResponse=1.0f;
                filledReference.apertureRadius=20.0f;
                filledReference.apertureShape=0;
                filledReference.apertureSoftness=.14f;
                filledReference.apertureCatEye=.24f;
                filledReference.apertureBokehSwirl=1.2f;
                save("375-filled-pupil-reference.tiff",displayPreview(render(
                    engine,device,queue,bubblePoints,width,height,filledReference)));
                auto bubbleDemo=filledReference;
                bubbleDemo.apertureRimWeight=.25f;
                save("376-demo-bubble-rim-filled-final.tiff",displayPreview(render(
                    engine,device,queue,bubblePoints,width,height,bubbleDemo)));
                auto bubbleMedium=LDBNeutralOpticsParameters(width,height);
                bubbleMedium.responseFieldOnset=.24f;
                bubbleMedium.responseFieldFalloff=.58f;
                bubbleMedium.apertureShape=0;
                bubbleMedium.apertureSoftness=.08f;
                bubbleMedium.fieldCurvature=.78f;
                bubbleMedium.cornerSharpnessLoss=.58f;
                bubbleMedium.astigmatism=.16f;
                bubbleMedium.radialSmear=.12f;
                bubbleMedium.apertureResponse=.50f;
                bubbleMedium.apertureRadius=11.0f;
                bubbleMedium.apertureCatEye=.18f;
                bubbleMedium.apertureRimWeight=.30f;
                bubbleMedium.sphericalHalo=.55f;
                bubbleMedium.microContrast=-.16f;
                bubbleMedium.longitudinalCA=.24f;
                save("377-bubble-bokeh-triplet-medium.tiff",displayPreview(render(
                    engine,device,queue,bubblePoints,width,height,bubbleMedium)));
                auto bubbleCaricature=LDBNeutralOpticsParameters(width,height);
                bubbleCaricature.responseFieldOnset=.24f;
                bubbleCaricature.responseFieldFalloff=.58f;
                bubbleCaricature.apertureShape=0;
                bubbleCaricature.apertureSoftness=.08f;
                bubbleCaricature.fieldCurvature=1.35f;
                bubbleCaricature.cornerSharpnessLoss=.94f;
                bubbleCaricature.astigmatism=.34f;
                bubbleCaricature.radialSmear=.28f;
                bubbleCaricature.tangentialSmear=.22f;
                bubbleCaricature.apertureResponse=.75f;
                bubbleCaricature.apertureRadius=15.0f;
                bubbleCaricature.apertureCatEye=.30f;
                bubbleCaricature.apertureRimWeight=.55f;
                bubbleCaricature.sphericalHalo=1.2f;
                bubbleCaricature.microContrast=-.30f;
                bubbleCaricature.longitudinalCA=.75f;
                save("378-bubble-bokeh-triplet-caricature.tiff",displayPreview(render(
                    engine,device,queue,bubblePoints,width,height,bubbleCaricature)));
            }

            if(passNumber==82) {
                save("368-integrated-night-scope-source.tiff",displayPreview(cookeDarkSource));
                std::vector<simd_float4> correctedPupilPoints(size_t(width)*height,
                                                               simd_float4{0,0,0,1});
                for(int row=0;row<5;++row) for(int column=0;column<7;++column) {
                    int x=int((column+.5f)*float(width)/7.0f);
                    int y=int((row+.5f)*float(height)/5.0f);
                    correctedPupilPoints[size_t(y)*width+size_t(x)]={8,8,8,1};
                }
                save("369-corrected-pupil-source.tiff",displayPreview(correctedPupilPoints));
                auto correctedClip=LDBNeutralOpticsParameters(width,height);
                correctedClip.responseFieldOnset=0.0f;
                correctedClip.responseFieldFalloff=.36f;
                correctedClip.apertureResponse=1.0f;
                correctedClip.apertureRadius=25.0f;
                correctedClip.apertureShape=0;
                correctedClip.apertureSoftness=.16f;
                correctedClip.aperturePupilShift=.78f;
                correctedClip.aperturePupilClip=.72f;
                save("370-demo-pupil-decenter-clipping-corrected.tiff",displayPreview(render(
                    engine,device,queue,correctedPupilPoints,width,height,correctedClip)));
                auto correctedRim=LDBNeutralOpticsParameters(width,height);
                correctedRim.responseFieldOnset=.08f;
                correctedRim.responseFieldFalloff=.72f;
                correctedRim.apertureResponse=1.0f;
                correctedRim.apertureRadius=20.0f;
                correctedRim.apertureShape=0;
                correctedRim.apertureSoftness=.12f;
                correctedRim.apertureCatEye=.24f;
                correctedRim.apertureBokehSwirl=1.2f;
                correctedRim.apertureRimWeight=.55f;
                save("371-demo-bubble-rim-filled-corrected.tiff",displayPreview(render(
                    engine,device,queue,correctedPupilPoints,width,height,correctedRim)));

                auto integratedScope=LDBNeutralOpticsParameters(width,height);
                integratedScope.anamorphicSqueeze=1.8f;
                integratedScope.fieldAspect=1.48f;
                integratedScope.responseFieldOnset=.18f;
                integratedScope.responseFieldFalloff=1.22f;
                integratedScope.apertureShape=2;
                integratedScope.apertureAspect=1.8f;
                integratedScope.apertureSoftness=.18f;
                integratedScope.anamorphicFlareColor={.22f,.48f,1.0f};
                integratedScope.anamorphicFlareGhostColor={.22f,.46f,.82f};
                integratedScope.glareColor={.24f,.46f,1.0f};
                integratedScope.anamorphicDistortion=.016f;
                integratedScope.anamorphicAberration=.68f;
                integratedScope.anamorphicFlareAmount=1.05f;
                integratedScope.anamorphicFlareRadius=1850.0f;
                integratedScope.anamorphicFlareThreshold=.36f;
                integratedScope.anamorphicFlareThickness=.13f;
                integratedScope.anamorphicFlareCoreAmount=.28f;
                integratedScope.anamorphicFlareAsymmetry=.10f;
                integratedScope.anamorphicFlareGhostAmount=.018f;
                integratedScope.anamorphicFlareGhostPosition=-.46f;
                integratedScope.anamorphicFlareGhostScale=1.25f;
                integratedScope.anamorphicFlareGhostCount=3.0f;
                integratedScope.anamorphicFlareGhostSpacing=150.0f;
                integratedScope.anamorphicFlareGhostScaleDecay=.78f;
                integratedScope.anamorphicFlareGhostEnergyDecay=.56f;
                integratedScope.anamorphicFlareBandAmount=.28f;
                integratedScope.anamorphicFlareBandSeparation=26.0f;
                integratedScope.anamorphicFlareSecondaryAmount=.08f;
                integratedScope.anamorphicFlareSecondaryOffset=205.0f;
                integratedScope.diffractionRayAmount=.08f;
                integratedScope.diffractionRayLength=170.0f;
                integratedScope.glareEnergy=.72f;
                integratedScope.glareRadius=650.0f;
                integratedScope.glareColorAmount=.55f;
                integratedScope.bloomEnergy=.18f;
                integratedScope.bloomThreshold=.38f;
                integratedScope.bloomRadius=65.0f;
                integratedScope.bloomHorizontalStretch=2.8f;
                integratedScope.apertureResponse=.32f;
                integratedScope.apertureRadius=10.0f;
                integratedScope.apertureCatEye=.38f;
                integratedScope.apertureBokehSwirl=1.4f;
                integratedScope.lateralCARed=.48f;
                integratedScope.lateralCABlue=-.68f;
                save("372-prismatic-night-scope-medium-integrated.tiff",displayPreview(render(
                    engine,device,queue,cookeDarkSource,width,height,integratedScope)));
                auto integratedScopeCaricature=integratedScope;
                integratedScopeCaricature.anamorphicDistortion=.028f;
                integratedScopeCaricature.anamorphicAberration=1.22f;
                integratedScopeCaricature.anamorphicFlareAmount=1.65f;
                integratedScopeCaricature.anamorphicFlareRadius=2000.0f;
                integratedScopeCaricature.anamorphicFlareThreshold=.22f;
                integratedScopeCaricature.anamorphicFlareThickness=.15f;
                integratedScopeCaricature.anamorphicFlareCoreAmount=.46f;
                integratedScopeCaricature.anamorphicFlareAsymmetry=.16f;
                integratedScopeCaricature.anamorphicFlareGhostAmount=.035f;
                integratedScopeCaricature.anamorphicFlareGhostPosition=-.54f;
                integratedScopeCaricature.anamorphicFlareGhostScale=1.4f;
                integratedScopeCaricature.anamorphicFlareGhostCount=4.0f;
                integratedScopeCaricature.anamorphicFlareGhostSpacing=175.0f;
                integratedScopeCaricature.anamorphicFlareGhostScaleDecay=.76f;
                integratedScopeCaricature.anamorphicFlareGhostEnergyDecay=.54f;
                integratedScopeCaricature.anamorphicFlareBandAmount=.55f;
                integratedScopeCaricature.anamorphicFlareBandSeparation=34.0f;
                integratedScopeCaricature.anamorphicFlareSecondaryAmount=.18f;
                integratedScopeCaricature.anamorphicFlareSecondaryOffset=235.0f;
                integratedScopeCaricature.diffractionRayAmount=.16f;
                integratedScopeCaricature.diffractionRayLength=230.0f;
                integratedScopeCaricature.glareEnergy=1.05f;
                integratedScopeCaricature.glareRadius=850.0f;
                integratedScopeCaricature.glareColorAmount=.72f;
                integratedScopeCaricature.bloomEnergy=.32f;
                integratedScopeCaricature.bloomThreshold=.24f;
                integratedScopeCaricature.bloomRadius=85.0f;
                integratedScopeCaricature.bloomHorizontalStretch=4.0f;
                integratedScopeCaricature.apertureResponse=.55f;
                integratedScopeCaricature.apertureRadius=14.0f;
                integratedScopeCaricature.apertureCatEye=.62f;
                integratedScopeCaricature.apertureBokehSwirl=2.8f;
                integratedScopeCaricature.lateralCARed=1.0f;
                integratedScopeCaricature.lateralCABlue=-1.35f;
                integratedScopeCaricature.longitudinalCA=.38f;
                integratedScopeCaricature.transmissionHighlightSoftness=.42f;
                save("373-prismatic-night-scope-caricature-integrated.tiff",displayPreview(render(
                    engine,device,queue,cookeDarkSource,width,height,integratedScopeCaricature)));
            }

            if(passNumber==81) {
                // Pass 81 is a preset-library capability audit. Each effect is
                // paired with a source that can actually expose it: compact
                // light for flare/diffraction, isolated points for pupil shape,
                // and photographed texture for compound lens character.
                save("357-compact-flare-source.tiff",displayPreview(cookeDarkSource));

                auto structuredFlare=LDBNeutralOpticsParameters(width,height);
                structuredFlare.anamorphicSqueeze=2.0f;
                structuredFlare.anamorphicFlareAmount=1.55f;
                structuredFlare.anamorphicFlareRadius=1900.0f;
                structuredFlare.anamorphicFlareThreshold=.36f;
                structuredFlare.anamorphicFlareThickness=.10f;
                structuredFlare.anamorphicFlareCoreAmount=.42f;
                structuredFlare.anamorphicFlareAsymmetry=.10f;
                structuredFlare.anamorphicFlareGhostAmount=.08f;
                structuredFlare.anamorphicFlareGhostPosition=-.55f;
                structuredFlare.anamorphicFlareGhostScale=.92f;
                structuredFlare.anamorphicFlareGhostCount=5.0f;
                structuredFlare.anamorphicFlareGhostSpacing=115.0f;
                structuredFlare.anamorphicFlareGhostScaleDecay=.80f;
                structuredFlare.anamorphicFlareGhostEnergyDecay=.62f;
                structuredFlare.anamorphicFlareBandAmount=.85f;
                structuredFlare.anamorphicFlareBandSeparation=30.0f;
                structuredFlare.anamorphicFlareSecondaryAmount=.34f;
                structuredFlare.anamorphicFlareSecondaryOffset=220.0f;
                structuredFlare.anamorphicFlareColor={.12f,.42f,1.0f};
                structuredFlare.anamorphicFlareGhostColor={.48f,.22f,1.0f};
                save("358-demo-structured-anamorphic-flare.tiff",displayPreview(render(
                    engine,device,queue,cookeDarkSource,width,height,structuredFlare)));

                auto diffraction=LDBNeutralOpticsParameters(width,height);
                diffraction.anamorphicFlareAmount=.28f;
                diffraction.anamorphicFlareThreshold=.42f;
                diffraction.anamorphicFlareCoreAmount=.52f;
                diffraction.diffractionRayAmount=.85f;
                diffraction.diffractionRayLength=340.0f;
                diffraction.glareEnergy=.16f;
                diffraction.glareRadius=95.0f;
                save("359-demo-diffraction-rays.tiff",displayPreview(render(
                    engine,device,queue,cookeDarkSource,width,height,diffraction)));

                std::vector<simd_float4> presetPupilPoints(size_t(width)*height,
                                                           simd_float4{0,0,0,1});
                for(int row=0;row<5;++row) for(int column=0;column<7;++column) {
                    int x=int((column+.5f)*float(width)/7.0f);
                    int y=int((row+.5f)*float(height)/5.0f);
                    presetPupilPoints[size_t(y)*width+size_t(x)]={8,8,8,1};
                }
                save("360-isolated-pupil-source.tiff",displayPreview(presetPupilPoints));
                auto decenteredPupil=LDBNeutralOpticsParameters(width,height);
                decenteredPupil.responseFieldOnset=0.0f;
                decenteredPupil.responseFieldFalloff=.36f;
                decenteredPupil.apertureResponse=1.0f;
                decenteredPupil.apertureRadius=21.0f;
                decenteredPupil.apertureShape=0;
                decenteredPupil.apertureSoftness=.16f;
                decenteredPupil.aperturePupilShift=.62f;
                decenteredPupil.aperturePupilClip=.50f;
                save("361-demo-pupil-decenter-clipping.tiff",displayPreview(render(
                    engine,device,queue,presetPupilPoints,width,height,decenteredPupil)));
                auto bubbleRim=LDBNeutralOpticsParameters(width,height);
                bubbleRim.responseFieldOnset=.08f;
                bubbleRim.responseFieldFalloff=.72f;
                bubbleRim.apertureResponse=1.0f;
                bubbleRim.apertureRadius=20.0f;
                bubbleRim.apertureShape=0;
                bubbleRim.apertureSoftness=.08f;
                bubbleRim.apertureCatEye=.24f;
                bubbleRim.apertureBokehSwirl=1.2f;
                bubbleRim.apertureRimWeight=.90f;
                save("362-demo-bubble-rim-bokeh.tiff",displayPreview(render(
                    engine,device,queue,presetPupilPoints,width,height,bubbleRim)));

                save("363-real-footage-source.tiff",displayPreview(cookeReference));
                auto dream=LDBNeutralOpticsParameters(width,height);
                dream.fieldCenter={.43f,.56f};
                dream.responseFieldOnset=.14f; dream.responseFieldFalloff=1.14f;
                dream.apertureShape=1; dream.apertureBladeCount=7;
                dream.apertureBladeCurvature=.48f; dream.apertureSoftness=.16f;
                dream.transmissionColor={1.0f,.88f,.76f}; dream.variationSeed=24571;
                dream.cornerSharpnessLoss=.72f; dream.fieldCurvature=.68f;
                dream.astigmatism=.34f; dream.tangentialSmear=.24f;
                dream.apertureResponse=.52f; dream.apertureRadius=12.0f;
                dream.apertureAspect=1.16f; dream.apertureCatEye=.46f;
                dream.apertureBokehSwirl=2.8f; dream.aperturePupilShift=.13f;
                dream.aperturePupilClip=.12f; dream.apertureRimWeight=.24f;
                dream.longitudinalCA=.34f; dream.lateralCARed=.38f;
                dream.lateralCABlue=-.52f; dream.sphericalHalo=.22f;
                dream.transmissionColorAmount=.22f; dream.variationAmount=.34f;
                dream.variationFieldAsymmetry=.42f; dream.variationPupilIrregularity=.42f;
                save("364-decentered-dream-glass-medium.tiff",displayPreview(render(
                    engine,device,queue,cookeReference,width,height,dream)));
                auto dreamCaricature=dream;
                dreamCaricature.cornerSharpnessLoss=1.25f; dreamCaricature.fieldCurvature=1.22f;
                dreamCaricature.astigmatism=.72f; dreamCaricature.radialSmear=.28f;
                dreamCaricature.tangentialSmear=.62f; dreamCaricature.apertureResponse=.78f;
                dreamCaricature.apertureRadius=16.0f; dreamCaricature.apertureAspect=1.28f;
                dreamCaricature.apertureCatEye=.78f; dreamCaricature.apertureBokehSwirl=4.8f;
                dreamCaricature.aperturePupilShift=.24f; dreamCaricature.aperturePupilClip=.26f;
                dreamCaricature.apertureRimWeight=.48f; dreamCaricature.longitudinalCA=.72f;
                dreamCaricature.lateralCARed=.88f; dreamCaricature.lateralCABlue=-1.16f;
                dreamCaricature.sphericalHalo=.62f; dreamCaricature.glareEnergy=.28f;
                dreamCaricature.transmissionColorAmount=.38f; dreamCaricature.variationAmount=.72f;
                dreamCaricature.variationFieldAsymmetry=.82f;
                dreamCaricature.variationPupilIrregularity=.78f;
                dreamCaricature.variationChromaticAsymmetry=.54f;
                save("365-decentered-dream-glass-caricature.tiff",displayPreview(render(
                    engine,device,queue,cookeReference,width,height,dreamCaricature)));

                auto scope=LDBNeutralOpticsParameters(width,height);
                scope.anamorphicSqueeze=1.8f; scope.fieldAspect=1.48f;
                scope.responseFieldOnset=.18f; scope.responseFieldFalloff=1.22f;
                scope.apertureShape=2; scope.apertureAspect=1.8f; scope.apertureSoftness=.18f;
                scope.anamorphicFlareColor={.28f,.52f,1.0f};
                scope.anamorphicFlareGhostColor={.72f,.24f,1.0f};
                scope.glareColor={.24f,.46f,1.0f};
                scope.anamorphicDistortion=.016f; scope.anamorphicAberration=.68f;
                scope.anamorphicFlareAmount=1.18f; scope.anamorphicFlareRadius=1750.0f;
                scope.anamorphicFlareThreshold=.38f; scope.anamorphicFlareThickness=.10f;
                scope.anamorphicFlareCoreAmount=.34f; scope.anamorphicFlareAsymmetry=.08f;
                scope.anamorphicFlareGhostAmount=.06f; scope.anamorphicFlareGhostPosition=-.52f;
                scope.anamorphicFlareGhostScale=.88f; scope.anamorphicFlareGhostCount=4.0f;
                scope.anamorphicFlareGhostSpacing=120.0f; scope.anamorphicFlareGhostScaleDecay=.78f;
                scope.anamorphicFlareGhostEnergyDecay=.60f; scope.anamorphicFlareBandAmount=.62f;
                scope.anamorphicFlareBandSeparation=32.0f; scope.anamorphicFlareSecondaryAmount=.20f;
                scope.anamorphicFlareSecondaryOffset=205.0f; scope.diffractionRayAmount=.16f;
                scope.diffractionRayLength=190.0f; scope.glareEnergy=.42f; scope.glareRadius=420.0f;
                scope.glareColorAmount=.68f; scope.bloomEnergy=.10f; scope.bloomThreshold=.48f;
                scope.apertureResponse=.32f; scope.apertureRadius=10.0f; scope.apertureCatEye=.38f;
                scope.apertureBokehSwirl=1.4f; scope.lateralCARed=.48f; scope.lateralCABlue=-.68f;
                save("366-prismatic-night-scope-medium.tiff",displayPreview(render(
                    engine,device,queue,cookeDarkSource,width,height,scope)));
                auto scopeCaricature=scope;
                scopeCaricature.anamorphicDistortion=.028f; scopeCaricature.anamorphicAberration=1.22f;
                scopeCaricature.anamorphicFlareAmount=1.85f; scopeCaricature.anamorphicFlareRadius=2300.0f;
                scopeCaricature.anamorphicFlareThreshold=.20f; scopeCaricature.anamorphicFlareThickness=.075f;
                scopeCaricature.anamorphicFlareCoreAmount=.58f; scopeCaricature.anamorphicFlareAsymmetry=.16f;
                scopeCaricature.anamorphicFlareGhostAmount=.14f; scopeCaricature.anamorphicFlareGhostPosition=-.68f;
                scopeCaricature.anamorphicFlareGhostScale=.78f; scopeCaricature.anamorphicFlareGhostCount=6.0f;
                scopeCaricature.anamorphicFlareGhostSpacing=145.0f;
                scopeCaricature.anamorphicFlareGhostScaleDecay=.74f;
                scopeCaricature.anamorphicFlareGhostEnergyDecay=.64f;
                scopeCaricature.anamorphicFlareBandAmount=1.25f;
                scopeCaricature.anamorphicFlareBandSeparation=42.0f;
                scopeCaricature.anamorphicFlareSecondaryAmount=.48f;
                scopeCaricature.anamorphicFlareSecondaryOffset=245.0f;
                scopeCaricature.diffractionRayAmount=.34f; scopeCaricature.diffractionRayLength=270.0f;
                scopeCaricature.glareEnergy=.82f; scopeCaricature.glareRadius=680.0f;
                scopeCaricature.glareColorAmount=.92f; scopeCaricature.bloomEnergy=.24f;
                scopeCaricature.bloomThreshold=.30f; scopeCaricature.apertureResponse=.55f;
                scopeCaricature.apertureRadius=14.0f; scopeCaricature.apertureCatEye=.62f;
                scopeCaricature.apertureBokehSwirl=2.8f; scopeCaricature.lateralCARed=1.0f;
                scopeCaricature.lateralCABlue=-1.35f; scopeCaricature.longitudinalCA=.38f;
                scopeCaricature.transmissionHighlightSoftness=.42f;
                save("367-prismatic-night-scope-caricature.tiff",displayPreview(render(
                    engine,device,queue,cookeDarkSource,width,height,scopeCaricature)));
            }
            save("252-analytic-flare-source.tiff",displayPreview(cookeDarkSource));
            auto cooke58Primary=LDBNeutralOpticsParameters(width,height);
            cooke58Primary.anamorphicFlareAmount=1.50f;
            cooke58Primary.anamorphicFlareRadius=2100.0f;
            cooke58Primary.anamorphicFlareThreshold=.42f;
            cooke58Primary.anamorphicFlareColor={.07f,.34f,1.0f};
            cooke58Primary.anamorphicFlareCoreAmount=.30f;
            cooke58Primary.anamorphicFlareThickness=.075f;
            cooke58Primary.anamorphicFlareBandAmount=.38f;
            cooke58Primary.anamorphicFlareBandSeparation=18.0f;
            cooke58Primary.diffractionRayAmount=.40f;
            cooke58Primary.diffractionRayLength=245.0f;
            save("253-analytic-broad-streak.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDarkSource,width,height,cooke58Primary))));
            auto cooke58Medium=cooke58Primary;
            cooke58Medium.anamorphicFlareGhostAmount=.035f;
            cooke58Medium.anamorphicFlareGhostPosition=.30f;
            cooke58Medium.anamorphicFlareGhostScale=1.48f;
            cooke58Medium.anamorphicFlareGhostColor={.12f,.52f,1.0f};
            cooke58Medium.anamorphicFlareSecondaryAmount=.08f;
            cooke58Medium.anamorphicFlareSecondaryOffset=165.0f;
            cooke58Medium.glareEnergy=.62f;
            cooke58Medium.glareRadius=760.0f;
            cooke58Medium.glareColorAmount=.78f;
            cooke58Medium.glareColor={.08f,.34f,.78f};
            cooke58Medium.bloomEnergy=.075f;
            cooke58Medium.bloomThreshold=.48f;
            cooke58Medium.bloomRadius=54.0f;
            save("254-cooke-analytic-medium.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDarkSource,width,height,cooke58Medium))));
            auto cooke58GhostAudit=cooke58Medium;
            cooke58GhostAudit.anamorphicFlareGhostAmount=.16f;
            save("255-analytic-ghost-primitive.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,cookeDarkSource,width,height,cooke58GhostAudit))));
            auto complexPracticals=cookeDarkSource;
            for(int row=-2;row<=2;++row) for(int column=-2;column<=2;++column) {
                float lightX=float(width)*.52f+float(column)*28.0f;
                float lightY=float(height)*.52f+float(row)*34.0f;
                for(uint32_t y=0;y<height;++y) for(uint32_t x=0;x<width;++x) {
                    float dx=float(x)-lightX,dy=float(y)-lightY;
                    float practical=2.4f*std::exp(-(dx*dx+dy*dy)/(2.0f*5.0f*5.0f));
                    auto& px=complexPracticals[size_t(y)*width+x];
                    px.x+=practical*.45f;px.y+=practical*.82f;px.z+=practical;
                }
            }
            save("256-complex-practicals-source-rejection.tiff",
                 displayPreview(protectCookeBars(render(engine,device,queue,complexPracticals,width,height,cooke58Medium))));
            save("257-cooke-close-focus-bokeh.tiff",
                 displayPreview(render(engine,device,queue,apertureChart,width,height,cookeCloseFocusBokeh)));

            if(passNumber>=64) {
                save("273-pupil-model-source.tiff",displayPreview(apertureChart));
                auto pupilSymmetric=LDBNeutralOpticsParameters(width,height);
                pupilSymmetric.apertureResponse=1.0f;
                pupilSymmetric.apertureRadius=22.0f;
                pupilSymmetric.apertureShape=2;
                pupilSymmetric.apertureAspect=1.7f;
                pupilSymmetric.apertureCatEye=.65f;
                pupilSymmetric.responseFieldOnset=.08f;
                pupilSymmetric.responseFieldFalloff=.72f;
                save("274-pupil-model-symmetric.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,pupilSymmetric)));
                auto pupilClipped=pupilSymmetric;
                pupilClipped.aperturePupilShift=.62f;
                pupilClipped.aperturePupilClip=.58f;
                save("275-pupil-model-shift-clip.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,pupilClipped)));
                auto pupilRim=pupilClipped;
                pupilRim.apertureRimWeight=.72f;
                save("276-pupil-model-rim-energy.tiff",displayPreview(render(
                    engine,device,queue,apertureChart,width,height,pupilRim)));

                save("277-cloud-model-source.tiff",displayPreview(input));
                auto cloudBase=LDBNeutralOpticsParameters(width,height);
                cloudBase.internalDirtAmount=1.25f;
                cloudBase.internalDirtScale=1.1f;
                cloudBase.internalDirtScatter=.85f;
                cloudBase.internalDirtSoftness=.15f;
                cloudBase.internalDirtComplexity=0.0f;
                cloudBase.internalDirtSeed=16180;
                save("278-cloud-model-base.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,cloudBase)));
                auto cloudSoft=cloudBase;
                cloudSoft.internalDirtSoftness=.88f;
                save("279-cloud-model-soft.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,cloudSoft)));
                auto cloudMultiscale=cloudSoft;
                cloudMultiscale.internalDirtComplexity=1.0f;
                cloudMultiscale.internalDirtSmear=.45f;
                save("280-cloud-model-multiscale.tiff",displayPreview(render(
                    engine,device,queue,input,width,height,cloudMultiscale)));
            }

            if(passNumber>=65) {
                auto cloudUniform=makeUniformField(width,height);
                for(auto& pixel:cloudUniform) pixel={.18f,.18f,.18f,1.0f};
                save("281-cloud-uniform-source.tiff",displayPreview(cloudUniform));
                auto cloudTransmission=LDBNeutralOpticsParameters(width,height);
                cloudTransmission.internalDirtAmount=1.7f;
                cloudTransmission.internalDirtScale=1.0f;
                cloudTransmission.internalDirtSmear=.25f;
                cloudTransmission.internalDirtScatter=0.0f;
                cloudTransmission.internalDirtSoftness=.72f;
                cloudTransmission.internalDirtComplexity=.82f;
                cloudTransmission.internalDirtSeed=16180;
                auto cloudUniformResult=render(engine,device,queue,cloudUniform,width,height,
                                               cloudTransmission);
                save("282-cloud-uniform-transmission.tiff",displayPreview(cloudUniformResult));
                auto cloudDiagnostic=cloudUniform;
                for(size_t i=0;i<cloudDiagnostic.size();++i) {
                    float density=std::clamp(
                        (cloudUniform[i].x-cloudUniformResult[i].x)*28.0f,
                        0.0f,1.0f);
                    cloudDiagnostic[i]={density,density,density,1.0f};
                }
                save("283-cloud-density-amplified-diagnostic.tiff",
                     displayPreview(cloudDiagnostic));
                save("284-cloud-hdr-source.tiff",displayPreview(hdr));
                auto cloudHDRBase=cloudTransmission;
                cloudHDRBase.internalDirtScatter=.75f;
                cloudHDRBase.internalDirtSoftness=.22f;
                cloudHDRBase.internalDirtComplexity=0.0f;
                save("285-cloud-hdr-base-veil.tiff",displayPreview(render(
                    engine,device,queue,hdr,width,height,cloudHDRBase)));
                auto cloudHDRComplex=cloudHDRBase;
                cloudHDRComplex.internalDirtSoftness=.82f;
                cloudHDRComplex.internalDirtComplexity=1.0f;
                cloudHDRComplex.internalDirtSmear=.48f;
                save("286-cloud-hdr-soft-multiscale-veil.tiff",displayPreview(render(
                    engine,device,queue,hdr,width,height,cloudHDRComplex)));

                std::vector<simd_float4> pupilPoints(size_t(width)*height,
                                                     simd_float4{0,0,0,1});
                for(int row=0;row<5;++row) for(int column=0;column<7;++column) {
                    int x=int((column+.5f)*float(width)/7.0f);
                    int y=int((row+.5f)*float(height)/5.0f);
                    pupilPoints[size_t(y)*width+size_t(x)]={8,8,8,1};
                }
                save("287-pupil-isolated-points-source.tiff",displayPreview(pupilPoints));
                auto pupilIsolated=LDBNeutralOpticsParameters(width,height);
                pupilIsolated.apertureResponse=1.0f;
                pupilIsolated.apertureRadius=24.0f;
                pupilIsolated.apertureShape=2;
                pupilIsolated.apertureAspect=1.7f;
                pupilIsolated.apertureCatEye=.62f;
                pupilIsolated.responseFieldOnset=0.0f;
                pupilIsolated.responseFieldFalloff=.72f;
                save("288-pupil-isolated-symmetric.tiff",displayPreview(render(
                    engine,device,queue,pupilPoints,width,height,pupilIsolated)));
                auto pupilIsolatedClip=pupilIsolated;
                pupilIsolatedClip.aperturePupilShift=.58f;
                pupilIsolatedClip.aperturePupilClip=.52f;
                save("289-pupil-isolated-shift-clip.tiff",displayPreview(render(
                    engine,device,queue,pupilPoints,width,height,pupilIsolatedClip)));
                auto pupilIsolatedRim=pupilIsolatedClip;
                pupilIsolatedRim.apertureRimWeight=.52f;
                save("290-pupil-isolated-rim-energy.tiff",displayPreview(render(
                    engine,device,queue,pupilPoints,width,height,pupilIsolatedRim)));
            }

            if(passNumber>=76) {
                auto amountUniform=makeUniformField(width,height);
                for(auto& pixel:amountUniform) pixel={.18f,.18f,.18f,1.0f};
                auto cloudAmount=LDBNeutralOpticsParameters(width,height);
                cloudAmount.internalDirtScale=1.0f;
                cloudAmount.internalDirtSmear=.34f;
                cloudAmount.internalDirtScatter=0.0f;
                cloudAmount.internalDirtSoftness=.72f;
                cloudAmount.internalDirtComplexity=.75f;
                cloudAmount.internalDirtSeed=16180;
                save("317-cloud-amount-uniform-source.tiff",displayPreview(amountUniform));
                cloudAmount.internalDirtAmount=1.0f;
                save("318-cloud-amount-conservative.tiff",displayPreview(render(
                    engine,device,queue,amountUniform,width,height,cloudAmount)));
                cloudAmount.internalDirtAmount=5.0f;
                save("319-cloud-amount-medium.tiff",displayPreview(render(
                    engine,device,queue,amountUniform,width,height,cloudAmount)));
                cloudAmount.internalDirtAmount=10.0f;
                save("320-cloud-amount-extreme.tiff",displayPreview(render(
                    engine,device,queue,amountUniform,width,height,cloudAmount)));
            }

            if(passNumber>=68) {
                auto cloudUniform=makeUniformField(width,height);
                for(auto& pixel:cloudUniform) pixel={.18f,.18f,.18f,1.0f};
                auto cloudSmooth=LDBNeutralOpticsParameters(width,height);
                cloudSmooth.internalDirtAmount=1.55f;
                cloudSmooth.internalDirtScale=1.0f;
                cloudSmooth.internalDirtSmear=.34f;
                cloudSmooth.internalDirtScatter=0.0f;
                cloudSmooth.internalDirtSoftness=.74f;
                cloudSmooth.internalDirtComplexity=0.0f;
                cloudSmooth.internalDirtSeed=16180;
                auto broadDensity=render(engine,device,queue,cloudUniform,width,height,cloudSmooth);
                save("310-cloud-density-source.tiff",displayPreview(cloudUniform));
                save("311-cloud-density-broad.tiff",displayPreview(broadDensity));
                auto cloudComplex=cloudSmooth;
                cloudComplex.internalDirtComplexity=1.0f;
                auto complexDensity=render(engine,device,queue,cloudUniform,width,height,cloudComplex);
                save("312-cloud-density-complex.tiff",displayPreview(complexDensity));
                auto densityDiagnostic=cloudUniform;
                for(size_t i=0;i<densityDiagnostic.size();++i) {
                    float broadLoss=std::max(cloudUniform[i].x-broadDensity[i].x,0.0f);
                    float complexLoss=std::max(cloudUniform[i].x-complexDensity[i].x,0.0f);
                    densityDiagnostic[i]={std::clamp(broadLoss*24.0f,0.0f,1.0f),
                                          std::clamp(complexLoss*24.0f,0.0f,1.0f),
                                          std::clamp(std::abs(complexLoss-broadLoss)*48.0f,0.0f,1.0f),
                                          1.0f};
                }
                save("313-cloud-density-diagnostic.tiff",displayPreview(densityDiagnostic));
            }

            if(passNumber>=67) {
                auto cloudUniform=makeUniformField(width,height);
                for(auto& pixel:cloudUniform) pixel={.18f,.18f,.18f,1.0f};
                auto cloudBroad=LDBNeutralOpticsParameters(width,height);
                cloudBroad.internalDirtAmount=1.55f;
                cloudBroad.internalDirtScale=1.0f;
                cloudBroad.internalDirtSmear=.34f;
                cloudBroad.internalDirtScatter=1.15f;
                cloudBroad.internalDirtSoftness=.74f;
                cloudBroad.internalDirtComplexity=0.0f;
                cloudBroad.internalDirtSeed=16180;
                auto broadUniform=render(engine,device,queue,cloudUniform,width,height,cloudBroad);
                auto broadDiagnostic=cloudUniform;
                for(size_t i=0;i<broadDiagnostic.size();++i) {
                    float density=std::clamp(
                        (cloudUniform[i].x-broadUniform[i].x)*32.0f,0.0f,1.0f);
                    broadDiagnostic[i]={density,density,density,1.0f};
                }
                save("302-cloud-density-broad-continuous.tiff",displayPreview(broadDiagnostic));
                auto cloudComplex=cloudBroad;
                cloudComplex.internalDirtComplexity=1.0f;
                auto complexUniform=render(engine,device,queue,cloudUniform,width,height,cloudComplex);
                auto complexDiagnostic=cloudUniform;
                for(size_t i=0;i<complexDiagnostic.size();++i) {
                    float density=std::clamp(
                        (cloudUniform[i].x-complexUniform[i].x)*32.0f,0.0f,1.0f);
                    complexDiagnostic[i]={density,density,density,1.0f};
                }
                save("303-cloud-density-complex-continuous.tiff",
                     displayPreview(complexDiagnostic));
                save("304-cloud-hdr-source.tiff",displayPreview(hdr));
                save("305-cloud-hdr-broad-veil.tiff",displayPreview(render(
                    engine,device,queue,hdr,width,height,cloudBroad)));
                save("306-cloud-hdr-complex-veil.tiff",displayPreview(render(
                    engine,device,queue,hdr,width,height,cloudComplex)));
            }

            if(passNumber>=66) {
                auto cloudUniform=makeUniformField(width,height);
                for(auto& pixel:cloudUniform) pixel={.18f,.18f,.18f,1.0f};
                auto cloudBroad=LDBNeutralOpticsParameters(width,height);
                cloudBroad.internalDirtAmount=1.7f;
                cloudBroad.internalDirtScale=1.0f;
                cloudBroad.internalDirtSmear=.32f;
                cloudBroad.internalDirtScatter=.95f;
                cloudBroad.internalDirtSoftness=.72f;
                cloudBroad.internalDirtComplexity=0.0f;
                cloudBroad.internalDirtSeed=16180;
                auto broadUniform=render(engine,device,queue,cloudUniform,width,height,cloudBroad);
                auto broadDiagnostic=cloudUniform;
                for(size_t i=0;i<broadDiagnostic.size();++i) {
                    float density=std::clamp(
                        (cloudUniform[i].x-broadUniform[i].x)*28.0f,0.0f,1.0f);
                    broadDiagnostic[i]={density,density,density,1.0f};
                }
                save("293-cloud-density-broad-diagnostic.tiff",displayPreview(broadDiagnostic));
                auto cloudComplex=cloudBroad;
                cloudComplex.internalDirtComplexity=1.0f;
                auto complexUniform=render(engine,device,queue,cloudUniform,width,height,cloudComplex);
                auto complexDiagnostic=cloudUniform;
                for(size_t i=0;i<complexDiagnostic.size();++i) {
                    float density=std::clamp(
                        (cloudUniform[i].x-complexUniform[i].x)*28.0f,0.0f,1.0f);
                    complexDiagnostic[i]={density,density,density,1.0f};
                }
                save("294-cloud-density-multiscale-diagnostic.tiff",
                     displayPreview(complexDiagnostic));
                save("295-cloud-hdr-broad-veil.tiff",displayPreview(render(
                    engine,device,queue,hdr,width,height,cloudBroad)));
                save("296-cloud-hdr-multiscale-veil.tiff",displayPreview(render(
                    engine,device,queue,hdr,width,height,cloudComplex)));

                std::vector<simd_float4> pupilPoints(size_t(width)*height,
                                                     simd_float4{0,0,0,1});
                for(int row=0;row<5;++row) for(int column=0;column<7;++column) {
                    int x=int((column+.5f)*float(width)/7.0f);
                    int y=int((row+.5f)*float(height)/5.0f);
                    pupilPoints[size_t(y)*width+size_t(x)]={8,8,8,1};
                }
                save("297-pupil-rim-source.tiff",displayPreview(pupilPoints));
                auto pupilRim=LDBNeutralOpticsParameters(width,height);
                pupilRim.apertureResponse=1.0f;
                pupilRim.apertureRadius=24.0f;
                pupilRim.apertureShape=2;
                pupilRim.apertureAspect=1.7f;
                pupilRim.apertureCatEye=.62f;
                pupilRim.aperturePupilShift=.58f;
                pupilRim.aperturePupilClip=.52f;
                pupilRim.apertureRimWeight=.38f;
                pupilRim.responseFieldOnset=0.0f;
                pupilRim.responseFieldFalloff=.72f;
                save("298-pupil-rim-moderate.tiff",displayPreview(render(
                    engine,device,queue,pupilPoints,width,height,pupilRim)));
                pupilRim.apertureRimWeight=.78f;
                save("299-pupil-rim-strong.tiff",displayPreview(render(
                    engine,device,queue,pupilPoints,width,height,pupilRim)));
            }

            if(passNumber>=61||baselineRebuild) {
                const bool currentProfileReview=passNumber>=63||baselineRebuild;
                const int sourceOutput=currentProfileReview?268:(passNumber>=62?263:258);
                std::string sourceName=std::to_string(sourceOutput)+(currentProfileReview
                    ?"-cooke-path-calibration-source.tiff"
                    :(passNumber>=62?"-cooke-reflection-train-source.tiff"
                    :"-cooke-focal-calibration-source.tiff"));
                save(sourceName,displayPreview(cookeDarkSource));
                const int focals[4]={32,50,75,100};
                const int outputs61[4]={259,260,261,262};
                const int outputs62[4]={264,265,266,267};
                const int outputs63[4]={269,270,271,272};
                for(int index=0;index<4;++index) {
                    std::string preset="presets/archive/v1.41/v1.41-Calibrate-Cooke-Special-Flare-"
                        +std::to_string(focals[index])+"mm.ldbpreset";
                    auto focalProfile=loadCookeFlareCalibration(preset,width,height);
                    int outputNumber=currentProfileReview?outputs63[index]
                        :(passNumber>=62?outputs62[index]:outputs61[index]);
                    std::string output=std::to_string(outputNumber)
                        +(currentProfileReview?"-cooke-path-calibration-"
                          :(passNumber>=62?"-cooke-reflection-train-":"-cooke-profile-"))
                        +std::to_string(focals[index])+"mm.tiff";
                    save(output,displayPreview(protectCookeBars(
                        render(engine,device,queue,cookeDarkSource,width,height,focalProfile))));
                }
            }

        }
        std::printf("Wrote visual validation images to %s\n", directory.c_str());
    }
    return 0;
}
