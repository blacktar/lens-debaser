#pragma once

#include <cmath>
#include <simd/simd.h>
#include "LDBOpticsParameters.h"

// Host reference used by tests and preview generation, not by the render path.
namespace LDBColorReference {

struct Matrix3 { float m[3][3]; };

inline simd_float3 apply(const Matrix3& m, simd_float3 v) {
    return {m.m[0][0]*v.x + m.m[0][1]*v.y + m.m[0][2]*v.z,
            m.m[1][0]*v.x + m.m[1][1]*v.y + m.m[1][2]*v.z,
            m.m[2][0]*v.x + m.m[2][1]*v.y + m.m[2][2]*v.z};
}

inline float logEncode(float x, float base, float a, float b, float c, float d, float cut, float e = 0) {
    float atCut = c * std::log(a*cut+b) / std::log(base) + d;
    float slope = e > 0 ? e : c*a / ((a*cut+b)*std::log(base));
    return x > cut ? c*std::log(a*x+b)/std::log(base)+d : atCut+slope*(x-cut);
}

inline float logDecode(float y, float base, float a, float b, float c, float d, float cut, float e = 0) {
    float atCut = c * std::log(a*cut+b) / std::log(base) + d;
    float slope = e > 0 ? e : c*a / ((a*cut+b)*std::log(base));
    return y > atCut ? (std::pow(base,(y-d)/c)-b)/a : cut+(y-atCut)/slope;
}

inline float encodeCurve(float v, uint32_t s) {
    if (s == LDBWorkingColorSpaceACEScct) return v > .0078125f ? (std::log2(v)+9.72f)/17.52f : 10.5402377416545f*v+.0729055341958355f;
    if (s == LDBWorkingColorSpaceDaVinciIntermediate) return logEncode(v,2,1,.0075f,.07329248f,.51304736f,.00262409f,10.44426855f);
    if (s == LDBWorkingColorSpaceARRILogC3EI800) return logEncode(v,10,5.55555555555556f,.0522722750251688f,.247189638318671f,.385536998692443f,.0105909904954696f);
    if (s == LDBWorkingColorSpaceARRILogC4) return logEncode(v,2,2231.82630906769f,64,.0647954196341293f,-.295908392682586f,-.0180569961199113f);
    return v;
}

inline float decodeCurve(float v, uint32_t s) {
    if (s == LDBWorkingColorSpaceACEScct) return v > .155251141552511f ? std::exp2(v*17.52f-9.72f) : (v-.0729055341958355f)/10.5402377416545f;
    if (s == LDBWorkingColorSpaceDaVinciIntermediate) return logDecode(v,2,1,.0075f,.07329248f,.51304736f,.00262409f,10.44426855f);
    if (s == LDBWorkingColorSpaceARRILogC3EI800) return logDecode(v,10,5.55555555555556f,.0522722750251688f,.247189638318671f,.385536998692443f,.0105909904954696f);
    if (s == LDBWorkingColorSpaceARRILogC4) return logDecode(v,2,2231.82630906769f,64,.0647954196341293f,-.295908392682586f,-.0180569961199113f);
    return v;
}

inline Matrix3 fromAP1Matrix(uint32_t s) {
    if (s == LDBWorkingColorSpaceDaVinciIntermediate) return {{{.914854961296f,.00284456545172f,.0823004733441f},{.031184511771f,.783316306969f,.185499181263f},{.0674001840941f,.0855860885789f,.847013727334f}}};
    if (s == LDBWorkingColorSpaceARRILogC3EI800) return {{{1.03896426669f,-.0979906125472f,.0590263459571f},{-.0441881322326f,.858661168238f,.18552696399f},{-.00983215117778f,.0546406347221f,.955191516455f}}};
    if (s == LDBWorkingColorSpaceARRILogC4) return {{{.918387668244f,.0225491821021f,.0590631497457f},{.0436754226211f,.85337876094f,.102945816443f},{-.00502262482106f,.004758976267f,1.00026364855f}}};
    return {{{1,0,0},{0,1,0},{0,0,1}}};
}

inline Matrix3 toAP1Matrix(uint32_t s) {
    if (s == LDBWorkingColorSpaceDaVinciIntermediate) return {{{1.10080813074f,.0078776190186f,-.108685749863f},{-.0236462205769f,1.30775099467f,-.284104774098f},{-.0852062732947f,-.132767913686f,1.21797418698f}}};
    if (s == LDBWorkingColorSpaceARRILogC3EI800) return {{{.966633447224f,.115541618793f,-.0821750661166f},{.0481903521746f,1.18493829339f,-.233128645567f},{.00719325353914f,-.0665937214668f,1.05940046793f}}};
    if (s == LDBWorkingColorSpaceARRILogC4) return {{{1.08988212182f,-.0284558573649f,-.0614262645512f},{-.0564721174125f,1.17395999047f,-.117487873055f},{.00574130477687f,-.00572826058093f,.999986955804f}}};
    return {{{1,0,0},{0,1,0},{0,0,1}}};
}

inline simd_float3 encode(simd_float3 ap1, uint32_t s) {
    simd_float3 v = apply(fromAP1Matrix(s), ap1);
    return {encodeCurve(v.x,s),encodeCurve(v.y,s),encodeCurve(v.z,s)};
}

inline simd_float3 decode(simd_float3 encoded, uint32_t s) {
    simd_float3 v = {decodeCurve(encoded.x,s),decodeCurve(encoded.y,s),decodeCurve(encoded.z,s)};
    return apply(toAP1Matrix(s), v);
}
}
