#include <metal_stdlib>
#include "LDBOpticsParameters.h"
using namespace metal;

kernel void ldbPackDepthLuminance(
    device const float4* source [[buffer(0)]],
    device const float4* depthSource [[buffer(1)]],
    device float4* destination [[buffer(2)]],
    constant LDBOpticsParameters& p [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(p.imageSize.x), height = uint(p.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    uint index = gid.y * width + gid.x;
    float4 sample = depthSource[index];
    float depth = dot(sample.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    destination[index] = float4(source[index].rgb, depth);
}

static float logCurveEncode(float x, float base, float linSlope, float linOffset,
                            float logSlope, float logOffset, float linBreak,
                            float explicitLinearSlope) {
    float atBreak = logSlope * log(linSlope * linBreak + linOffset) / log(base) + logOffset;
    float linearSlope = explicitLinearSlope > 0.0f ? explicitLinearSlope
        : logSlope * linSlope / ((linSlope * linBreak + linOffset) * log(base));
    return x > linBreak
        ? logSlope * log(linSlope * x + linOffset) / log(base) + logOffset
        : atBreak + linearSlope * (x - linBreak);
}

static float logCurveDecode(float y, float base, float linSlope, float linOffset,
                            float logSlope, float logOffset, float linBreak,
                            float explicitLinearSlope) {
    float atBreak = logSlope * log(linSlope * linBreak + linOffset) / log(base) + logOffset;
    float linearSlope = explicitLinearSlope > 0.0f ? explicitLinearSlope
        : logSlope * linSlope / ((linSlope * linBreak + linOffset) * log(base));
    return y > atBreak
        ? (pow(base, (y - logOffset) / logSlope) - linOffset) / linSlope
        : linBreak + (y - atBreak) / linearSlope;
}

static float decodeTransfer(float v, uint space) {
    switch (space) {
        case LDBWorkingColorSpaceACEScct:
            return v > 0.155251141552511f ? exp2(v * 17.52f - 9.72f)
                : (v - 0.0729055341958355f) / 10.5402377416545f;
        case LDBWorkingColorSpaceDaVinciIntermediate:
            return logCurveDecode(v, 2.0f, 1.0f, 0.0075f, 0.07329248f,
                                  0.51304736f, 0.00262409f, 10.44426855f);
        case LDBWorkingColorSpaceARRILogC3EI800:
            return logCurveDecode(v, 10.0f, 5.55555555555556f, 0.0522722750251688f,
                                  0.247189638318671f, 0.385536998692443f,
                                  0.0105909904954696f, 0.0f);
        case LDBWorkingColorSpaceARRILogC4:
            return logCurveDecode(v, 2.0f, 2231.82630906769f, 64.0f,
                                  0.0647954196341293f, -0.295908392682586f,
                                  -0.0180569961199113f, 0.0f);
        default: return v;
    }
}

static float encodeTransfer(float v, uint space) {
    switch (space) {
        case LDBWorkingColorSpaceACEScct:
            return v > 0.0078125f ? (log2(v) + 9.72f) / 17.52f
                : 10.5402377416545f * v + 0.0729055341958355f;
        case LDBWorkingColorSpaceDaVinciIntermediate:
            return logCurveEncode(v, 2.0f, 1.0f, 0.0075f, 0.07329248f,
                                  0.51304736f, 0.00262409f, 10.44426855f);
        case LDBWorkingColorSpaceARRILogC3EI800:
            return logCurveEncode(v, 10.0f, 5.55555555555556f, 0.0522722750251688f,
                                  0.247189638318671f, 0.385536998692443f,
                                  0.0105909904954696f, 0.0f);
        case LDBWorkingColorSpaceARRILogC4:
            return logCurveEncode(v, 2.0f, 2231.82630906769f, 64.0f,
                                  0.0647954196341293f, -0.295908392682586f,
                                  -0.0180569961199113f, 0.0f);
        default: return v;
    }
}

static float3 multiplyRows(float3 v, float3 r0, float3 r1, float3 r2) {
    return float3(dot(r0, v), dot(r1, v), dot(r2, v));
}

static float3 toAP1(float3 v, uint space) {
    if (space == LDBWorkingColorSpaceDaVinciIntermediate)
        return multiplyRows(v, {1.10080813074f, .0078776190186f, -.108685749863f},
            {-.0236462205769f, 1.30775099467f, -.284104774098f},
            {-.0852062732947f, -.132767913686f, 1.21797418698f});
    if (space == LDBWorkingColorSpaceARRILogC3EI800)
        return multiplyRows(v, {.966633447224f, .115541618793f, -.0821750661166f},
            {.0481903521746f, 1.18493829339f, -.233128645567f},
            {.00719325353914f, -.0665937214668f, 1.05940046793f});
    if (space == LDBWorkingColorSpaceARRILogC4)
        return multiplyRows(v, {1.08988212182f, -.0284558573649f, -.0614262645512f},
            {-.0564721174125f, 1.17395999047f, -.117487873055f},
            {.00574130477687f, -.00572826058093f, .999986955804f});
    return v;
}

static float3 fromAP1(float3 v, uint space) {
    if (space == LDBWorkingColorSpaceDaVinciIntermediate)
        return multiplyRows(v, {.914854961296f, .00284456545172f, .0823004733441f},
            {.031184511771f, .783316306969f, .185499181263f},
            {.0674001840941f, .0855860885789f, .847013727334f});
    if (space == LDBWorkingColorSpaceARRILogC3EI800)
        return multiplyRows(v, {1.03896426669f, -.0979906125472f, .0590263459571f},
            {-.0441881322326f, .858661168238f, .18552696399f},
            {-.00983215117778f, .0546406347221f, .955191516455f});
    if (space == LDBWorkingColorSpaceARRILogC4)
        return multiplyRows(v, {.918387668244f, .0225491821021f, .0590631497457f},
            {.0436754226211f, .85337876094f, .102945816443f},
            {-.00502262482106f, .004758976267f, 1.00026364855f});
    return v;
}

kernel void ldbDecodeToLinearAP1(device const float4* source [[buffer(0)]],
                                 device float4* destination [[buffer(1)]],
                                 constant LDBOpticsParameters& p [[buffer(2)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(p.imageSize.x), height = uint(p.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    uint index = gid.y * width + gid.x;
    float4 encoded = source[index];
    float3 linear = float3(decodeTransfer(encoded.r, p.workingColorSpace),
                           decodeTransfer(encoded.g, p.workingColorSpace),
                           decodeTransfer(encoded.b, p.workingColorSpace));
    destination[index] = float4(toAP1(linear, p.workingColorSpace), encoded.a);
}

static float4 sampleBilinear(device const float4* image, float2 pixel, uint width, uint height) {
    pixel = clamp(pixel, float2(0.0f), float2(float(width - 1), float(height - 1)));
    uint2 p0 = uint2(floor(pixel));
    uint2 p1 = min(p0 + uint2(1), uint2(width - 1, height - 1));
    float2 f = fract(pixel);
    float4 a = mix(image[p0.y * width + p0.x], image[p0.y * width + p1.x], f.x);
    float4 b = mix(image[p1.y * width + p0.x], image[p1.y * width + p1.x], f.x);
    return mix(a, b, f.y);
}

static float4 sampleInteger(device const float4* image, int2 pixel, uint width, uint height) {
    int2 bounded = clamp(pixel, int2(0), int2(int(width) - 1, int(height) - 1));
    return image[uint(bounded.y) * width + uint(bounded.x)];
}

static float4 sampleNearest(device const float4* image, float2 pixel, uint width, uint height) {
    return sampleInteger(image, int2(floor(pixel + 0.5f)), width, height);
}

static float3 thresholdHighlightResponse(float3 color,float threshold,float knee) {
    color=max(color,float3(0.0f));
    float luminance=dot(color,float3(0.2126f,0.7152f,0.0722f));
    float width=max(knee,0.0f);
    float excess;
    if(width<=1e-6f) excess=max(luminance-threshold,0.0f);
    else {
        float x=luminance-threshold;
        if(x<=-width) excess=0.0f;
        else if(x>=width) excess=x;
        else {
            float t=(x+width)/(2.0f*width);
            excess=width*t*t;
        }
    }
    return color*excess/max(luminance,1e-6f);
}

static float defocusResponse(float depth,constant LDBOpticsParameters& p) {
    float onset=clamp(p.responseDefocusOnset,0.0f,1.0f);
    float falloff=max(clamp(p.responseDefocusFalloff,0.0f,1.0f),onset+1e-4f);
    return smoothstep(onset,falloff,
                      abs(depth-clamp(p.depthFocus,0.0f,1.0f)));
}

static float depthLayerSimilarity(float targetDepth,float sampleDepth,
                                  constant LDBOpticsParameters& p) {
    // Softness 0.5 exactly reproduces the approved historical .035/.16
    // transition. Lower values protect crisp mattes; higher values tolerate
    // soft, noisy, or low-resolution neural depth boundaries.
    float softness=clamp(p.depthEdgeSoftness,0.0f,1.0f);
    float inner=mix(.005f,.065f,softness);
    float outer=mix(.04f,.28f,softness);
    return 1.0f-smoothstep(inner,outer,abs(sampleDepth-targetDepth));
}

static float protectedLayerAgreement(float targetDepth,float sampleDepth,
                                     constant LDBOpticsParameters& p) {
    float sameLayer=depthLayerSimilarity(targetDepth,sampleDepth,p);
    float protectedAgreement=mix(.12f,1.0f,sameLayer);
    return mix(1.0f,protectedAgreement,
               clamp(p.responseScatterEdgeProtection,0.0f,1.0f));
}

static float variationPhase(uint seed) {
    // Integer hashing avoids frame state and produces a deterministic phase on
    // every Apple Silicon render. It is not image noise and never changes with
    // time unless the user animates the seed.
    uint h=seed*747796405u+2891336453u;
    h=((h>>((h>>28u)+4u))^h)*277803737u;
    h=(h>>22u)^h;
    return float(h&0x00ffffffu)/float(0x01000000u)*M_PI_F*2.0f;
}

static float normalizedDepth(float4 sample,constant LDBOpticsParameters& p) {
    float raw=p.depthChannel==1u?sample.r:(p.depthChannel==2u?sample.g:(p.depthChannel==3u?sample.b:(p.depthChannel==4u?sample.a:dot(sample.rgb,float3(.272229f,.674082f,.053689f)))));
    float n=clamp((raw-p.depthNear)/max(abs(p.depthFar-p.depthNear),1e-6f),0.0f,1.0f);
    if(p.depthMode==1u) n=1.0f-n;             // near white
    else if(p.depthMode==4u) n=1.0f-n;        // inverse Z / disparity
    else if(p.depthMode==5u) n=log2(1.0f+15.0f*n)/4.0f;
    return n;
}

static float depthSampleAgreement(float targetDepth,float sampleDepth,
                                  constant LDBOpticsParameters& p) {
    // Same-layer samples always participate. Across a hard jump, farther
    // background is prevented from bleeding into foreground. A nearer sample
    // may expand over a farther target only in proportion to its own defocus;
    // this keeps focused silhouettes crisp while allowing defocused foreground
    // bokeh to soften outward instead of producing a cardboard-cutout edge.
    float sameLayer=depthLayerSimilarity(targetDepth,sampleDepth,p);
    float sourceDefocus=defocusResponse(sampleDepth,p);
    float nearerExpansion=sampleDepth<targetDepth?sourceDefocus:0.0f;
    float protectedAgreement=max(sameLayer,nearerExpansion);
    return mix(1.0f,protectedAgreement,
               clamp(p.responseScatterEdgeProtection,0.0f,1.0f));
}

static float4 smoothAxisBlur(device const float4* image, float2 pixel, float2 axis,
                             float radius, uint width, uint height) {
    if (radius <= 0.001f) return sampleBilinear(image, pixel, width, height);
    float2 halfOffset = axis * radius * 0.5f;
    float2 fullOffset = axis * radius;
    return sampleBilinear(image, pixel, width, height) * 0.40f
         + (sampleBilinear(image, pixel + halfOffset, width, height)
          + sampleBilinear(image, pixel - halfOffset, width, height)) * 0.20f
         + (sampleBilinear(image, pixel + fullOffset, width, height)
          + sampleBilinear(image, pixel - fullOffset, width, height)) * 0.10f;
}

static float3 smoothIsotropicBlur(device const float4* image,float2 pixel,float radius,
                                  uint width,uint height) {
    if(radius<=0.001f)return sampleBilinear(image,pixel,width,height).rgb;
    float3 result=sampleBilinear(image,pixel,width,height).rgb*.25f;
    constexpr int innerTaps=8;
    for(int i=0;i<innerTaps;++i){
        float angle=6.28318530718f*(float(i)+.5f)/float(innerTaps);
        float2 offset=float2(cos(angle),sin(angle))*radius*.48f;
        result+=sampleBilinear(image,pixel+offset,width,height).rgb*(.45f/float(innerTaps));
    }
    constexpr int outerTaps=12;
    for(int i=0;i<outerTaps;++i){
        float angle=6.28318530718f*(float(i)+.5f)/float(outerTaps)+.19f;
        float2 offset=float2(cos(angle),sin(angle))*radius;
        result+=sampleBilinear(image,pixel+offset,width,height).rgb*(.30f/float(outerTaps));
    }
    return result;
}

static float2 distortCoordinate(float2 uv, constant LDBOpticsParameters& p) {
    float2 q = uv - p.opticalCenter;
    // Squeeze describes an elliptical lens field, not a second image desqueeze.
    // It therefore changes the spatial response of off-axis characteristics
    // while leaving a completely neutral image untouched.
    float fieldAspect = sqrt(max(p.anamorphicSqueeze, 0.001f));
    q.x *= fieldAspect;
    float r2 = dot(q, q) * 4.0f;
    float scale = 1.0f + p.distortionK1 * r2 + p.distortionK2 * r2 * r2
                  + p.moustacheK3 * r2 * r2 * r2;
    float theta = p.swirl * r2 * 0.08f;
    float s = sin(theta), c = cos(theta);
    q = float2(c * q.x - s * q.y, s * q.x + c * q.y);
    q *= scale;
    if (p.anamorphicDistortion != 0.0f) {
        // Cylindrical groups characteristically bend the horizontal and
        // vertical field by different amounts. This remains a field response,
        // never a squeeze/desqueeze operation.
        float amount = clamp(p.anamorphicDistortion, -1.0f, 1.0f);
        q *= float2(1.0f + amount * r2,
                    1.0f - amount * r2 * .22f);
    }
    q.x /= fieldAspect;
    return q + p.opticalCenter;
}

static float vignetteAt(float2 uv, constant LDBOpticsParameters& p) {
    float2 q = uv - p.opticalCenter;
    q.x *= sqrt(max(p.anamorphicSqueeze, 0.001f));
    float r2 = dot(q, q) * 4.0f;
    float natural = exp(-p.vignetteNatural * r2);
    float optical = exp(-p.vignetteOptical * r2 * r2);
    float2 circleQ = float2(q.x, q.y / max(p.imageCircleAspect, 0.01f));
    float circleR = length(circleQ) * 2.0f;
    float edge0 = max(0.001f, p.imageCircleSize - p.imageCircleSoftness);
    float mechanical = 1.0f - smoothstep(edge0, p.imageCircleSize, circleR);
    mechanical = mix(1.0f, mechanical, clamp(p.vignetteMechanical, 0.0f, 1.0f));
    return clamp(natural * optical * mechanical, 0.0f, 1.0f);
}

kernel void ldbOpticsMain(device const float4* source [[buffer(0)]],
                          device float4* direct [[buffer(1)]],
                          device float4* highlights [[buffer(2)]],
                          constant LDBOpticsParameters& p [[buffer(3)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(p.imageSize.x), height = uint(p.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;

    float2 uv = (float2(gid) + 0.5f) / p.imageSize;
    float2 warped = distortCoordinate(uv, p);
    float2 basePixel = warped * p.imageSize - 0.5f;
    float2 opticalField = warped - p.opticalCenter;
    float fieldAspect = sqrt(max(p.anamorphicSqueeze, 0.001f));
    float2 fieldMetric = float2(opticalField.x * fieldAspect, opticalField.y);
    float radius = clamp(length(fieldMetric) * 2.0f, 0.0f, 1.5f);
    // Gradient of the elliptical radius gives the perceptual radial direction
    // in image coordinates.
    float2 radial = normalize(float2(opticalField.x * fieldAspect * fieldAspect, opticalField.y)
                              + float2(1e-6f, 0.0f));
    float2 tangent = float2(-radial.y, radial.x);
    float variation=clamp(p.variationAmount,0.0f,1.0f);
    float phase=variationPhase(p.variationSeed);

    // Field Shape is deliberately independent from Optical Center. Optical
    // Center continues to govern distortion, vignette and lateral chromatic
    // displacement, while this field controls focus/detail/off-axis response.
    // The neutral branch retains the exact established field calculation.
    bool customField = p.fieldCenter.x != .5f || p.fieldCenter.y != .5f
                    || p.fieldAspect != 1.0f || p.fieldRotation != 0.0f;
    if (customField) {
        float2 shaped = warped - p.fieldCenter;
        float angle = p.fieldRotation * (M_PI_F / 180.0f);
        float s = sin(angle), c = cos(angle);
        shaped = float2(c * shaped.x + s * shaped.y,
                       -s * shaped.x + c * shaped.y);
        float aspect = sqrt(clamp(p.fieldAspect, .25f, 4.0f));
        float2 shapedMetric = float2(shaped.x * aspect, shaped.y / aspect);
        radius = clamp(length(shapedMetric) * 2.0f, 0.0f, 1.5f);
        float2 localRadial = normalize(float2(shaped.x * aspect * aspect,
                                              shaped.y / (aspect * aspect))
                                       + float2(1e-6f, 0.0f));
        radial = float2(c * localRadial.x - s * localRadial.y,
                        s * localRadial.x + c * localRadial.y);
        tangent = float2(-radial.y, radial.x);
    }
    if(variation>0.0f&&p.variationFieldAsymmetry!=0.0f) {
        float2 direction=float2(cos(phase),sin(phase));
        float asymmetry=dot(warped-p.fieldCenter,direction)*2.0f
                       *clamp(p.variationFieldAsymmetry,-1.0f,1.0f)*variation;
        radius=clamp(radius*(1.0f+asymmetry*.65f),0.0f,1.5f);
    }

    float opticalRadius = clamp(length(fieldMetric) * 2.0f, 0.0f, 1.5f);
    float2 opticalRadial = normalize(float2(opticalField.x * fieldAspect * fieldAspect,
                                             opticalField.y) + float2(1e-6f, 0.0f));
    float caR = p.lateralCARed * opticalRadius * opticalRadius;
    float caB = p.lateralCABlue * opticalRadius * opticalRadius;
    float2 pixelScale = p.imageSize;
    float4 center = sampleBilinear(source, basePixel, width, height);
    float2 redOffset=opticalRadial*caR*pixelScale*.002f;
    float2 blueOffset=opticalRadial*caB*pixelScale*.002f;
    if(variation>0.0f&&p.variationChromaticAsymmetry!=0.0f) {
        float2 variationAxis=float2(cos(phase),sin(phase));
        float signedField=dot(opticalField,variationAxis)*2.0f;
        float shift=clamp(p.variationChromaticAsymmetry,-2.0f,2.0f)
                   *variation*signedField*opticalRadius*p.imageSize.x*.0012f;
        redOffset+=variationAxis*shift;
        blueOffset-=variationAxis*shift;
    }
    if (p.anamorphicAberration != 0.0f) {
        float amount = clamp(p.anamorphicAberration, -2.0f, 2.0f)
                     * opticalRadius * opticalRadius;
        float horizontalPixels = amount * p.imageSize.x * .0015f;
        redOffset+=float2(horizontalPixels,0.0f);
        blueOffset-=float2(horizontalPixels,0.0f);
    }
    center.r=sampleBilinear(source,basePixel+redOffset,width,height).r;
    center.b=sampleBilinear(source,basePixel+blueOffset,width,height).b;

    // These are normalized perceptual controls. Each must remain independently
    // visible; earlier versions merely modulated an existing field blur by 1–2%,
    // making all three appear broken unless another control was already active.
    float fieldOnset=clamp(p.responseFieldOnset,0.0f,1.5f);
    float fieldFalloff=max(clamp(p.responseFieldFalloff,0.0f,1.5f),fieldOnset+1e-4f);
    float fieldEnvelope = smoothstep(fieldOnset,fieldFalloff,clamp(radius,0.0f,1.5f));
    // Corner loss and curvature predate the configurable envelope and were
    // expressed directly in powers of radius. Scale those established curves
    // relative to their original smoothstep(0,1) envelope so the defaults are
    // unchanged while custom onset/falloff values affect every field family.
    float establishedFieldEnvelope=smoothstep(0.0f,1.0f,clamp(radius,0.0f,1.5f));
    float fieldResponseScale=establishedFieldEnvelope>1e-6f
        ?fieldEnvelope/establishedFieldEnvelope:0.0f;
    float curvatureBlur = clamp(p.fieldCurvature, 0.0f, 2.0f) * radius * radius * radius * radius * 2.4f;
    float fieldBlur = max(0.0f, clamp(p.cornerSharpnessLoss, 0.0f, 2.0f) * radius * radius * 2.4f + curvatureBlur);
    fieldBlur*=fieldResponseScale;
    float astigmatism = clamp(p.astigmatism, -2.0f, 2.0f);
    float radialSmear = clamp(p.radialSmear, 0.0f, 2.0f);
    float tangentSmear = clamp(p.tangentialSmear, 0.0f, 2.0f);
    float radialCharacter = max(astigmatism, 0.0f) * 3.5f + radialSmear * 4.5f;
    float tangentCharacter = max(-astigmatism, 0.0f) * 3.5f + tangentSmear * 4.5f;
    float radialWidth = fieldBlur + fieldEnvelope * radialCharacter;
    float tangentWidth = fieldBlur + fieldEnvelope * tangentCharacter;
    float4 radialBlur = smoothAxisBlur(source, basePixel, radial, radialWidth, width, height);
    float4 tangentBlur = smoothAxisBlur(source, basePixel, tangent, tangentWidth, width, height);
    float characterMix = fieldEnvelope * (abs(astigmatism) * 0.60f
                       + radialSmear * 0.45f + tangentSmear * 0.45f);
    float focusMix = clamp(fieldBlur * 0.32f + characterMix, 0.0f, 1.0f);
    float4 optical = mix(center, (radialBlur + tangentBlur) * 0.5f, focusMix);

    // A compact isotropic low-pass isolates focus-transition chroma. In the
    // default depth-free mode the image transition selects the tint, preserving
    // the approved approximation. With external depth, distance from the focus
    // plane supplies both near/far selection and defocus strength.
    float axialStrength = clamp(p.longitudinalCA, 0.0f, 2.0f);
    if (axialStrength > 0.0f) {
        float axialRadius = clamp(p.longitudinalCARadius, 0.5f, 12.0f);
        float innerRadius = max(0.5f, axialRadius * 0.42f);
        float3 innerBlur=smoothIsotropicBlur(source,basePixel,innerRadius,width,height);
        float3 outerBlur=smoothIsotropicBlur(source,basePixel,axialRadius,width,height);
        constexpr float3 lumaWeights = float3(0.272229f, 0.674082f, 0.053689f);
        float centerL=max(dot(center.rgb,lumaWeights),0.0f);
        float transition = dot(innerBlur - outerBlur, lumaWeights);
        float innerL=max(dot(innerBlur,lumaWeights),0.0f),outerL=max(dot(outerBlur,lumaWeights),0.0f);
        // Combine two bands so Radius visibly broadens the response and softly
        // defocused sources are not rejected merely because their inner and
        // outer averages are similar. The low floor retains small practical
        // highlights without reviving the old isolated-point artefacts.
        float broadTransition=centerL-outerL;
        float edgeEnergy=abs(transition)*.70f+abs(broadTransition)*.55f;
        float footprintSupport=smoothstep(.008f,.16f,max(centerL,max(innerL,outerL)));
        float3 nearTint = p.nearFocusColor / max(dot(p.nearFocusColor, lumaWeights), 1e-4f) - 1.0f;
        float3 farTint = p.farFocusColor / max(dot(p.farFocusColor, lumaWeights), 1e-4f) - 1.0f;
        float3 axialChroma;
        if (p.depthMode > 0u) {
            float depth = normalizedDepth(sampleBilinear(source, basePixel, width, height), p);
            float signedDefocus = depth - clamp(p.depthFocus, 0.0f, 1.0f);
            float defocus = defocusResponse(depth,p);
            float3 depthTint = signedDefocus < 0.0f ? nearTint : farTint;
            axialChroma = edgeEnergy * depthTint * defocus;
        } else {
            // Preserve image-derived near/far polarity while giving Radius a
            // broader visible footprint than the original narrow band-pass.
            float signedTransition=transition+broadTransition*.45f;
            axialChroma = max(signedTransition, 0.0f) * nearTint
                        + max(-signedTransition, 0.0f) * farTint;
        }
        // Chroma-only gain is intentionally stronger than the original
        // conservative prototype: normalized lens footage otherwise hides the
        // response after the working-space display transform.
        float creativeGain=mix(.72f,1.05f,clamp(axialStrength*.5f,0.0f,1.0f));
        optical.rgb += axialChroma * axialStrength * creativeGain * footprintSupport;
    }

    // Perceptual MTF/detail transfer: two compact spatial bands with field-aware
    // sagittal and tangential response. Signed controls permit enhancement or loss.
    if (p.microContrast != 0.0f || p.fineDetail != 0.0f || p.detailEdgeFalloff != 0.0f
        || p.sagittalDetail != 0.0f || p.tangentialDetail != 0.0f) {
        float scale = clamp(p.detailScale, 0.25f, 8.0f);
        float4 fineRadialBase = (sampleBilinear(source, basePixel + radial * scale, width, height)
                               + sampleBilinear(source, basePixel - radial * scale, width, height)) * 0.5f;
        float4 fineTangentBase = (sampleBilinear(source, basePixel + tangent * scale, width, height)
                                + sampleBilinear(source, basePixel - tangent * scale, width, height)) * 0.5f;
        float3 radialBand = center.rgb - fineRadialBase.rgb;
        float3 tangentBand = center.rgb - fineTangentBase.rgb;
        float3 fineBand = (radialBand + tangentBand) * 0.5f;
        float4 fineBase = (fineRadialBase + fineTangentBase) * 0.5f;
        float mediumRadius = scale * 3.0f;
        float4 outerBase = (sampleBilinear(source, basePixel + radial * mediumRadius, width, height)
                          + sampleBilinear(source, basePixel - radial * mediumRadius, width, height)
                          + sampleBilinear(source, basePixel + tangent * mediumRadius, width, height)
                          + sampleBilinear(source, basePixel - tangent * mediumRadius, width, height)) * 0.25f;
        // Weighted inner and outer samples approximate a compact Gaussian band
        // and avoid the doubled edges produced by a single sparse outer ring.
        float4 mediumBase = fineBase * 0.7f + outerBase * 0.3f;
        float3 mediumBand = center.rgb - mediumBase.rgb;
        float fieldWeight = fieldEnvelope;
        float edgeLoss = clamp(p.detailEdgeFalloff, 0.0f, 2.0f) * fieldWeight;
        float3 transfer = fineBand * p.fineDetail * 0.35f
                        + mediumBand * p.microContrast * 0.28f;
        transfer += fieldWeight * (radialBand * p.sagittalDetail
                                  + tangentBand * p.tangentialDetail) * 0.35f;
        transfer -= edgeLoss * (fineBand * 0.45f + mediumBand * 0.25f);
        float3 localMin = min(center.rgb, min(fineBase.rgb, outerBase.rgb));
        float3 localMax = max(center.rgb, max(fineBase.rgb, outerBase.rgb));
        float3 allowance = (localMax - localMin) * 0.08f + 1e-5f;
        optical.rgb = clamp(optical.rgb + transfer, localMin - allowance, localMax + allowance);
    }

    // Perceptual coma is restricted to super-white/specular energy. Applying a
    // one-sided PSF to ordinary SDR edges reads as a shifted image, not a lens.
    float comaStrength = clamp(abs(p.coma), 0.0f, 2.0f);
    if (comaStrength > 0.0f && radius > 0.02f) {
        float directionSign = p.coma >= 0.0f ? 1.0f : -1.0f;
        float3 comaGlow = 0.0f;
        float weightSum = 0.0f;
        constexpr int comaSteps = 12;
        for (int i=0;i<comaSteps;++i) {
            float t=(float(i)+0.5f)/float(comaSteps);
            float distance=comaStrength*12.0f*t;
            // Broaden away from the source so point highlights read as a
            // continuous comet/fan rather than a thin diagonal scratch.
            float wing=distance*(0.12f+0.45f*t);
            float2 sourcePixel=basePixel-radial*distance*directionSign;
            float weight=exp(-1.8f*t);
            float threshold=clamp(p.comaThreshold,0.0f,4.0f);
            float3 sampleCenter=thresholdHighlightResponse(sampleBilinear(source,sourcePixel,width,height).rgb,
                                                           threshold,p.responseHighlightKnee);
            float3 sampleWings=thresholdHighlightResponse(sampleBilinear(source,sourcePixel+tangent*wing,width,height).rgb,
                                                          threshold,p.responseHighlightKnee)
                              +thresholdHighlightResponse(sampleBilinear(source,sourcePixel-tangent*wing,width,height).rgb,
                                                          threshold,p.responseHighlightKnee);
            float centerWeight=mix(0.72f,0.32f,t);
            comaGlow+=(sampleCenter*centerWeight+sampleWings*((1.0f-centerWeight)*0.5f))*weight;
            weightSum+=weight;
        }
        optical.rgb+=comaGlow/max(weightSum,1e-6f)*comaStrength*0.30f*radius*radius;
    }

    float luminance = dot(max(center.rgb, float3(0.0f)), float3(0.2126f, 0.7152f, 0.0722f));
    float highlight = max(0.0f, luminance - p.bloomThreshold);

    optical.rgb *= vignetteAt(uv, p);
    float3 transmission = mix(float3(1.0f), p.transmissionColor, p.transmissionColorAmount);
    optical.rgb *= transmission;
    if (p.transmissionDensity != 0.0f) {
        optical.rgb *= exp2(-clamp(p.transmissionDensity, -2.0f, 2.0f));
    }
    if (p.transmissionContrast != 0.0f) {
        constexpr float pivot = .18f;
        float contrast = exp2(clamp(p.transmissionContrast, -2.0f, 2.0f));
        float3 signValue = sign(optical.rgb);
        optical.rgb = signValue * pivot
                    * pow(max(abs(optical.rgb) / pivot, float3(1e-6f)), contrast);
    }
    if (p.transmissionHighlightSoftness > 0.0f) {
        float softness = clamp(p.transmissionHighlightSoftness, 0.0f, 2.0f);
        // Preserve 18% middle grey while progressively compressing only the
        // positive highlight side. Negative extended-range values pass through.
        float3 positive = max(optical.rgb, float3(0.0f));
        float3 softened = positive * (1.0f + softness * .18f)
                        / (1.0f + softness * positive);
        optical.rgb = select(optical.rgb, softened, optical.rgb >= 0.0f);
    }
    if(variation>0.0f&&p.variationTransmissionUnevenness!=0.0f) {
        float2 direction=float2(cos(phase+1.7f),sin(phase+1.7f));
        float broad=dot(uv-float2(.5f),direction)*1.35f
                   +sin((uv.x*1.7f+uv.y*1.3f)*M_PI_F+phase)*.18f;
        float uneven=1.0f+clamp(p.variationTransmissionUnevenness,-1.0f,1.0f)
                           *variation*broad*.35f;
        optical.rgb*=max(uneven,.2f);
    }
    uint index = gid.y * width + gid.x;
    direct[index] = float4(optical.rgb, source[index].a);
    if ((p.processingFlags & 1u) != 0u)
        highlights[index] = float4(max(center.rgb, float3(0.0f)) * highlight / max(luminance, 1e-6f), 1.0f);
}

static int scatterTapLimit(constant LDBOpticsParameters& p) {
    (void)p;
    return 16;
}

static float4 blurLine(device const float4* image, float2 pixel, float2 axis, float radius,
                       uint width, uint height, int maximumTaps) {
    if (radius <= 0.001f) return sampleBilinear(image, pixel, width, height);
    float4 result = 0.0f;
    float weightSum = 0.0f;
    constexpr float sigma = 0.45f;
    int tapRadius = clamp(int(ceil(radius)), 1, maximumTaps);
    for (int tap = -16; tap <= 16; ++tap) {
        if (abs(tap) > tapRadius) continue;
        float normalizedOffset = float(tap) / float(tapRadius);
        float weight = exp(-0.5f * (normalizedOffset / sigma) * (normalizedOffset / sigma));
        result += sampleBilinear(image, pixel + axis * radius * normalizedOffset,
                                 width, height) * weight;
        weightSum += weight;
    }
    return result / weightSum;
}

static float scatterDepthAgreement(float targetDepth,float sampleDepth,
                                   constant LDBOpticsParameters& p) {
    // A near layer occludes light scattered by a farther layer. Light from a
    // nearer source may still veil a farther target, which preserves the useful
    // photographic spread of foreground practicals without background bloom
    // leaking through silhouettes.
    float sameLayer=depthLayerSimilarity(targetDepth,sampleDepth,p);
    float directed=max(sameLayer,sampleDepth<targetDepth?1.0f:0.0f);
    // Bloom and veiling glare are formed inside the lens after scene
    // occlusion, so a farther practical must never be cut out completely.
    // Retain a restrained optical floor while strongly reducing the spill.
    float protectedAgreement=mix(.12f,1.0f,directed);
    return mix(1.0f,protectedAgreement,
               clamp(p.responseScatterEdgeProtection,0.0f,1.0f));
}

static float4 blurLineDepthAware(device const float4* image,float2 pixel,float2 axis,
                                 float radius,uint width,uint height,
                                 constant LDBOpticsParameters& p,int maximumTaps) {
    if(radius<=.001f) return sampleBilinear(image,pixel,width,height);
    float4 centre=sampleNearest(image,pixel,width,height);
    float targetDepth=normalizedDepth(centre,p);
    float3 result=0.0f;
    float weightSum=0.0f;
    constexpr float sigma=.45f;
    int tapRadius=clamp(int(ceil(radius)),1,maximumTaps);
    for(int tap=-16;tap<=16;++tap) {
        if(abs(tap)>tapRadius) continue;
        float normalizedOffset=float(tap)/float(tapRadius);
        float weight=exp(-.5f*(normalizedOffset/sigma)*(normalizedOffset/sigma));
        float4 sample=sampleBilinear(image,pixel+axis*radius*normalizedOffset,width,height);
        float sampleDepth=normalizedDepth(sampleNearest(image,
            pixel+axis*radius*normalizedOffset,width,height),p);
        weight*=scatterDepthAgreement(targetDepth,sampleDepth,p);
        result+=sample.rgb*weight;
        weightSum+=weight;
    }
    return float4(weightSum>1e-6f?result/weightSum:centre.rgb,centre.a);
}

kernel void ldbBlurAperture(device const float4* source [[buffer(0)]],
                            device float4* destination [[buffer(1)]],
                            constant LDBScatterParameters& scatter [[buffer(2)]],
                            constant LDBOpticsParameters& p [[buffer(3)]],
                            uint2 gid [[thread_position_in_grid]]) {
    uint width=uint(scatter.imageSize.x),height=uint(scatter.imageSize.y);
    if(gid.x>=width||gid.y>=height) return;
    if(scatter.scale>0u) {
        // Each low-discrepancy point represents a finite pupil area. Reconstruct
        // that area at a radius derived from sample density, instead of leaving
        // the points visible or applying a fixed blur that fails at large radii.
        float reconstructionRadius=clamp(scatter.radiusX*0.16f,0.75f,4.0f);
        float4 centreSample=source[gid.y*width+gid.x];
        float targetDepth=0.0f;
        if(p.depthMode>0u) {
            float depth=normalizedDepth(centreSample,p);
            targetDepth=depth;
            float defocus=defocusResponse(depth,p);
            reconstructionRadius*=defocus;
            if(reconstructionRadius<=.001f) {
                destination[gid.y*width+gid.x]=source[gid.y*width+gid.x];
                return;
            }
        }
        float sigma=max(reconstructionRadius*0.52f,0.55f);
        float4 smoothed=0.0f;
        float weightSum=0.0f;
        for(int tap=-4;tap<=4;++tap) {
            if(abs(float(tap))>reconstructionRadius+0.5f) continue;
            float weight=exp(-0.5f*float(tap*tap)/(sigma*sigma));
            int2 offset=scatter.scale==1u?int2(tap,0):int2(0,tap);
            float4 tapSample=sampleInteger(source,int2(gid)+offset,width,height);
            if(p.depthMode>0u)
                weight*=depthSampleAgreement(targetDepth,normalizedDepth(tapSample,p),p);
            smoothed+=tapSample*weight;
            weightSum+=weight;
        }
        float4 reconstructed=weightSum>1e-6f?smoothed/weightSum:centreSample;
        if(p.depthMode>0u) reconstructed.a=centreSample.a;
        destination[gid.y*width+gid.x]=reconstructed;
        return;
    }
    float2 uv=(float2(gid)+0.5f)/scatter.imageSize;
    float2 field=uv-p.opticalCenter;
    float2 radial=normalize(field+float2(1e-6f,0.0f));
    float2 tangent=float2(-radial.y,radial.x);
    float fieldRadius=clamp(length(field)*2.0f,0.0f,1.0f);
    float catEye=clamp(p.apertureCatEye,0.0f,1.0f)*smoothstep(0.15f,1.0f,fieldRadius);
    float2 apertureX=normalize(float2(scatter.axisX,scatter.axisY)+float2(1e-6f,0.0f));
    float2 apertureY=float2(-apertureX.y,apertureX.x);
    float reconstructionRadius=clamp(scatter.radiusX*0.16f,0.75f,4.0f);
    float radius=max(scatter.radiusX-min(reconstructionRadius*0.65f,scatter.radiusX*0.15f),0.0f);
    float4 centreSample=source[gid.y*width+gid.x];
    float targetDepth=0.0f;
    if(p.depthMode>0u) {
        float depth=normalizedDepth(centreSample,p);
        targetDepth=depth;
        float defocus=defocusResponse(depth,p);
        radius*=defocus;
        if(radius<=.001f) {
            destination[gid.y*width+gid.x]=source[gid.y*width+gid.x];
            return;
        }
    }
    float softness=clamp(scatter.threshold,0.0f,1.0f);
    float aspect=p.apertureShape==2u?sqrt(clamp(p.apertureAspect,0.25f,4.0f)):1.0f;
    uint blades=clamp(p.apertureBladeCount,3u,32u);
    float curvature=clamp(p.apertureBladeCurvature,0.0f,1.0f);
    // Do not privilege a zero-offset source sample: it leaves a concentrated
    // copy of point highlights inside an otherwise defocused pupil footprint.
    float4 result=0.0f;
    float weightSum=0.0f;
    constexpr uint sampleCount=96u;
    constexpr float goldenAngle=2.39996322972865332f;
    // The pupil sequence is invariant across the frame. Build it by recurrence
    // instead of evaluating sin/cos for all 96 samples at every output pixel.
    constexpr float goldenCos=-0.737368878f;
    constexpr float goldenSin=0.675490294f;
    float2 direction=float2(1.0f,0.0f);
    // exp(-1.6 * diskRadius^2) is also invariant apart from the sample index.
    // Its exponent advances linearly, so update it multiplicatively rather
    // than evaluating another transcendental function for every sample.
    float softProfile=0.991701293f;
    constexpr float softProfileStep=0.983471454f;
    for(uint i=0u;i<sampleCount;++i) {
        float diskRadius=sqrt((float(i)+0.5f)/float(sampleCount));
        float angle=float(i)*goldenAngle;
        float boundary=1.0f;
        if(p.apertureShape==1u) {
            float sector=2.0f*M_PI_F/float(blades);
            float local=fmod(angle+M_PI_F,sector)-0.5f*sector;
            float polygonBoundary=cos(M_PI_F/float(blades))/max(cos(local),1e-4f);
            boundary=mix(polygonBoundary,1.0f,curvature);
        }
        if(p.variationAmount>0.0f&&p.variationPupilIrregularity!=0.0f) {
            float phase=variationPhase(p.variationSeed);
            float irregular=sin(angle*3.0f+phase)*.62f+sin(angle*5.0f-phase*.7f)*.38f;
            boundary*=1.0f+irregular*clamp(p.variationPupilIrregularity,-1.0f,1.0f)
                            *clamp(p.variationAmount,0.0f,1.0f)*.16f;
        }
        float2 localPoint=direction*diskRadius*boundary;
        localPoint*=float2(aspect,1.0f/aspect);
        float2 offset=(apertureX*localPoint.x+apertureY*localPoint.y)*radius;
        // Cat-eye deformation is a filled off-axis pupil compression. Keeping a
        // non-zero radial width prevents extreme settings from collapsing into arcs.
        float radialScale=mix(1.0f,0.42f,catEye);
        float radialComponent=dot(offset,radial);
        float tangentialComponent=dot(offset,tangent);
        offset=radial*(radialComponent*radialScale)+tangent*tangentialComponent;
        float edgeWeight=mix(1.0f,softProfile,softness);
        float2 pupilPosition=float2(gid)+offset;
        float4 pupilSample=sampleBilinear(source,pupilPosition,width,height);
        if(p.depthMode>0u)
            edgeWeight*=depthSampleAgreement(targetDepth,
                normalizedDepth(sampleNearest(source,pupilPosition,width,height),p),p);
        result+=pupilSample*edgeWeight;
        weightSum+=edgeWeight;
        direction=float2(direction.x*goldenCos-direction.y*goldenSin,
                         direction.x*goldenSin+direction.y*goldenCos);
        softProfile*=softProfileStep;
    }
    float4 pupilResult=weightSum>1e-6f?result/weightSum:centreSample;
    if(p.depthMode>0u) pupilResult.a=centreSample.a;
    destination[gid.y*width+gid.x]=pupilResult;
}

kernel void ldbDownsampleHighlights(device const float4* source [[buffer(0)]],
                                    device float4* destination [[buffer(1)]],
                                    constant LDBOpticsParameters& p [[buffer(2)]],
                                    constant LDBScatterParameters& scatter [[buffer(3)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(scatter.imageSize.x), height = uint(scatter.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    uint scale = max(scatter.scale, 1u);
    float3 sum = 0.0f;
    for (uint y = 0; y < scale; ++y) {
        for (uint x = 0; x < scale; ++x) {
            uint2 sourcePosition = min(gid * scale + uint2(x, y),
                                       uint2(uint(p.imageSize.x) - 1, uint(p.imageSize.y) - 1));
            float4 sourceSample=source[sourcePosition.y*uint(p.imageSize.x)+sourcePosition.x];
            float sourceWeight=1.0f;
            if(p.depthMode>0u&&scatter.axisX>1.5f) {
                float depth=normalizedDepth(sourceSample,p);
                sourceWeight=defocusResponse(depth,p);
            }
            sum+=thresholdHighlightResponse(sourceSample.rgb,scatter.threshold,
                                             p.responseHighlightKnee)*sourceWeight;
        }
    }
    uint2 depthPosition=min(gid*scale+uint2(scale/2u),
        uint2(uint(p.imageSize.x)-1,uint(p.imageSize.y)-1));
    float depthCarrier=source[depthPosition.y*uint(p.imageSize.x)+depthPosition.x].a;
    destination[gid.y * width + gid.x] = float4(sum / float(scale * scale),depthCarrier);
}

kernel void ldbBlurHorizontal(device const float4* source [[buffer(0)]],
                              device float4* destination [[buffer(1)]],
                              constant LDBScatterParameters& scatter [[buffer(2)]],
                              constant LDBOpticsParameters& p [[buffer(3)]],
                              uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(scatter.imageSize.x), height = uint(scatter.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    bool depthAware=p.depthMode>0u&&scatter.axisX>.5f;
    int maximumTaps=scatterTapLimit(p);
    destination[gid.y*width+gid.x]=depthAware
        ?blurLineDepthAware(source,float2(gid),float2(1,0),scatter.radiusX,width,height,p,maximumTaps)
        :blurLine(source,float2(gid),float2(1,0),scatter.radiusX,width,height,maximumTaps);
}

kernel void ldbBlurVertical(device const float4* source [[buffer(0)]],
                            device float4* destination [[buffer(1)]],
                            constant LDBScatterParameters& scatter [[buffer(2)]],
                            constant LDBOpticsParameters& p [[buffer(3)]],
                            uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(scatter.imageSize.x), height = uint(scatter.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    bool depthAware=p.depthMode>0u&&scatter.axisX>.5f;
    int maximumTaps=scatterTapLimit(p);
    destination[gid.y*width+gid.x]=depthAware
        ?blurLineDepthAware(source,float2(gid),float2(0,1),scatter.radiusY,width,height,p,maximumTaps)
        :blurLine(source,float2(gid),float2(0,1),scatter.radiusY,width,height,maximumTaps);
}

kernel void ldbComposite(device const float4* source [[buffer(0)]],
                         device const float4* direct [[buffer(1)]],
                         device const float4* bloomScattered [[buffer(2)]],
                         device const float4* glareScattered [[buffer(3)]],
                         device const float4* haloScattered [[buffer(4)]],
                         device const float4* apertureScattered [[buffer(5)]],
                         device const float4* flareScattered [[buffer(6)]],
                         device float4* destination [[buffer(7)]],
                         constant LDBOpticsParameters& p [[buffer(8)]],
                         constant LDBScatterParameters& bloomScatter [[buffer(9)]],
                         constant LDBScatterParameters& glareScatter [[buffer(10)]],
                         constant LDBScatterParameters& haloScatter [[buffer(11)]],
                         constant LDBScatterParameters& flareScatter [[buffer(12)]],
                         uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(p.imageSize.x), height = uint(p.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    uint index = gid.y * width + gid.x;
    float3 glareTint = mix(float3(1.0f), p.glareColor, p.glareColorAmount);
    float2 bloomPixel = (float2(gid) + 0.5f) / float(bloomScatter.scale) - 0.5f;
    float2 glarePixel = (float2(gid) + 0.5f) / float(glareScatter.scale) - 0.5f;
    float3 bloom = sampleBilinear(bloomScattered, bloomPixel,
                                  uint(bloomScatter.imageSize.x), uint(bloomScatter.imageSize.y)).rgb;
    float3 glare = sampleBilinear(glareScattered, glarePixel,
                                  uint(glareScatter.imageSize.x), uint(glareScatter.imageSize.y)).rgb;
    float2 haloPixel = (float2(gid) + 0.5f) / float(haloScatter.scale) - 0.5f;
    float3 halo = sampleBilinear(haloScattered, haloPixel,
                                 uint(haloScatter.imageSize.x), uint(haloScatter.imageSize.y)).rgb;
    float2 flarePixel = (float2(gid) + 0.5f) / float(flareScatter.scale) - 0.5f;
    float3 flare = sampleBilinear(flareScattered, flarePixel,
                                  uint(flareScatter.imageSize.x), uint(flareScatter.imageSize.y)).rgb;
    if(p.depthMode>0u) {
        float targetDepth=normalizedDepth(source[index],p);
        float bloomDepth=normalizedDepth(sampleNearest(bloomScattered,bloomPixel,
            uint(bloomScatter.imageSize.x),uint(bloomScatter.imageSize.y)),p);
        float glareDepth=normalizedDepth(sampleNearest(glareScattered,glarePixel,
            uint(glareScatter.imageSize.x),uint(glareScatter.imageSize.y)),p);
        // The scatter buffer alpha is the depth of its low-resolution target,
        // not the originating highlight. Use a symmetric reconstruction guard
        // here; directional occlusion has already happened inside the blur.
        bloom*=protectedLayerAgreement(targetDepth,bloomDepth,p);
        glare*=protectedLayerAgreement(targetDepth,glareDepth,p);
        float haloDepth=normalizedDepth(sampleNearest(haloScattered,haloPixel,
            uint(haloScatter.imageSize.x),uint(haloScatter.imageSize.y)),p);
        halo*=protectedLayerAgreement(targetDepth,haloDepth,p);
        float flareDepth=normalizedDepth(sampleNearest(flareScattered,flarePixel,
            uint(flareScatter.imageSize.x),uint(flareScatter.imageSize.y)),p);
        flare*=protectedLayerAgreement(targetDepth,flareDepth,p);
    }
    float apertureMix=clamp(p.apertureResponse,0.0f,1.0f);
    float3 directOptics=mix(direct[index].rgb,apertureScattered[index].rgb,apertureMix);
    float3 result = directOptics
                  + bloom * max(0.0f, p.bloomEnergy)
                  + glare * max(0.0f, p.glareEnergy) * glareTint
                  + halo * clamp(p.sphericalHalo, 0.0f, 2.0f) * 0.22f
                  + flare * max(0.0f, p.anamorphicFlareAmount)
                    * max(p.anamorphicFlareColor, float3(0.0f));
    uint diagnostic = p.processingFlags & LDBDiagnosticMask;
    if (diagnostic == LDBDiagnosticDifference)
        result = float3(0.18f) + (result - source[index].rgb) * 2.0f;
    else if (diagnostic == LDBDiagnosticScatter)
        result = (bloom * max(0.0f, p.bloomEnergy)
                + glare * max(0.0f, p.glareEnergy) * glareTint
                + halo * clamp(p.sphericalHalo, 0.0f, 2.0f) * 0.22f
                + flare * max(0.0f, p.anamorphicFlareAmount)
                  * max(p.anamorphicFlareColor, float3(0.0f))) * 2.0f;
    else if (diagnostic == LDBDiagnosticDirectOptics)
        result = directOptics;
    else if (diagnostic == LDBDiagnosticDepth) {
        float d=p.depthMode>0u?normalizedDepth(source[index],p):0.0f;
        result=float3(d);
    }
    else if (diagnostic == LDBDiagnosticDefocus) {
        float d=p.depthMode>0u?normalizedDepth(source[index],p):p.depthFocus;
        result=float3(defocusResponse(d,p));
    }
    else if (diagnostic == LDBDiagnosticDepthRejection) {
        float rejection=0.0f;
        if(p.depthMode>0u) {
            float target=normalizedDepth(source[index],p);
            float agreement=0.0f;
            agreement+=depthLayerSimilarity(target,normalizedDepth(sampleInteger(source,int2(gid)+int2(-1,0),width,height),p),p);
            agreement+=depthLayerSimilarity(target,normalizedDepth(sampleInteger(source,int2(gid)+int2(1,0),width,height),p),p);
            agreement+=depthLayerSimilarity(target,normalizedDepth(sampleInteger(source,int2(gid)+int2(0,-1),width,height),p),p);
            agreement+=depthLayerSimilarity(target,normalizedDepth(sampleInteger(source,int2(gid)+int2(0,1),width,height),p),p);
            rejection=(1.0f-agreement*.25f)*clamp(p.responseScatterEdgeProtection,0.0f,1.0f);
        }
        result=float3(rejection);
    }
    float outputAlpha=(p.depthMode>0u&&p.depthChannel==4u)?1.0f:source[index].a;
    destination[index] = float4(mix(source[index].rgb, result, clamp(p.effectBlend, 0.0f, 1.0f)), outputAlpha);
}

kernel void ldbEncodeFromLinearAP1(device const float4* original [[buffer(0)]],
                                   device const float4* linearAP1 [[buffer(1)]],
                                   device float4* destination [[buffer(2)]],
                                   constant LDBOpticsParameters& p [[buffer(3)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(p.imageSize.x), height = uint(p.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    uint index = gid.y * width + gid.x;
    if (p.effectBlend <= 0.0f) {
        destination[index] = original[index];
        return;
    }
    float3 linear = fromAP1(linearAP1[index].rgb, p.workingColorSpace);
    destination[index] = float4(encodeTransfer(linear.r, p.workingColorSpace),
                                encodeTransfer(linear.g, p.workingColorSpace),
                                encodeTransfer(linear.b, p.workingColorSpace),
                                linearAP1[index].a);
}
