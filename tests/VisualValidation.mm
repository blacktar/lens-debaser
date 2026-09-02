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
    NSUInteger bytes = input.size() * sizeof(simd_float4);
    id<MTLBuffer> src = [device newBufferWithBytes:input.data() length:bytes options:MTLResourceStorageModeShared];
    id<MTLBuffer> dst = [device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    engine.encode(command, src, dst, width, height, parameters);
    [command commit];
    [command waitUntilCompleted];
    simd_float4* values = static_cast<simd_float4*>(dst.contents);
    return std::vector<simd_float4>(values, values + input.size());
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

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 4 || argc > 7) return 2;
        constexpr uint32_t width = 1920, height = 1080;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return 3;
        if (!rec709NeutralChannelRegression()) {
            std::fprintf(stderr, "FAIL: Rec.709 Gamma 2.4 neutral-channel regression\n");
            return 14;
        }
        LDBOpticsEngine engine(device, [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]);
        if (!engine.valid()) return 4;
        id<MTLCommandQueue> queue = [device newCommandQueue];
        auto input = makeChart(width, height); // scene-linear AP1 reference chart
        std::string directory = argv[2];
        auto save = [&](const std::string& name, const std::vector<simd_float4>& pixels) {
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
        auto comaOnly = LDBNeutralOpticsParameters(width, height);
        comaOnly.coma=.80f;
        save("34-hdr-coma.tiff",displayPreview(render(engine,device,queue,hdr,width,height,comaOnly)));
        auto haloOnly = LDBNeutralOpticsParameters(width, height);
        haloOnly.sphericalHalo=.65f;
        save("35-hdr-spherical-halo.tiff",displayPreview(render(engine,device,queue,hdr,width,height,haloOnly)));
        auto comaHalo=comaOnly; comaHalo.sphericalHalo=.65f;
        save("36-hdr-coma-halo.tiff",displayPreview(render(engine,device,queue,hdr,width,height,comaHalo)));
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
        }

        if (argc >= 6) {
            uint32_t realWidth = 0, realHeight = 0;
            auto real = loadEncodedTIFF(argv[5], realWidth, realHeight);
            if (real.empty()) { std::fprintf(stderr, "FAIL: unable to load real camera TIFF %s\n", argv[5]); return 10; }
            simd_float3 realMean = meanRGB(real);
            std::printf("iPhone encoded RGB means: %.6f %.6f %.6f\n", realMean.x, realMean.y, realMean.z);
            auto saveReal = [&](const std::string& name, const std::vector<simd_float4>& encoded) {
                if (!writeTIFF(directory + "/" + name,
                               rec709Gamma24FromWorkingSpace(encoded, LDBWorkingColorSpaceDaVinciIntermediate),
                               realWidth, realHeight, true)) std::exit(11);
            };
            auto neutralReal = LDBNeutralOpticsParameters(realWidth, realHeight);
            neutralReal.workingColorSpace = LDBWorkingColorSpaceDaVinciIntermediate;
            saveReal("50-iphone-dwg-neutral-rec709-g24.tiff", real);
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
        if (argc == 7) {
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
        }
        std::printf("Wrote visual validation images to %s\n", directory.c_str());
    }
    return 0;
}
