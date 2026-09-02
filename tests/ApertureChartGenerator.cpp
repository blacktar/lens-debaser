#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <string>
#include <vector>

namespace {
constexpr uint32_t width=3840,height=2160;
using RGB=std::array<float,3>;
std::vector<RGB> image(size_t(width)*height,RGB{.002f,.002f,.002f});

void pixel(int x,int y,RGB c) {
    if(x<0||y<0||x>=int(width)||y>=int(height)) return;
    auto& p=image[size_t(y)*width+x];
    for(int channel=0;channel<3;++channel)p[channel]=std::max(p[channel],c[channel]);
}
void disc(int cx,int cy,int radius,RGB c) {
    for(int y=-radius;y<=radius;++y)for(int x=-radius;x<=radius;++x)
        if(x*x+y*y<=radius*radius)pixel(cx+x,cy+y,c);
}
void line(int x0,int y0,int x1,int y1,RGB c) {
    int dx=std::abs(x1-x0),sx=x0<x1?1:-1,dy=-std::abs(y1-y0),sy=y0<y1?1:-1,error=dx+dy;
    for(;;){pixel(x0,y0,c);if(x0==x1&&y0==y1)break;int twice=2*error;if(twice>=dy){error+=dy;x0+=sx;}if(twice<=dx){error+=dx;y0+=sy;}}
}
void asymmetricMarker(int x,int y) {
    disc(x,y,2,{1,1,1});
    line(x+18,y+11,x+31,y+11,{.12f,.12f,.12f});
    line(x+31,y+11,x+31,y+22,{.12f,.12f,.12f});
}
bool writeTIFF(const std::string& path) {
    std::vector<uint16_t> rgb(size_t(width)*height*3);
    for(size_t i=0;i<image.size();++i)for(int c=0;c<3;++c)
        rgb[i*3+c]=uint16_t(std::lround(std::clamp(image[i][c],0.0f,1.0f)*65535.0f));
    constexpr uint16_t entries=10;constexpr uint32_t ifd=8;
    constexpr uint32_t ifdBytes=2+entries*12+4,bits=ifd+ifdBytes,formats=bits+6,pixels=formats+6;
    const uint32_t pixelBytes=width*height*3*sizeof(uint16_t);
    std::ofstream out(path,std::ios::binary|std::ios::trunc);if(!out)return false;
    auto u16=[&](uint16_t v){out.put(char(v&255));out.put(char(v>>8));};
    auto u32=[&](uint32_t v){u16(uint16_t(v));u16(uint16_t(v>>16));};
    auto entry=[&](uint16_t tag,uint16_t type,uint32_t count,uint32_t value){u16(tag);u16(type);u32(count);u32(value);};
    out.write("II",2);u16(42);u32(ifd);u16(entries);
    entry(256,4,1,width);entry(257,4,1,height);entry(258,3,3,bits);entry(259,3,1,1);entry(262,3,1,2);
    entry(273,4,1,pixels);entry(277,3,1,3);entry(278,4,1,height);entry(279,4,1,pixelBytes);entry(339,3,3,formats);
    u32(0);u16(16);u16(16);u16(16);u16(1);u16(1);u16(1);
    out.write(reinterpret_cast<const char*>(rgb.data()),pixelBytes);return bool(out);
}
}

int main(int argc,char**argv) {
    if(argc!=2)return 2;
    const int cx=int(width/2),cy=int(height/2);
    // Low-level radial/spoke references reveal rotation, smearing and duplicated geometry.
    for(int angle=0;angle<360;angle+=15){float a=float(angle)*3.14159265f/180.0f;line(cx,cy,cx+int(std::cos(a)*720),cy+int(std::sin(a)*720),{.025f,.025f,.025f});}
    for(int radius:{240,480,720})for(int angle=0;angle<360;angle+=30){float a=float(angle)*3.14159265f/180.0f;disc(cx+int(std::cos(a)*radius),cy+int(std::sin(a)*radius),2,{.8f,.8f,.8f});}
    // Paired symmetric field grid. The left member is a 4-pixel-diameter sharp
    // emitter for reading the pupil footprint; the right member is a practical
    // 20-pixel-diameter highlight for judging smoothness on photographed lights.
    // A 100-pixel separation keeps both 24-pixel-radius responses independent.
    const float xs[]={.08f,.25f,.50f,.75f,.92f},ys[]={.10f,.28f,.50f,.72f,.90f};
    for(int yi=0;yi<5;++yi)for(int xi=0;xi<5;++xi){
        int x=int(xs[xi]*width),y=int(ys[yi]*height);
        disc(x-50,y,2,{1,1,1});
        disc(x+50,y,10,{1,1,1});
    }
    // Coloured sources make channel displacement or coloured ghosts obvious.
    disc(int(.16f*width),cy,3,{1,.08f,.08f});disc(int(.84f*width),cy,3,{.08f,.15f,1});
    disc(cx,int(.16f*height),3,{.08f,1,.15f});disc(cx,int(.84f*height),3,{1,.18f,.75f});
    // Unequal doublets and L-marked sources expose extra copies and directional ghosts.
    asymmetricMarker(int(.13f*width),int(.18f*height));asymmetricMarker(int(.87f*width),int(.18f*height));
    asymmetricMarker(int(.13f*width),int(.82f*height));asymmetricMarker(int(.87f*width),int(.82f*height));
    // Exposure ladder uses identical sharp emitters, isolating response energy
    // from source diameter.
    for(int i=0;i<7;++i){int x=int(.35f*width)+i*int(.05f*width);float v=float(i+1)/7.0f;disc(x,int(.96f*height),2,{v,v,v});}
    // Centre orientation key is deliberately asymmetric.
    disc(cx,cy,3,{1,1,1});line(cx+24,cy,cx+74,cy,{.2f,.2f,.2f});line(cx,cy-24,cx,cy-54,{.1f,.1f,.1f});
    return writeTIFF(argv[1])?0:3;
}
