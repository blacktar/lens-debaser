#include <metal_stdlib>
#include "LDBOpticsParameters.h"
using namespace metal;

// Promoted for Lens Debaser 1.68 after the focused preset comparison and
// light-transport audit. Keeping the switch defined here makes the accepted
// continuous field/aperture PSF the shipping path while preserving the old
// branch temporarily for controlled regression work.
#ifndef LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF
#define LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF 1
#endif

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
    // Knee is a dimensionless softness control. Map it into a width that can
    // approach, but never exceed, the active threshold. The previous absolute
    // scene-linear width allowed Knee > Threshold, which made the extraction
    // begin below zero and admitted virtually every positive shadow value.
    float positiveThreshold=max(threshold,0.0f);
    float width=positiveThreshold*(1.0f-exp(-max(knee,0.0f)));
    float excess;
    if(width<=1e-6f) excess=max(luminance-positiveThreshold,0.0f);
    else {
        float x=luminance-positiveThreshold;
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

static uint dirtHash(uint value) {
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    return value ^ (value >> 16u);
}

static float dirtRandom(int2 cell,uint seed,uint salt) {
    uint x=as_type<uint>(cell.x),y=as_type<uint>(cell.y);
    uint h=dirtHash(x*0x9e3779b9u^y*0x85ebca6bu^seed^salt*0xc2b2ae35u);
    return float(h&0x00ffffffu)/float(0x01000000u);
}

static float internalContaminationPattern(float2 uv,float scale,float smear,float amount,
                                          float softness,float complexity,uint seed,
                                          float imageAspect) {
    if(amount<=0.0f) return 0.0f;
    float smearMix=clamp(smear,0.0f,1.0f);
    float2 q=float2((uv.x-.5f)*imageAspect,uv.y-.5f);
    // Internal contamination is a continuous optical-density field, not
    // resolved debris. Overlapping lobes at several scales avoid both tiled
    // noise and the obvious three-blob structure of the earlier model.
    float broadClouds=0.0f,broadNormalization=0.0f;
    float soft=clamp(softness,0.0f,1.0f);
    float detail=clamp(complexity,0.0f,1.0f);
    // Six mutually-overlapping analytic lobes establish the low-frequency
    // density envelope. Complexity is generated separately as a continuous
    // domain-warped field, so it cannot expose individual oval elements.
    for(int i=0;i<6;++i) {
        int2 key=int2(41+i*5,73+i*7);
        float2 centre=float2(dirtRandom(key,seed,41u)-.5f,
                             dirtRandom(key,seed,42u)-.5f);
        centre.x*=imageAspect;
        float a=dirtRandom(key,seed,43u)*M_PI_F*2.0f;
        float cs=cos(a),sn=sin(a);
        float2 d=q-centre;
        float2 local=float2(cs*d.x+sn*d.y,-sn*d.x+cs*d.y);
        float radius=mix(.68f,.22f,float(i)/5.0f)
                    *mix(.72f,1.28f,dirtRandom(key,seed,44u))
                    *clamp(scale,.25f,4.0f);
        local.x/=mix(1.0f,2.8f,smearMix);
        float exponent=mix(3.4f,.72f,soft);
        float cloud=exp(-dot(local,local)/max(radius*radius,1e-4f)*exponent);
        float weight=mix(.55f,1.0f,dirtRandom(key,seed,45u));
        broadClouds+=cloud*weight;
        broadNormalization+=weight;
    }
    float broadDensity=broadClouds/max(broadNormalization*.58f,1e-4f);
    // Several non-axis-aligned waves are smoothly domain-warped by two lower-
    // frequency waves. Randomized phases retain deterministic Seed behavior
    // without a sampling lattice, cells, particles, or closed ring shapes.
    float phase0=dirtRandom(int2(113,197),seed,61u)*M_PI_F*2.0f;
    float phase1=dirtRandom(int2(127,211),seed,62u)*M_PI_F*2.0f;
    float phase2=dirtRandom(int2(139,223),seed,63u)*M_PI_F*2.0f;
    float2 fieldQ=q/max(clamp(scale,.25f,4.0f),.25f);
    fieldQ.x/=mix(1.0f,1.85f,smearMix);
    float2 warp=float2(sin(dot(fieldQ,float2(1.73f,2.41f))+phase0),
                       sin(dot(fieldQ,float2(-2.16f,1.37f))+phase1));
    float2 warped=fieldQ+warp*mix(.10f,.22f,soft);
    float continuousDetail=.50f
        +.24f*sin(dot(warped,float2(4.21f,2.63f))+phase1)
        +.16f*sin(dot(warped,float2(-3.17f,5.09f))+phase2)
        +.10f*sin(dot(warped,float2(7.13f,-2.29f))+phase0);
    continuousDetail=clamp(continuousDetail,0.0f,1.0f);
    // Complexity reshapes the broad field instead of adding standalone marks.
    float detailFactor=clamp(1.0f+(continuousDetail-.5f)*detail*.92f,.56f,1.46f);
    float density=broadDensity*detailFactor;
    density=smoothstep(0.0f,mix(.88f,.54f,soft),density);
    return clamp(density*mix(.48f,.66f,smearMix),0.0f,.72f);
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
    // Seventeen smoothly weighted samples prevent a wide footprint from
    // resolving into the five discrete copies produced by the legacy kernel.
    // The normalized locations cover three standard deviations; bilinear
    // source reads keep fractional radii continuous.
    // Moderate footprints use 17 samples. Very wide off-axis footprints use
    // 33 so their sample spacing does not resolve as faint parallel copies.
    // This branch is experimental and is benchmarked separately with the
    // extreme-field case before any production adoption.
    int pairs = radius > 7.25f ? 16 : 8;
    float4 result = sampleBilinear(image, pixel, width, height);
    float weightSum = 1.0f;
    for (int i = 1; i <= 16; ++i) {
        if (i > pairs) continue;
        float position = float(i) / float(pairs);
        float weight = exp(-4.5f * position * position);
        // Match the legacy five-tap kernel's second moment (0.30*r^2).
        // Without this scale the Gaussian candidate has only 60% of the
        // baseline RMS width, making a quality comparison misleadingly easy.
        float matchedSpread = pairs == 16 ? 1.6602315f : 1.6557839f;
        float2 offset = axis * radius * position * matchedSpread;
        result += (sampleBilinear(image, pixel + offset, width, height)
                 + sampleBilinear(image, pixel - offset, width, height)) * weight;
        weightSum += 2.0f * weight;
    }
    return result / weightSum;
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

static float2 refractiveOffsetAt(float2 uv, constant LDBOpticsParameters& p) {
    float amount=clamp(p.refractiveIrregularity,0.0f,2.0f);
    if(amount<=0.0f) return 0.0f;
    float phase=variationPhase(p.refractiveSeed+1709u);
    float angle=p.refractiveRotation*(M_PI_F/180.0f);
    float s=sin(angle),c=cos(angle);
    float2 q=uv-.5f;
    float2 local=float2(c*q.x+s*q.y,-s*q.x+c*q.y);
    float anisotropy=clamp(p.refractiveAnisotropy,0.0f,1.0f);
    local.x*=mix(1.0f,.28f,anisotropy);
    float frequency=9.0f/clamp(p.refractiveScale,.25f,4.0f);
    float2 gradient=float2(
        sin(local.y*frequency+phase)+.52f*sin((local.x+local.y)*frequency*.63f-phase*.71f),
        cos(local.x*frequency-phase*.83f)+.47f*cos((local.x-local.y)*frequency*.71f+phase*1.19f));
    float radius=clamp(length(q)*2.0f,0.0f,1.5f);
    float edge=mix(1.0f,smoothstep(.18f,1.05f,radius),
                   clamp(p.refractiveEdgeBias,0.0f,1.0f));
    float2 imageGradient=float2(c*gradient.x-s*gradient.y,
                                s*gradient.x+c*gradient.y);
    return imageGradient*amount*edge*.0075f;
}

static float2 boundedPrismOffset(float2 uv,float2 offset) {
    // Fade only inside the small region where a displacement would otherwise
    // ask the shared sampler to clamp multiple output pixels to one border
    // pixel. The optical response remains unchanged through the usable frame
    // and arrives smoothly at zero at an unavailable source boundary.
    float availableX=offset.x>=0.0f?1.0f-uv.x:uv.x;
    float availableY=offset.y>=0.0f?1.0f-uv.y:uv.y;
    float fadeX=smoothstep(0.0f,max(abs(offset.x)*1.5f,.002f),availableX);
    float fadeY=smoothstep(0.0f,max(abs(offset.y)*1.5f,.002f),availableY);
    return offset*(fadeX*fadeY);
}

#if defined(LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF)
static float continuousFieldPSFEnvelope(float radius,
                                        constant LDBOpticsParameters& p) {
    float onset=clamp(p.responseFieldOnset,0.0f,1.5f);
    // Preserve a protected centre at exactly zero, but introduce a very soft
    // toe before the old hard onset so the result does not read as a cut-out
    // circle. Use almost the full normalized field for the remaining ramp;
    // only the furthest corners should reach the maximum footprint.
    float start=onset*0.35f;
    float end=min(1.5f,onset+max(clamp(p.responseFieldFalloff,0.0f,1.5f)*1.55f,
                                 0.08f));
    return smoothstep(start,max(end,start+0.08f),clamp(radius,0.0f,1.5f));
}
#endif

// A prism is a coherent displacement, not a noise field. Distribution chooses
// where the glass acts; Direction controls its physical refraction axis (or
// rotates the local direction in Radial Field mode). Dispersion is applied
// later around the green-channel base sample.
static float2 prismOffsetAt(float2 uv, constant LDBOpticsParameters& p) {
    float amount=clamp(p.prismAmount,0.0f,2.0f);
    if(amount<=0.0f)return 0.0f;
    float angle=p.prismDirection*(M_PI_F/180.0f);
    float2 axis=float2(cos(angle),sin(angle));

    if(p.prismDistribution==LDBPrismUniform)
        return boundedPrismOffset(uv,-axis*(amount*.035f));

    float2 field=uv-p.fieldCenter;
    float fieldAngle=p.fieldRotation*(M_PI_F/180.0f);
    float fs=sin(fieldAngle),fc=cos(fieldAngle);
    float2 local=float2(fc*field.x+fs*field.y,-fs*field.x+fc*field.y);
    float aspect=sqrt(clamp(p.fieldAspect,.25f,4.0f));
    float2 metric=float2(local.x*aspect,local.y/aspect);
    float radius=clamp(length(metric)*2.0f,0.0f,1.5f);
    float fieldOnset=clamp(p.responseFieldOnset,0.0f,1.5f);
    float fieldEnd=fieldOnset+max(clamp(p.responseFieldFalloff,0.0f,1.5f),.08f);
    float fieldEnvelope=smoothstep(fieldOnset,fieldEnd,radius);

    if(p.prismDistribution==LDBPrismBilateral) {
        float side=local.x<0.0f?-1.0f:1.0f;
        float axisRadius=clamp(abs(metric.x)*2.0f,0.0f,1.5f);
        float envelope=smoothstep(fieldOnset,fieldEnd,axisRadius);
        return boundedPrismOffset(uv,-axis*(side*amount*envelope*.035f));
    }
    if(p.prismDistribution==LDBPrismRadialField) {
        float2 localRadial=normalize(float2(local.x*aspect*aspect,
                                             local.y/(aspect*aspect))
                                      +float2(1e-6f,0.0f));
        float2 radial=float2(fc*localRadial.x-fs*localRadial.y,
                             fs*localRadial.x+fc*localRadial.y);
        float rs=sin(angle),rc=cos(angle);
        float2 rotated=float2(rc*radial.x-rs*radial.y,
                              rs*radial.x+rc*radial.y);
        return boundedPrismOffset(uv,-rotated*(amount*fieldEnvelope*.035f));
    }
    if(p.prismDistribution==LDBPrismInverseField)
        return boundedPrismOffset(uv,-axis*(amount*(1.0f-fieldEnvelope)*.035f));

    // Linear Edge is the released v16 response and remains the default for
    // old presets and projects.
    float edgeCoordinate=clamp(dot(uv-p.fieldCenter,axis)+.5f,0.0f,1.0f);
    float onset=clamp(p.prismEdgeBias,0.0f,.98f);
    float end=min(onset+max(p.prismSoftness,.01f),1.0f);
    float envelope=smoothstep(onset,max(end,onset+.005f),edgeCoordinate);
    // Sample back into the available frame from the selected glass edge.
    // Sampling outward would clamp to one border pixel and turn it into an
    // artificial solid streak at strong settings.
    return -axis*(amount*envelope*.035f);
}

static float2 distortCoordinate(float2 uv, constant LDBOpticsParameters& p,
                                thread float2& refractiveOffset) {
#if defined(LDB_EXPERIMENT_WIDE_PROJECTION) || defined(LDB_ENABLE_PROJECTION)
    // Experiment-only inverse projection. The reserved parameters are inert in
    // released builds: V4_3 is blend, V4_4 selects the ideal model (1..4),
    // V4_5 is the shared half-diagonal field angle in degrees, and V4_7 blends
    // from full-frame preservation to centre-scale preservation. Normalising
    // all models at the same angle makes their density behaviour comparable.
    float projectionBlend=clamp(p.reservedV4_3,0.0f,1.0f);
    int projectionModel=int(round(p.reservedV4_4));
    if(projectionBlend>1e-6f&&projectionModel>=1&&projectionModel<=4
#if defined(LDB_EXPERIMENT_PROJECTION_ANGLE_LIMITS) || defined(LDB_ENABLE_PROJECTION)
       &&p.reservedV4_5>0.0f
#endif
       ) {
        float aspect=max(p.imageSize.x/max(p.imageSize.y,1.0f),1e-4f);
        float2 projectionQ=(uv-p.opticalCenter)*float2(aspect,1.0f);
        float diagonalRadius=.5f*length(float2(aspect,1.0f));
        float outputRadius=length(projectionQ);
        float normalizedRadius=outputRadius/max(diagonalRadius,1e-5f);
#if defined(LDB_EXPERIMENT_PROJECTION_ANGLE_LIMITS) || defined(LDB_ENABLE_PROJECTION)
        // Separate limits experiment: preserve the completed 35..82 degree pass.
        float maxAngle=clamp(p.reservedV4_5,0.0f,89.0f)*(M_PI_F/180.0f);
#else
        float maxAngle=clamp(p.reservedV4_5,35.0f,82.0f)*(M_PI_F/180.0f);
#endif
        float theta=0.0f;
        float projectionRadiusAtMax=maxAngle;
        if(projectionModel==1) { // equidistant: r=f*theta
            theta=normalizedRadius*maxAngle;
        } else if(projectionModel==2) { // equisolid angle: r=2f*sin(theta/2)
            projectionRadiusAtMax=2.0f*sin(maxAngle*.5f);
            theta=2.0f*asin(clamp(normalizedRadius*projectionRadiusAtMax*.5f,
                                  0.0f,.9999f));
        } else if(projectionModel==3) { // stereographic: r=2f*tan(theta/2)
            projectionRadiusAtMax=2.0f*tan(maxAngle*.5f);
            theta=2.0f*atan(normalizedRadius*projectionRadiusAtMax*.5f);
        } else { // orthographic: r=f*sin(theta)
            projectionRadiusAtMax=sin(maxAngle);
            theta=asin(clamp(normalizedRadius*projectionRadiusAtMax,0.0f,.9999f));
        }
        bool boundarySafe=p.reservedV4_7>1.5f;
        float framing=boundarySafe?1.0f:clamp(p.reservedV4_7,0.0f,1.0f);
        // Every ideal projection has unit slope at the optical axis, but its
        // radius at the common field angle differs. Using that model-specific
        // radius is what genuinely preserves centre scale. It also prevents
        // one model from appearing stronger merely because it inherited the
        // equidistant normalisation constant.
        float radialNormalization=mix(tan(maxAngle),projectionRadiusAtMax,framing);
#if defined(LDB_EXPERIMENT_PROJECTION_ANGLE_LIMITS) || defined(LDB_ENABLE_PROJECTION)
        // Zero angle has the identity limit. Test through 89 degrees without
        // the previous 88 degree cap hiding high-angle behavior.
        float perspectiveRadius=maxAngle<=1e-6f?normalizedRadius:
#if defined(LDB_PROJECTION_RESOLVE_CANDIDATE) || defined(LDB_ENABLE_PROJECTION)
            // A displaced optical axis can put a corner beyond the nominal
            // half-diagonal angle. Keep inverse perspective below its pole.
            tan(min(theta,89.9f*(M_PI_F/180.0f)))/max(radialNormalization,1e-12f);
#else
            tan(theta)/max(radialNormalization,1e-12f);
#endif
#else
        float perspectiveRadius=tan(min(theta,88.0f*(M_PI_F/180.0f)))/
                                max(radialNormalization,1e-5f);
#endif
        float radialScale=normalizedRadius>1e-6f?
            perspectiveRadius/normalizedRadius:1.0f;
        float2 projected=p.opticalCenter+
            projectionQ*radialScale/float2(aspect,1.0f);
        float2 candidate=mix(uv,projected,projectionBlend);
        if(boundarySafe) {
            // Preserve centre scale through most of the frame, then smoothly
            // reduce only the final displacement as it approaches unavailable
            // source pixels. This avoids clamped streaks without imposing the
            // global magnification of full-frame fitting.
            float2 delta=candidate-uv;
            float safeT=1.0f;
            if(delta.x>1e-7f)safeT=min(safeT,(.998f-uv.x)/delta.x);
            if(delta.x<-1e-7f)safeT=min(safeT,(uv.x-.002f)/(-delta.x));
            if(delta.y>1e-7f)safeT=min(safeT,(.998f-uv.y)/delta.y);
            if(delta.y<-1e-7f)safeT=min(safeT,(uv.y-.002f)/(-delta.y));
            safeT=clamp(safeT,0.0f,1.0f);
            float nearestEdge=min(min(candidate.x,1.0f-candidate.x),
                                  min(candidate.y,1.0f-candidate.y));
            float boundaryInfluence=1.0f-smoothstep(-.01f,.08f,nearestEdge);
            float taperedLimit=safeT*(.94f+.06f*safeT);
            candidate=uv+delta*mix(1.0f,taperedLimit,boundaryInfluence);
        }
        uv=candidate;
    }
#endif
    float2 originalQ = uv - p.opticalCenter;
    float2 q = originalQ;
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

    // Unlike the legacy polynomial mapping, these terms can preserve a clean
    // central region and build smoothly only at the optical perimeter. The
    // geometry envelope follows the independently shaped Field controls.
    float2 shaped = uv - p.fieldCenter;
    float angle = p.fieldRotation * (M_PI_F / 180.0f);
    float fs = sin(angle), fc = cos(angle);
    float2 local = float2(fc * shaped.x + fs * shaped.y,
                         -fs * shaped.x + fc * shaped.y);
    float aspect = sqrt(clamp(p.fieldAspect, .25f, 4.0f));
    float fieldRadius = clamp(length(float2(local.x * aspect,
                                            local.y / aspect)) * 2.0f,
                              0.0f, 1.5f);
    float onset = clamp(p.responseFieldOnset, 0.0f, 1.5f);
    float fieldEnd = onset + max(clamp(p.responseFieldFalloff, 0.0f, 1.5f),
                                 0.08f);
    float envelope = smoothstep(onset, fieldEnd, fieldRadius);
    float geometryGate = mix(1.0f, envelope,
                             clamp(p.geometryFieldAmount, 0.0f, 1.0f));

    float2 mapped = originalQ + (q - originalQ) * geometryGate;
    float radialPower = envelope * envelope * (0.35f + 0.65f * fieldRadius);
    mapped *= 1.0f + clamp(p.peripheralStretch, -2.0f, 2.0f)
                     * radialPower * 0.34f;

    float edgeWarp = clamp(p.peripheralWarp, -2.0f, 2.0f);
    if (edgeWarp != 0.0f && fieldRadius > 1e-5f) {
        float theta = atan2(local.y, local.x);
        // Low angular harmonics approximate decentered, stressed or imperfect
        // front groups without introducing high-frequency ripples.
        float radialLobe = sin(theta * 2.0f + .73f)
                         + .46f * sin(theta * 3.0f - 1.17f);
        float tangentLobe = cos(theta * 2.0f - .31f)
                          - .38f * cos(theta * 3.0f + .82f);
        float2 localRadial = normalize(local + float2(1e-6f, 0.0f));
        float2 localTangent = float2(-localRadial.y, localRadial.x);
        float2 localOffset = (localRadial * radialLobe
                            + localTangent * tangentLobe * .55f)
                           * edgeWarp * radialPower * .018f;
        float2 imageOffset = float2(fc * localOffset.x - fs * localOffset.y,
                                    fs * localOffset.x + fc * localOffset.y);
        mapped += imageOffset;
    }
    refractiveOffset=refractiveOffsetAt(uv,p);
    return mapped + p.opticalCenter + refractiveOffset + prismOffsetAt(uv,p);
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

static float3 frontElementPattern(float2 uv, constant LDBOpticsParameters& p) {
    float phase = variationPhase(p.damageSeed + 101u);
    float angle = p.scratchDirection * (M_PI_F / 180.0f);
    float s = sin(angle), c = cos(angle);
    float2 q = uv - .5f;
    float2 r = float2(c * q.x + s * q.y, -s * q.x + c * q.y);
    float scale = clamp(p.damageScale, .25f, 4.0f);

    // Repeated wiping produces broad arcs plus many fine, nearly parallel
    // micro-marks. Sparse gating prevents a synthetic ruled-line overlay.
    float arcA = abs(length(q - float2(.18f*cos(phase), .15f*sin(phase)))
                   - (.28f + .05f*sin(phase*1.7f)));
    float arcB = abs(length(q + float2(.14f*sin(phase), .20f*cos(phase)))
                   - (.43f + .04f*cos(phase*1.3f)));
    float arcs = 1.0f-smoothstep(.0015f*scale,.010f*scale,min(arcA,arcB));
    float fineDistance = abs(fract((r.y + sin(r.x*19.0f+phase)*.006f)
                                   * (72.0f/scale)+phase)-.5f);
    float segment = .5f+.5f*sin(r.x*(31.0f/scale)+phase*2.3f);
    float fine = smoothstep(.455f,.497f,fineDistance)
               * smoothstep(.72f,.94f,segment);

    // A few deeper scratches have unequal spacing and limited length.
    float deepA = 1.0f-smoothstep(.00055f,.0022f,
        abs(r.y-.12f*sin(phase)-r.x*.035f));
    deepA *= smoothstep(.36f,.47f,.5f-abs(r.x+.08f*cos(phase)));
    float deepB = 1.0f-smoothstep(.00045f,.0019f,
        abs(r.y+.19f*cos(phase)+r.x*.08f));
    deepB *= smoothstep(.20f,.38f,.42f-abs(r.x-.13f*sin(phase)));
    return float3(clamp(arcs+fine*.55f,0.0f,1.0f),
                  clamp(max(deepA,deepB),0.0f,1.0f), 0.0f);
}

static float coatingWearPattern(float2 uv, constant LDBOpticsParameters& p) {
    float phase=variationPhase(p.damageSeed+911u);
    float scale=clamp(p.coatingWearScale,.25f,4.0f);
    float2 q=(uv-.5f)*(2.2f/scale);
    float broad=sin(q.x*3.1f+phase)+sin(q.y*2.7f-phase*.63f)
               +.65f*sin((q.x+q.y)*4.3f+phase*1.4f);
    float mottling=.5f+.5f*sin(q.x*5.7f-q.y*4.9f+phase*.8f);
    return smoothstep(.08f,1.32f,broad+mottling*.32f);
}

kernel void ldbOpticsMain(device const float4* source [[buffer(0)]],
                          device float4* direct [[buffer(1)]],
                          constant LDBOpticsParameters& p [[buffer(2)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(p.imageSize.x), height = uint(p.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;

    float2 uv = (float2(gid) + 0.5f) / p.imageSize;
    float2 refractiveOffset=0.0f;
    float2 warped = distortCoordinate(uv, p, refractiveOffset);
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
    float fieldOnset=clamp(p.responseFieldOnset,0.0f,1.5f);
    float fieldEnd=fieldOnset+max(clamp(p.responseFieldFalloff,0.0f,1.5f),0.08f);
    float fieldEnvelope = smoothstep(fieldOnset,fieldEnd,clamp(radius,0.0f,1.5f));
    float establishedFieldEnvelope=smoothstep(0.0f,1.0f,clamp(radius,0.0f,1.5f));
    float fieldResponseScale=establishedFieldEnvelope>1e-6f
        ?clamp(fieldEnvelope/establishedFieldEnvelope,0.0f,4.0f):0.0f;
    float chromaticEnvelope=fieldEnvelope;
    if (p.chromaticFieldOnset >= 0.0f) {
        float onset=clamp(p.chromaticFieldOnset,0.0f,1.5f);
        float end=onset+max(clamp(p.chromaticFieldFalloff,0.0f,1.5f),0.08f);
        chromaticEnvelope=smoothstep(onset,end,clamp(radius,0.0f,1.5f));
    }
    float chromaticResponseScale=establishedFieldEnvelope>1e-6f
        ?clamp(chromaticEnvelope/establishedFieldEnvelope,0.0f,4.0f):0.0f;
    float caR = p.lateralCARed * opticalRadius * opticalRadius * chromaticResponseScale;
    float caB = p.lateralCABlue * opticalRadius * opticalRadius * chromaticResponseScale;
    float2 pixelScale = p.imageSize;
    float4 center = sampleBilinear(source, basePixel, width, height);
    float2 redOffset=opticalRadial*caR*pixelScale*.002f;
    float2 blueOffset=opticalRadial*caB*pixelScale*.002f;
    float irregularDispersion=clamp(p.refractiveDispersion,0.0f,2.0f);
    redOffset+=refractiveOffset*pixelScale*irregularDispersion*.055f*chromaticEnvelope;
    blueOffset-=refractiveOffset*pixelScale*irregularDispersion*.075f*chromaticEnvelope;
    float2 prismOffset=prismOffsetAt(uv,p);
    float prismDispersion=clamp(p.prismDispersion,0.0f,2.0f);
    redOffset+=prismOffset*pixelScale*prismDispersion*.16f;
    blueOffset-=prismOffset*pixelScale*prismDispersion*.22f;
    if(variation>0.0f&&p.variationChromaticAsymmetry!=0.0f) {
        float2 variationAxis=float2(cos(phase),sin(phase));
        float signedField=dot(opticalField,variationAxis)*2.0f;
        float shift=clamp(p.variationChromaticAsymmetry,-2.0f,2.0f)
                   *variation*signedField*opticalRadius*p.imageSize.x*.0012f
                   *chromaticEnvelope;
        redOffset+=variationAxis*shift;
        blueOffset-=variationAxis*shift;
    }
    if (p.anamorphicAberration != 0.0f) {
        float amount = clamp(p.anamorphicAberration, -2.0f, 2.0f)
                     * opticalRadius * opticalRadius * chromaticResponseScale;
        float horizontalPixels = amount * p.imageSize.x * .0015f;
        redOffset+=float2(horizontalPixels,0.0f);
        blueOffset-=float2(horizontalPixels,0.0f);
    }

    // These are normalized perceptual controls. Each must remain independently
    // visible; earlier versions merely modulated an existing field blur by 1–2%,
    // making all three appear broken unless another control was already active.
    // Falloff is a width, not a second absolute radius. The previous endpoint
    // interpretation collapsed to a near-step whenever Falloff <= Onset,
    // producing a visible ring. Retain a small perceptual feather at zero.
    // Corner loss and curvature predate the configurable envelope and were
    // expressed directly in powers of radius. Scale those established curves
    // relative to their original smoothstep(0,1) envelope so the defaults are
    // unchanged while custom onset/falloff values affect every field family.
    float hostPixelScale=max(p.renderPixelScale,0.0001f);
    float curvatureBlur = clamp(p.fieldCurvature, 0.0f, 2.0f) * radius * radius * radius * radius * 2.4f*hostPixelScale;
    float fieldBlur = max(0.0f, clamp(p.cornerSharpnessLoss, 0.0f, 2.0f) * radius * radius * 2.4f*hostPixelScale + curvatureBlur);
    fieldBlur*=fieldResponseScale;
    float astigmatism = clamp(p.astigmatism, -2.0f, 2.0f);
    float radialSmear = clamp(p.radialSmear, 0.0f, 2.0f);
    float tangentSmear = clamp(p.tangentialSmear, 0.0f, 2.0f);
    float radialCharacter = (max(astigmatism, 0.0f) * 3.5f + radialSmear * 4.5f)*hostPixelScale;
    float tangentCharacter = (max(-astigmatism, 0.0f) * 3.5f + tangentSmear * 4.5f)*hostPixelScale;
    float radialWidth = fieldBlur + fieldEnvelope * radialCharacter;
    float tangentWidth = fieldBlur + fieldEnvelope * tangentCharacter;
    float characterMix = fieldEnvelope * (abs(astigmatism) * 0.60f
                       + radialSmear * 0.45f + tangentSmear * 0.45f);
    float focusBlur=fieldBlur;
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
    if(!(p.processingFlags & (1u<<30)))focusBlur/=hostPixelScale; // Preserve normalized strength; only footprint scales.
#endif
    float focusMix = clamp(focusBlur * 0.32f + characterMix, 0.0f, 1.0f);
    float4 optical;
#if defined(LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF)
    // Experimental A/B path: radialWidth and tangentWidth already collapse to
    // zero through the field envelope, at which point smoothAxisBlur returns
    // the centre sample. Match the old mixture's second moment by scaling the
    // footprint without retaining a registered sharp image underneath it.
    // The first candidate matched only the mixture's mathematical variance;
    // without the old sharp core that looked substantially stronger. Calibrate
    // perceptual size downward and extend the spatial transition so established
    // preset values remain useful rather than immediately reaching maximum blur.
    float continuousEnvelope=continuousFieldPSFEnvelope(radius,p);
    float envelopeScale=continuousEnvelope/max(fieldEnvelope,0.001f);
    float continuousScale=0.70f*envelopeScale*pow(focusMix,0.90f);
    float4 radialBlur=smoothAxisBlur(source,basePixel,radial,
                                     radialWidth*continuousScale,width,height);
    float4 tangentBlur=smoothAxisBlur(source,basePixel,tangent,
                                      tangentWidth*continuousScale,width,height);
    optical=(radialBlur+tangentBlur)*0.5f;
#else
    float4 radialBlur=smoothAxisBlur(source,basePixel,radial,radialWidth,width,height);
    float4 tangentBlur=smoothAxisBlur(source,basePixel,tangent,tangentWidth,width,height);
    optical=mix(center,(radialBlur+tangentBlur)*0.5f,focusMix);
#endif

    // A compact isotropic low-pass isolates focus-transition chroma. In the
    // default depth-free mode the image transition selects the tint, preserving
    // the approved approximation. With external depth, distance from the focus
    // plane supplies both near/far selection and defocus strength.
    float axialStrength = clamp(p.longitudinalCA, 0.0f, 2.0f);
    if (axialStrength > 0.0f) {
        float axialRadius = clamp(p.longitudinalCARadius, 0.5f
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
 *((p.processingFlags & (1u<<30))?1.0f:hostPixelScale)
#endif
 , 12.0f
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
 *((p.processingFlags & (1u<<30))?1.0f:hostPixelScale)
#endif
 );
        float innerRadius = max(0.5f
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
 *((p.processingFlags & (1u<<30))?1.0f:hostPixelScale)
#endif
 , axialRadius * 0.42f);
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
        float scale = clamp(p.detailScale, 0.25f
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
 *((p.processingFlags & (1u<<30))?1.0f:hostPixelScale)
#endif
 , 8.0f
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
 *((p.processingFlags & (1u<<30))?1.0f:hostPixelScale)
#endif
 );
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
        // Enhancement belongs before the field/pupil loss in the conceptual
        // optical chain. This compact single-pass approximation evaluates it
        // here, so taper only the positive (sharpening) side by the amount of
        // defocus already reconstructed. Negative detail controls remain fully
        // active and can continue to remove texture from a defocused image.
        // Positive transfer is an upstream lens-MTF characteristic. In this
        // fused approximation its source-derived bands are evaluated after
        // field reconstruction, so attenuate them by the *remaining* MTF
        // twice: once for contrast surviving the optical loss and once for
        // the ability of that surviving contrast to carry enhancement. This
        // prevents a strong defocus from being sharpened back into texture.
        float focusPreservation=(1.0f-focusMix)*(1.0f-focusMix);
        float fineControl=min(p.fineDetail,0.0f)
                         +max(p.fineDetail,0.0f)*focusPreservation;
        float microControl=min(p.microContrast,0.0f)
                          +max(p.microContrast,0.0f)*focusPreservation;
        float sagittalControl=min(p.sagittalDetail,0.0f)
                              +max(p.sagittalDetail,0.0f)*focusPreservation;
        float tangentialControl=min(p.tangentialDetail,0.0f)
                                +max(p.tangentialDetail,0.0f)*focusPreservation;
        float3 transfer = fineBand * fineControl * 0.35f
                        + mediumBand * microControl * 0.28f;
        transfer += fieldWeight * (radialBand * sagittalControl
                                  + tangentBand * tangentialControl) * 0.35f;
        transfer -= edgeLoss * (fineBand * 0.45f + mediumBand * 0.25f);
        float transferActivity=abs(fineControl)+abs(microControl)
                              +abs(sagittalControl)+abs(tangentialControl)
                              +abs(edgeLoss);
        if(transferActivity>1e-7f) {
            float3 localMin = min(center.rgb, min(fineBase.rgb, outerBase.rgb));
            float3 localMax = max(center.rgb, max(fineBase.rgb, outerBase.rgb));
            float3 allowance = (localMax - localMin) * 0.08f + 1e-5f;
            optical.rgb = clamp(optical.rgb + transfer,
                                localMin - allowance,localMax + allowance);
        }
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
            float distance=comaStrength*12.0f*hostPixelScale*t;
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
    float haze=clamp(p.frontHaze,0.0f,2.0f);
    float marks=clamp(p.cleaningMarks,0.0f,2.0f);
    float scratches=clamp(p.scratchAmount,0.0f,2.0f);
    float coating=clamp(p.coatingWear,0.0f,2.0f);
    if(haze>0.0f||marks>0.0f||scratches>0.0f||coating>0.0f) {
        float3 pattern=frontElementPattern(uv,p);
        float wear=coatingWearPattern(uv,p);
        // Spatial wear masks alter transmission here. Their illumination-driven
        // scatter is composited later from the smooth separable scatter graph;
        // direct sparse taps made their sampling lattice visible around points.
        // Marks primarily remove a small amount of local transmission. Keep
        // the ceiling low enough to avoid drawn-on dark lines, but high enough
        // for the 0..1 range to remain useful before highlight scatter reveals
        // the residue more strongly in the composite stage.
        // Wiping residue must remain visible in ordinary midtones, while deep
        // scratches interrupt transmission more decisively along their narrow
        // paths. The masks stay deterministic and spatially sparse, so these
        // stronger per-mark responses do not become a global density change.
        optical.rgb*=1.0f-clamp(pattern.x*marks*.045f+pattern.y*scratches*.035f,
                                0.0f,.14f);
        if(coating>0.0f) {
            float coatingMask=wear*coating;
            float3 wornTint=float3(1.09f,.975f,.84f);
            optical.rgb*=mix(float3(1.0f),wornTint,clamp(coatingMask*.68f,0.0f,.85f));
        }
    }
    float internalDirt=clamp(p.internalDirtAmount,0.0f,10.0f);
    float imageAspect=p.imageSize.x/max(p.imageSize.y,1.0f);
    if(internalDirt>0.0f) {
        float mask=internalContaminationPattern(
            uv,p.internalDirtScale,p.internalDirtSmear,internalDirt,
            p.internalDirtSoftness,p.internalDirtComplexity,
            p.internalDirtSeed,imageAspect);
        if(mask>0.0f) {
            // Preserve the established 0..2 response exactly. Above 2, add a
            // smooth creative extension that approaches full attenuation
            // without permitting negative transmission.
            float naturalAmount=min(internalDirt,2.0f);
            float naturalLoss=mask*naturalAmount*.14f;
            float extendedAmount=max(internalDirt-2.0f,0.0f);
            float extendedLoss=(1.0f-naturalLoss)
                *(1.0f-exp(-mask*extendedAmount*.38f));
            // Only density belongs in the direct optical stage. Highlight
            // redistribution is composited later from the smooth separable
            // scatter graph; sampling a wide kernel here exposed its lattice.
            // Density must remain independently useful when illumination
            // scatter is disabled. The former 2.2% coefficient made Cloud
            // Softness and Complexity effectively invisible unless users also
            // enabled scatter, which then obscured the controls with highlight
            // diffusion. Keep this as smooth transmission attenuation, with a
            // numerical ceiling that can approach opaque dirt creatively but
            // cannot cross through zero transmission.
            optical.rgb*=1.0f-clamp(naturalLoss+extendedLoss,0.0f,.98f);
        }
    }
    uint index = gid.y * width + gid.x;
    // RGB has already been geometrically mapped, so its packed depth carrier
    // must follow the same coordinate. Keeping source[index].a here made
    // depth-aware aperture and scatter compare warped colour against an
    // unwarped depth map near strong distortion and peripheral warps.
    direct[index] = float4(optical.rgb, center.a);
}

// Wavelength-dependent PSF approximation. Geometry and field
// softness are reconstructed first. Lateral dispersion then shifts the centre
// of each already-softened colour-channel PSF. This is the inexpensive local,
// space-variant equivalent of convolving with separate R/G/B kernels and
// avoids adding sharp zero/half/full-offset copies after optical blur.
kernel void ldbChromaticPSF(
    device const float4* achromatic [[buffer(0)]],
    device float4* output [[buffer(1)]],
    constant LDBOpticsParameters& p [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]) {
    uint width=uint(p.imageSize.x),height=uint(p.imageSize.y);
    if(gid.x>=width||gid.y>=height)return;
    uint index=gid.y*width+gid.x;
    float2 uv=(float2(gid)+.5f)/p.imageSize;
    float2 opticalField=uv-p.opticalCenter;
    float fieldAspect=sqrt(max(p.anamorphicSqueeze,.001f));
    float opticalRadius=clamp(length(float2(opticalField.x*fieldAspect,
                                             opticalField.y))*2.0f,0.0f,1.5f);
    float2 opticalRadial=normalize(float2(opticalField.x*fieldAspect*fieldAspect,
                                          opticalField.y)+float2(1e-6f,0.0f));
    float fieldOnset=clamp(p.responseFieldOnset,0.0f,1.5f);
    float fieldEnd=fieldOnset+max(clamp(p.responseFieldFalloff,0.0f,1.5f),.08f);
    float established=smoothstep(0.0f,1.0f,opticalRadius);
    float chromaticEnvelope=smoothstep(fieldOnset,fieldEnd,opticalRadius);
    if(p.chromaticFieldOnset>=0.0f){
        float onset=clamp(p.chromaticFieldOnset,0.0f,1.5f);
        float end=onset+max(clamp(p.chromaticFieldFalloff,0.0f,1.5f),.08f);
        chromaticEnvelope=smoothstep(onset,end,opticalRadius);
    }
    float response=established>1e-6f
        ?clamp(chromaticEnvelope/established,0.0f,4.0f):0.0f;
    float2 redOffset=opticalRadial*p.lateralCARed*opticalRadius*opticalRadius
                    *response*p.imageSize*.002f;
    float2 blueOffset=opticalRadial*p.lateralCABlue*opticalRadius*opticalRadius
                     *response*p.imageSize*.002f;
    float2 refractive=refractiveOffsetAt(uv,p)*p.imageSize
                     *clamp(p.refractiveDispersion,0.0f,2.0f)*chromaticEnvelope;
    redOffset+=refractive*.055f;
    blueOffset-=refractive*.075f;
    float2 prism=prismOffsetAt(uv,p)*p.imageSize*clamp(p.prismDispersion,0.0f,2.0f);
    redOffset+=prism*.16f;
    blueOffset-=prism*.22f;
    float variation=clamp(p.variationAmount,0.0f,1.0f);
    if(variation>0.0f&&p.variationChromaticAsymmetry!=0.0f){
        float phase=variationPhase(p.variationSeed);
        float2 axis=float2(cos(phase),sin(phase));
        float signedField=dot(opticalField,axis)*2.0f;
        float shift=clamp(p.variationChromaticAsymmetry,-2.0f,2.0f)*variation
                   *signedField*opticalRadius*p.imageSize.x*.0012f*chromaticEnvelope;
        redOffset+=axis*shift;
        blueOffset-=axis*shift;
    }
    if(p.anamorphicAberration!=0.0f){
        float shift=clamp(p.anamorphicAberration,-2.0f,2.0f)*opticalRadius
                   *opticalRadius*response*p.imageSize.x*.0015f;
        redOffset.x+=shift;
        blueOffset.x-=shift;
    }

    float2 pixel=float2(gid);
    float4 center=achromatic[index];
    // Three bilinear reads are the common path. Only offsets wider than two
    // pixels receive a compact three-point spectral footprint, centred on the
    // displaced PSF rather than spanning back to the undispersed image.
    float red=sampleBilinear(achromatic,pixel+redOffset,width,height).r;
    float blue=sampleBilinear(achromatic,pixel+blueOffset,width,height).b;
    float redLength=length(redOffset),blueLength=length(blueOffset);
    if(redLength>2.0f){
        float2 band=redOffset/redLength*min(redLength*.18f,1.5f);
        red=sampleBilinear(achromatic,pixel+redOffset,width,height).r*.5f
           +(sampleBilinear(achromatic,pixel+redOffset-band,width,height).r
            +sampleBilinear(achromatic,pixel+redOffset+band,width,height).r)*.25f;
    }
    if(blueLength>2.0f){
        float2 band=blueOffset/blueLength*min(blueLength*.18f,1.5f);
        blue=sampleBilinear(achromatic,pixel+blueOffset,width,height).b*.5f
            +(sampleBilinear(achromatic,pixel+blueOffset-band,width,height).b
             +sampleBilinear(achromatic,pixel+blueOffset+band,width,height).b)*.25f;
    }
    output[index]=float4(red,center.g,blue,center.a);
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
        // Fade the finite kernel to zero before its square support boundary.
        // Without this taper, compact highlights reveal the separable cutoff
        // as a rounded rectangle even though the inner Gaussian is circular.
        weight*=1.0f-smoothstep(.72f,1.0f,abs(normalizedOffset));
        result += sampleBilinear(image, pixel + axis * radius * normalizedOffset,
                                 width, height) * weight;
        weightSum += weight;
    }
    return result / weightSum;
}

// Veiling glare needs a genuinely Gaussian tail. The ordinary bounded kernel
// stops at one nominal radius, where its Gaussian still carries visible
// energy; two separable passes therefore reveal a square support boundary.
// Extend glare to 1.5 radii, where the tail is effectively black, while still
// operating on the reduced scatter buffer.
static float4 blurLineGlare(device const float4* image,float2 pixel,float2 axis,
                            float radius,uint width,uint height) {
    if(radius<=.001f)return sampleBilinear(image,pixel,width,height);
    float4 result=0.0f;
    float weightSum=0.0f;
    float sigma=max(radius*.45f,.55f);
    int support=clamp(int(ceil(radius*1.5f)),1,32);
    for(int tap=-32;tap<=32;++tap) {
        if(abs(tap)>support)continue;
        float weight=exp(-.5f*float(tap*tap)/(sigma*sigma));
        result+=sampleBilinear(image,pixel+axis*float(tap),width,height)*weight;
        weightSum+=weight;
    }
    return result/max(weightSum,1e-6f);
}

// Very long anamorphic streaks need near-continuous sampling. Keep the sample
// interval below roughly 1.5 reduced-buffer pixels so compact sources cannot
// resolve into the regularly spaced vertical cuts produced by sparse taps.
// This path runs only on the reduced-resolution flare buffer.
static float4 blurLineLongFlare(device const float4* image,float2 pixel,float2 axis,
                                float radius,uint width,uint height) {
    if(radius<=.001f)return sampleBilinear(image,pixel,width,height);
    float4 result=0.0f;
    float weightSum=0.0f;
    constexpr float sigma=.45f;
    int tapRadius=clamp(int(ceil(radius/1.35f)),64,192);
    for(int tap=-192;tap<=192;++tap) {
        if(abs(tap)>tapRadius)continue;
        float normalizedOffset=float(tap)/float(tapRadius);
        float weight=exp(-.5f*(normalizedOffset/sigma)*(normalizedOffset/sigma));
        result+=sampleBilinear(image,pixel+axis*radius*normalizedOffset,
                               width,height)*weight;
        weightSum+=weight;
    }
    return result/max(weightSum,1e-6f);
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
        weight*=1.0f-smoothstep(.72f,1.0f,abs(normalizedOffset));
        float4 sample=sampleBilinear(image,pixel+axis*radius*normalizedOffset,width,height);
        float sampleDepth=normalizedDepth(sampleNearest(image,
            pixel+axis*radius*normalizedOffset,width,height),p);
        weight*=scatterDepthAgreement(targetDepth,sampleDepth,p);
        result+=sample.rgb*weight;
        weightSum+=weight;
    }
    return float4(weightSum>1e-6f?result/weightSum:centre.rgb,centre.a);
}


static float4 blurLineGlareDepthAware(device const float4* image,float2 pixel,
                                      float2 axis,float radius,uint width,uint height,
                                      constant LDBOpticsParameters& p) {
    if(radius<=.001f)return sampleBilinear(image,pixel,width,height);
    float4 centre=sampleNearest(image,pixel,width,height);
    float targetDepth=normalizedDepth(centre,p);
    float3 result=0.0f;
    float weightSum=0.0f;
    float sigma=max(radius*.45f,.55f);
    int support=clamp(int(ceil(radius*1.5f)),1,32);
    for(int tap=-32;tap<=32;++tap) {
        if(abs(tap)>support)continue;
        float2 samplePixel=pixel+axis*float(tap);
        float4 sample=sampleBilinear(image,samplePixel,width,height);
        float weight=exp(-.5f*float(tap*tap)/(sigma*sigma));
        weight*=scatterDepthAgreement(targetDepth,
            normalizedDepth(sampleNearest(image,samplePixel,width,height),p),p);
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
        float aperturePixelScale=1.0f;
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
    aperturePixelScale=(p.processingFlags & (1u<<30))?1.0f:max(p.renderPixelScale,0.0001f);
#endif
    float reconstructionRadius=clamp(scatter.radiusX*0.16f,0.75f*aperturePixelScale,4.0f*aperturePixelScale);
#if defined(LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF)
        if(p.depthMode==0u) {
            float2 uv=(float2(gid)+0.5f)/scatter.imageSize;
            float2 field=uv-p.fieldCenter;
            float fieldAngle=p.fieldRotation*(M_PI_F/180.0f);
            float fs=sin(fieldAngle),fc=cos(fieldAngle);
            float2 local=float2(fc*field.x+fs*field.y,
                                -fs*field.x+fc*field.y);
            float aspect=sqrt(clamp(p.fieldAspect,0.25f,4.0f));
            float fieldRadius=clamp(length(float2(local.x*aspect,
                                                   local.y/aspect))*2.0f,
                                    0.0f,1.5f);
            float envelope=continuousFieldPSFEnvelope(fieldRadius,p);
            reconstructionRadius*=0.70f*pow(envelope,1.15f);
            if(reconstructionRadius<=.001f) {
                destination[gid.y*width+gid.x]=source[gid.y*width+gid.x];
                return;
            }
        }
#endif
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
        float referenceReconstructionRadius=reconstructionRadius/aperturePixelScale;
        float sigma=max(referenceReconstructionRadius*0.52f,0.55f);
        float4 smoothed=0.0f;
        float weightSum=0.0f;
        for(int tap=-4;tap<=4;++tap) {
            if(abs(float(tap))>referenceReconstructionRadius+0.5f) continue;
            float weight=exp(-0.5f*float(tap*tap)/(sigma*sigma));
            int2 offset=scatter.scale==1u?int2(tap,0):int2(0,tap);
            float4 tapSample;
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
            tapSample=sampleBilinear(source,float2(gid)+float2(offset)*aperturePixelScale,width,height);
#else
            tapSample=sampleInteger(source,int2(gid)+offset,width,height);
#endif
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
    // Bokeh orientation follows the independently positionable Field Shape,
    // not the distortion Optical Center. This lets a preset retain a clean
    // focus island while the pupil becomes increasingly tangential off axis.
    float2 field=uv-p.fieldCenter;
    float fieldAngle=p.fieldRotation*(M_PI_F/180.0f);
    float fs=sin(fieldAngle),fc=cos(fieldAngle);
    float2 localField=float2(fc*field.x+fs*field.y,
                            -fs*field.x+fc*field.y);
    float fieldAspect=sqrt(clamp(p.fieldAspect,0.25f,4.0f));
    float2 fieldMetric=float2(localField.x*fieldAspect,
                              localField.y/fieldAspect);
    float2 localRadial=normalize(float2(localField.x*fieldAspect*fieldAspect,
                                        localField.y/(fieldAspect*fieldAspect))
                                 +float2(1e-6f,0.0f));
    float2 radial=float2(fc*localRadial.x-fs*localRadial.y,
                         fs*localRadial.x+fc*localRadial.y);
    float2 tangent=float2(-radial.y,radial.x);
    float fieldRadius=clamp(length(fieldMetric)*2.0f,0.0f,1.5f);
    float onset=clamp(p.responseFieldOnset,0.0f,1.5f);
    float fieldEnd=onset+max(clamp(p.responseFieldFalloff,0.0f,1.5f),0.08f);
    float fieldEnvelope=smoothstep(onset,fieldEnd,fieldRadius);
#if defined(LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF)
    // In the experiment the pupil itself grows from a delta response at the
    // protected centre.  All three passes must converge to identity together;
    // otherwise the reconstruction passes leave a faint global soft layer.
    if(p.depthMode==0u&&fieldEnvelope<=0.0001f) {
        destination[gid.y*width+gid.x]=source[gid.y*width+gid.x];
        return;
    }
#endif
    float bokehSwirl=clamp(p.apertureBokehSwirl,0.0f,12.0f)*fieldEnvelope;
    float catEye=clamp(p.apertureCatEye,0.0f,1.0f)*smoothstep(0.15f,1.0f,fieldRadius);
    float pupilShift=clamp(p.aperturePupilShift,0.0f,1.0f)*fieldEnvelope;
    float pupilClip=clamp(p.aperturePupilClip,0.0f,1.0f)*fieldEnvelope;
    float rimWeight=clamp(p.apertureRimWeight,-1.0f,1.0f);
    float2 apertureX=normalize(float2(scatter.axisX,scatter.axisY)+float2(1e-6f,0.0f));
    float2 apertureY=float2(-apertureX.y,apertureX.x);
    float aperturePixelScale=1.0f;
#if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
    aperturePixelScale=(p.processingFlags & (1u<<30))?1.0f:max(p.renderPixelScale,0.0001f);
#endif
    float reconstructionRadius=clamp(scatter.radiusX*0.16f,0.75f*aperturePixelScale,4.0f*aperturePixelScale);
    float radius=max(scatter.radiusX-min(reconstructionRadius*0.65f,scatter.radiusX*0.15f),0.0f);
#if defined(LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF)
    if(p.depthMode==0u) {
        float continuousEnvelope=continuousFieldPSFEnvelope(fieldRadius,p);
        float continuousScale=0.70f*pow(continuousEnvelope,1.15f);
        reconstructionRadius*=continuousScale;
        radius*=continuousScale;
    }
#endif
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
    // Pupil aspect is an independent optical control.  Restricting it to the
    // Oval mode made it silently inert for polygonal pupils (including the
    // Petzval factory family), even though real squeezed pupils can retain a
    // bladed outline.  Circular remains circular at the neutral value of one.
    float aspect=sqrt(clamp(p.apertureAspect,0.25f,8.0f));
    uint blades=clamp(p.apertureBladeCount,3u,16u);
    float curvature=clamp(p.apertureBladeCurvature,0.0f,1.0f);
    // Optical Drift translates the centre of the pupil distribution as the
    // PSF grows. Because the translation is proportional to the already
    // field/depth-conditioned radius, focused regions remain exactly fixed.
    // Radial and Tangential reuse the shaped field orientation; Directed is a
    // global lens-space tilt selected by angle. The signed amount reverses the
    // corresponding direction without adding another mode or coordinate.
    float driftAmount=clamp(p.opticalDriftAmount,-1.0f,1.0f);
    float2 driftDirection=radial;
    float driftFieldWeight=smoothstep(.02f,.20f,fieldRadius);
    if(p.opticalDriftMode==LDBOpticalDriftTangential) {
        driftDirection=tangent;
    } else if(p.opticalDriftMode==LDBOpticalDriftDirected) {
        float driftAngle=p.opticalDriftAngle*(M_PI_F/180.0f);
        driftDirection=float2(cos(driftAngle),sin(driftAngle));
        driftFieldWeight=1.0f;
    }
    float2 opticalDrift=driftDirection*(driftAmount*radius*.80f*driftFieldWeight);
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
        float2 pupilRadial=float2(dot(radial,apertureX),dot(radial,apertureY));
        pupilRadial=normalize(pupilRadial+float2(1e-6f,0.0f));
        // Off-axis pupil images are displaced and clipped by the barrel. These
        // independent terms allow asymmetric cat-eye footprints instead of
        // reducing every lens to a centred ellipse.
        localPoint-=pupilRadial*(pupilShift*.62f);
        float clipCoordinate=dot(localPoint,pupilRadial);
        float clipLimit=mix(1.2f,-.08f,pupilClip);
        float clipFeather=mix(.018f,.10f,softness);
        float clipWeight=1.0f-smoothstep(clipLimit-clipFeather,
                                        clipLimit+clipFeather,clipCoordinate);
        float2 offset=(apertureX*localPoint.x+apertureY*localPoint.y)*radius;
        // Cat-eye deformation is a filled off-axis pupil compression. Keeping a
        // non-zero radial width prevents extreme settings from collapsing into arcs.
        float radialScale=mix(1.0f,0.58f,catEye);
        // Bokeh Swirl should read as a rotating off-axis pupil, not as a
        // vanishingly thin tangential streak. Preserve approximately the
        // established response around five while allowing the extended 0..12
        // range to progress instead of saturating almost completely by five.
        // The shallow quadratic taper keeps the maximum footprint bounded for
        // the 96-sample filled pupil.
        float swirlResponse=bokehSwirl*(0.22f-0.003f*bokehSwirl);
        radialScale*=1.0f/(1.0f+0.32f*swirlResponse);
        float tangentialScale=1.0f+0.72f*swirlResponse;
        float radialComponent=dot(offset,radial);
        float tangentialComponent=dot(offset,tangent);
        offset=radial*(radialComponent*radialScale)
              +tangent*(tangentialComponent*tangentialScale);
        // Redistribute energy across a deliberately broad pupil band.  The
        // earlier 0.62..1.48 profile largely disappeared after normalization,
        // so maximum positive Rim Weight still looked like a filled disk.  A
        // wider but smooth centre-to-edge ratio produces a readable bubble rim
        // without concentrating energy into a narrow sampled ring.
        float rimProfile=smoothstep(.16f,.94f,diskRadius);
        float positiveRimProfile=mix(.16f,2.75f,rimProfile);
        float negativeRimProfile=mix(2.20f,.24f,rimProfile);
        float edgeWeight=mix(1.0f,softProfile,softness)
                        *mix(1.0f,positiveRimProfile,max(rimWeight,0.0f))
                        *mix(1.0f,negativeRimProfile,max(-rimWeight,0.0f))
                        *clipWeight;
        float2 pupilPosition=float2(gid)+offset+opticalDrift;
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
    float3 peak = 0.0f;
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
            if(scatter.axisY>2.5f) {
                uint sourceWidth=uint(p.imageSize.x),sourceHeight=uint(p.imageSize.y);
                int peakRadius=max(int(scale)*2,3);
                float sourceLuma=dot(sourceSample.rgb,float3(.2126f,.7152f,.0722f));
                float surroundLuma=(
                    dot(sampleInteger(source,int2(sourcePosition)+int2(peakRadius,0),sourceWidth,sourceHeight).rgb,float3(.2126f,.7152f,.0722f))
                   +dot(sampleInteger(source,int2(sourcePosition)-int2(peakRadius,0),sourceWidth,sourceHeight).rgb,float3(.2126f,.7152f,.0722f))
                   +dot(sampleInteger(source,int2(sourcePosition)+int2(0,peakRadius),sourceWidth,sourceHeight).rgb,float3(.2126f,.7152f,.0722f))
                   +dot(sampleInteger(source,int2(sourcePosition)-int2(0,peakRadius),sourceWidth,sourceHeight).rgb,float3(.2126f,.7152f,.0722f)))*.25f;
                float compactGate=smoothstep(.05f,.32f,
                    max(sourceLuma-surroundLuma*.90f,0.0f)/max(sourceLuma,1e-5f));
                sourceWeight*=compactGate;
            }
            float3 eligible=thresholdHighlightResponse(sourceSample.rgb,scatter.threshold,
                                                        p.responseHighlightKnee)*sourceWeight;
            sum+=eligible;
            peak=max(peak,eligible);
        }
    }
    uint2 depthPosition=min(gid*scale+uint2(scale/2u),
        uint2(uint(p.imageSize.x)-1,uint(p.imageSize.y)-1));
    float depthCarrier=source[depthPosition.y*uint(p.imageSize.x)+depthPosition.x].a;
    float3 reduced=sum/float(scale*scale);
    // Glare is frequently driven by compact practicals. Pure cell averaging
    // divides a one-pixel source by as much as 64 before the blur and makes the
    // UI appear inert. A restrained peak-preserving reduction retains source
    // energy without turning the broad response into a hard point sprite.
    if(scatter.axisY>.5f&&scatter.axisY<1.5f)
        reduced=mix(reduced,peak,.35f);
    destination[gid.y * width + gid.x] = float4(reduced,depthCarrier);
}

kernel void ldbDetectFlareSources(
    device const float4* highlights [[buffer(0)]],
    device LDBFlareSource* sources [[buffer(1)]],
    constant LDBScatterParameters& scatter [[buffer(2)]],
    uint gid [[thread_position_in_grid]]) {
    if(gid!=0u)return;
    // Runtime flare shaping follows the dominant coherent lamp.  The previous
    // four-source search rescanned the reduced image four times on one GPU
    // lane and allowed rows of practicals to compete with the photographed
    // flare source.  A softly downsampled highlight covers multiple reduced
    // pixels, so a two-pixel search stride retains sub-cell stability while
    // cutting the serial reduction work to one eighth of that first version.
    constexpr uint maximumSources=1u;
    uint width=uint(scatter.imageSize.x),height=uint(scatter.imageSize.y);
    for(uint slot=0u;slot<maximumSources;++slot) {
        sources[slot].positionEnergyRadius=float4(0.0f);
        sources[slot].colorActive=float4(0.0f);
    }
    const float3 lumaWeights=float3(.2126f,.7152f,.0722f);
    float strongest=0.0f;
    for(uint slot=0u;slot<maximumSources;++slot) {
        float bestEnergy=0.0f;
        uint2 bestPosition=uint2(0u);
        float3 bestColor=0.0f;
        for(uint y=1u;y+2u<height;y+=2u) {
            for(uint x=1u;x+2u<width;x+=2u) {
                // Retain the faster cell-stride reduction without assuming
                // the highlight peak lands on one particular pixel parity.
                uint2 candidatePosition=uint2(x,y);
                float3 candidate=highlights[y*width+x].rgb;
                float cellEnergy=dot(candidate,lumaWeights);
                for(uint cellY=0u;cellY<2u;++cellY)
                    for(uint cellX=0u;cellX<2u;++cellX) {
                        uint2 position=uint2(x+cellX,y+cellY);
                        float3 cellCandidate=highlights[position.y*width+position.x].rgb;
                        float candidateEnergy=dot(cellCandidate,lumaWeights);
                        if(candidateEnergy>cellEnergy) {
                            candidatePosition=position;
                            candidate=cellCandidate;
                            cellEnergy=candidateEnergy;
                        }
                    }
                float energy=dot(candidate,lumaWeights);
                if(energy<=bestEnergy)continue;
                bool separated=true;
                for(uint previous=0u;previous<slot;++previous) {
                    float2 previousReduced=sources[previous].positionEnergyRadius.xy
                        /float(max(scatter.scale,1u));
                    if(distance(float2(candidatePosition)+.5f,previousReduced)<6.0f) {
                        separated=false;
                        break;
                    }
                }
                if(!separated)continue;
                bool localMaximum=true;
                for(int oy=-1;oy<=1&&localMaximum;++oy)
                    for(int ox=-1;ox<=1;++ox) {
                        if(ox==0&&oy==0)continue;
                        float neighbor=dot(highlights[uint(int(candidatePosition.y)+oy)*width
                            +uint(int(candidatePosition.x)+ox)].rgb,lumaWeights);
                        if(neighbor>energy) { localMaximum=false; break; }
                    }
                if(localMaximum) {
                    bestEnergy=energy;
                    bestPosition=candidatePosition;
                    bestColor=candidate;
                }
            }
        }
        if(slot==0u)strongest=bestEnergy;
        if(bestEnergy<=1e-6f||bestEnergy<max(strongest*.16f,1e-5f))break;
        float scale=float(max(scatter.scale,1u));
        sources[slot].positionEnergyRadius=float4(
            (float2(bestPosition)+.5f)*scale,bestEnergy,
            clamp(sqrt(bestEnergy)*2.0f,1.0f,12.0f));
        sources[slot].colorActive=float4(bestColor/max(bestEnergy,1e-5f),1.0f);
    }
}

kernel void ldbBlurHorizontal(device const float4* source [[buffer(0)]],
                              device float4* destination [[buffer(1)]],
                              constant LDBScatterParameters& scatter [[buffer(2)]],
                              constant LDBOpticsParameters& p [[buffer(3)]],
                              uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(scatter.imageSize.x), height = uint(scatter.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    bool depthAware=p.depthMode>0u&&scatter.axisX>.5f;
    bool glareKernel=scatter.axisY>.5f&&scatter.axisY<1.5f;
    int maximumTaps=scatterTapLimit(p);
    destination[gid.y*width+gid.x]=glareKernel
        ?(depthAware
            ?blurLineGlareDepthAware(source,float2(gid),float2(1,0),scatter.radiusX,width,height,p)
            :blurLineGlare(source,float2(gid),float2(1,0),scatter.radiusX,width,height))
        :depthAware
        ?blurLineDepthAware(source,float2(gid),float2(1,0),scatter.radiusX,width,height,p,maximumTaps)
        :((scatter.axisY>2.5f||scatter.radiusX>24.0f)
            ?blurLineLongFlare(source,float2(gid),float2(1,0),scatter.radiusX,width,height)
            :blurLine(source,float2(gid),float2(1,0),scatter.radiusX,width,height,maximumTaps));
}

kernel void ldbBlurVertical(device const float4* source [[buffer(0)]],
                            device float4* destination [[buffer(1)]],
                            constant LDBScatterParameters& scatter [[buffer(2)]],
                            constant LDBOpticsParameters& p [[buffer(3)]],
                            uint2 gid [[thread_position_in_grid]]) {
    uint width = uint(scatter.imageSize.x), height = uint(scatter.imageSize.y);
    if (gid.x >= width || gid.y >= height) return;
    bool depthAware=p.depthMode>0u&&scatter.axisX>.5f;
    bool glareKernel=scatter.axisY>.5f&&scatter.axisY<1.5f;
    int maximumTaps=scatterTapLimit(p);
    destination[gid.y*width+gid.x]=glareKernel
        ?(depthAware
            ?blurLineGlareDepthAware(source,float2(gid),float2(0,1),scatter.radiusY,width,height,p)
            :blurLineGlare(source,float2(gid),float2(0,1),scatter.radiusY,width,height))
        :depthAware
        ?blurLineDepthAware(source,float2(gid),float2(0,1),scatter.radiusY,width,height,p,maximumTaps)
        :(scatter.radiusY>24.0f
            ?blurLineLongFlare(source,float2(gid),float2(0,1),scatter.radiusY,width,height)
            :blurLine(source,float2(gid),float2(0,1),scatter.radiusY,width,height,maximumTaps));
}

kernel void ldbReconstructAnamorphicFlare(
    device const float4* highlightSource [[buffer(0)]],
    device const float4* broadScatter [[buffer(1)]],
    device float4* destination [[buffer(2)]],
    constant LDBOpticsParameters& p [[buffer(3)]],
    constant LDBScatterParameters& scatter [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]) {
    uint width=uint(scatter.imageSize.x),height=uint(scatter.imageSize.y);
    if(gid.x>=width||gid.y>=height)return;
    float2 pixel=float2(gid);

    // The established long-radius scatter supplies only the broad streak.
    // Integrate it continuously across both axes here so sparse blur taps do
    // not resolve as dots or parallel rails in the final image.
    float3 broad=0.0f;
    float broadWeight=0.0f;
    for(int y=-6;y<=6;++y) {
        float wy=exp(-.5f*float(y*y)/7.5f);
        for(int x=-2;x<=2;++x) {
            float wx=exp(-.5f*float(x*x)/1.4f);
            float w=wx*wy;
            broad+=sampleBilinear(broadScatter,pixel+float2(x,y),width,height).rgb*w;
            broadWeight+=w;
        }
    }
    broad/=max(broadWeight,1e-6f);
    float bandAmount=max(p.anamorphicFlareBandAmount,0.0f);
    if(bandAmount>1e-6f) {
        float spacing=max(p.anamorphicFlareBandSeparation,0.0f)
                    /float(max(scatter.scale,1u));
        float3 closeBands=
            sampleBilinear(broadScatter,pixel+float2(0, spacing*.42f),width,height).rgb+
            sampleBilinear(broadScatter,pixel-float2(0, spacing*.42f),width,height).rgb;
        float3 outerBands=
            sampleBilinear(broadScatter,pixel+float2(0, spacing),width,height).rgb+
            sampleBilinear(broadScatter,pixel-float2(0, spacing),width,height).rgb;
        broad+=bandAmount*(closeBands*.24f+outerBands*.13f);
    }
    float secondaryAmount=max(p.anamorphicFlareSecondaryAmount,0.0f);
    if(secondaryAmount>1e-6f) {
        float secondaryOffset=p.anamorphicFlareSecondaryOffset
                            /float(max(scatter.scale,1u));
        broad+=sampleBilinear(broadScatter,pixel-float2(0,secondaryOffset),width,height).rgb
              *secondaryAmount*.62f;
    }
    float asymmetry=clamp(p.anamorphicFlareAsymmetry,-1.0f,1.0f);
    if(abs(asymmetry)>1e-6f) {
        float offset=max(scatter.radiusX*.14f,1.0f)*sign(asymmetry);
        float3 tail=sampleBilinear(broadScatter,pixel+float2(offset,0),width,height).rgb;
        broad=mix(broad,tail,abs(asymmetry)*.62f);
    }

    // A compact source-derived core remains independent of the long streak.
    float3 core=0.0f;
    float coreWeight=0.0f;
    for(int x=-4;x<=4;++x) {
        float w=exp(-.5f*float(x*x)/3.2f);
        float2 corePosition=pixel+float2(x,0);
        float3 coreSample=sampleBilinear(highlightSource,corePosition,width,height).rgb;
        float coreLuma=dot(coreSample,float3(.2126f,.7152f,.0722f));
        float surroundLuma=(
            dot(sampleBilinear(highlightSource,corePosition+float2(3,0),width,height).rgb,float3(.2126f,.7152f,.0722f))
           +dot(sampleBilinear(highlightSource,corePosition-float2(3,0),width,height).rgb,float3(.2126f,.7152f,.0722f))
           +dot(sampleBilinear(highlightSource,corePosition+float2(0,3),width,height).rgb,float3(.2126f,.7152f,.0722f))
           +dot(sampleBilinear(highlightSource,corePosition-float2(0,3),width,height).rgb,float3(.2126f,.7152f,.0722f)))*.25f;
        float compactGate=smoothstep(.08f,.42f,
            max(coreLuma-surroundLuma*.88f,0.0f)/max(coreLuma,1e-5f));
        core+=coreSample*compactGate*w;
        coreWeight+=w;
    }
    core/=max(coreWeight,1e-6f);
    core=core/(float3(1.0f)+core*.22f);

    // Source-derived vertical diffraction rays remain independent of the
    // horizontal cylindrical streak. A normalized fixed-tap convolution keeps
    // the ray continuous while Ray Length controls its output-space extent.
    float3 verticalRay=0.0f;
    float verticalRayWeight=0.0f;
    // Shaped rays are now reconstructed analytically at full output
    // resolution. Keep the reduced buffer responsible only for broad energy.
    float rayAmount=0.0f;
    if(rayAmount>1e-6f) {
        float rayRadius=clamp(p.diffractionRayLength
                            /float(max(scatter.scale,1u)),1.0f,float(height)*.5f);
        // Long rays need a denser reconstruction than the compact flare core.
        // With only 65 taps, long output-space rays exposed individual sample
        // intervals as visible steps in smooth gradients. 129 normalized taps
        // keep the falloff continuous in the reduced flare buffer.
        constexpr int rayHalfSamples=64;
        for(int i=-rayHalfSamples;i<=rayHalfSamples;++i) {
            float normalizedOffset=float(i)/float(rayHalfSamples);
            float weight=exp(-abs(normalizedOffset)*5.2f);
            float2 rayPosition=pixel+float2(0.0f,normalizedOffset*rayRadius);
            if(rayPosition.y>=0.0f&&rayPosition.y<=float(height-1)) {
                float3 raySample=sampleBilinear(highlightSource,rayPosition,width,height).rgb;
                float rayLuma=dot(raySample,float3(.2126f,.7152f,.0722f));
                // Diffraction is driven by the compact source, not its broad
                // photographic halo. This prevents a bright lamp from turning
                // into a constant-width vertical light column.
                float compactRayGate=smoothstep(.08f,.72f,rayLuma);
                verticalRay+=raySample*compactRayGate*weight;
                verticalRayWeight+=weight;
            }
        }
        verticalRay/=max(verticalRayWeight,1e-6f);
        verticalRay=verticalRay/(float3(1.0f)+verticalRay*.18f);
    }

    // Reproject the unblurred highlight field around Optical Center and use a
    // filled elliptical footprint. This is a bounded internal reflection,
    // never a transformed copy of the horizontal streak.
    float3 ghost=0.0f;
    // Internal ghosts are also full-resolution analytic primitives now. Image
    // reprojection in this reduced buffer produced tiled practical-light blobs.
    float ghostAmount=0.0f;
    if(ghostAmount>1e-6f) {
        float2 centre=clamp(p.opticalCenter,float2(0.0f),float2(1.0f))*float2(width,height);
        float position=p.anamorphicFlareGhostPosition;
        float signedPosition=abs(position)<.05f?(position<0.0f?-.05f:.05f):position;
        float scale=clamp(p.anamorphicFlareGhostScale,.25f,3.0f);
        float2 sourcePosition=centre+(pixel-centre)/(signedPosition*scale);
        constexpr int ghostSamples=28;
        constexpr float goldenAngle=2.39996323f;
        float ghostWeight=0.0f;
        for(int i=0;i<ghostSamples;++i) {
            float radius=sqrt((float(i)+.5f)/float(ghostSamples));
            float angle=float(i)*goldenAngle;
            float2 offset=float2(cos(angle)*radius*3.2f*scale,
                                 sin(angle)*radius*6.2f*scale);
            float2 samplePosition=sourcePosition+offset;
            // Do not let the sampler clamp an off-frame reflected source to
            // the border. That turns a single edge highlight into a solid
            // magenta bar spanning every output pixel that maps past it.
            bool inside=samplePosition.x>=0.0f&&samplePosition.y>=0.0f
                     &&samplePosition.x<=float(width-1u)
                     &&samplePosition.y<=float(height-1u);
            if(inside) {
                float w=(1.0f-radius*.72f);
                float3 ghostSample=sampleBilinear(highlightSource,samplePosition,width,height).rgb;
                float ghostLuma=dot(ghostSample,float3(.2126f,.7152f,.0722f));
                float surroundLuma=(
                    dot(sampleBilinear(highlightSource,samplePosition+float2(3,0),width,height).rgb,float3(.2126f,.7152f,.0722f))
                   +dot(sampleBilinear(highlightSource,samplePosition-float2(3,0),width,height).rgb,float3(.2126f,.7152f,.0722f))
                   +dot(sampleBilinear(highlightSource,samplePosition+float2(0,3),width,height).rgb,float3(.2126f,.7152f,.0722f))
                   +dot(sampleBilinear(highlightSource,samplePosition-float2(0,3),width,height).rgb,float3(.2126f,.7152f,.0722f)))*.25f;
                float compactGate=smoothstep(.08f,.42f,
                    max(ghostLuma-surroundLuma*.88f,0.0f)/max(ghostLuma,1e-5f));
                // A flare ghost should be driven by the dominant compact lamp,
                // not every small practical or bokeh point in the frame. The
                // additional energy gate prevents dense highlight arrays from
                // reappearing as a pixelated colored cluster.
                float ghostEnergyGate=smoothstep(.18f,1.20f,ghostLuma);
                ghost+=ghostSample*compactGate*ghostEnergyGate*w;
                ghostWeight+=w;
            }
        }
        ghost/=max(ghostWeight,1e-6f);
        ghost=ghost/(float3(1.0f)+ghost*.30f);
    }

    float amount=max(p.anamorphicFlareAmount,0.0f);
    float3 streakColor=max(p.anamorphicFlareColor,float3(0.0f));
    float3 ghostColor=max(p.anamorphicFlareGhostColor,float3(0.0f));
    float3 result=(broad*.82f+core*max(p.anamorphicFlareCoreAmount,0.0f))
                    *amount*streakColor
                 +ghost*ghostAmount*amount*ghostColor
                 +verticalRay*rayAmount*amount*mix(float3(1.0f),streakColor,.28f);
    destination[gid.y*width+gid.x]=float4(result,broadScatter[gid.y*width+gid.x].a);
}

static float3 analyticFlareElements(float2 pixel,
                                    device const LDBFlareSource* sources,
                                    constant LDBOpticsParameters& p) {
    if(p.anamorphicFlareAmount<=1e-6f)return float3(0.0f);
    float strongest=max(sources[0].positionEnergyRadius.z,1e-6f);
    float2 opticalCentre=clamp(p.opticalCenter,float2(0.0f),float2(1.0f))
                        *p.imageSize;
    float3 result=0.0f;
    for(uint index=0u;index<1u;++index) {
        LDBFlareSource source=sources[index];
        if(source.colorActive.w<.5f)continue;
        float energy=source.positionEnergyRadius.z;
        float relative=pow(clamp(energy/strongest,0.0f,1.0f),.72f);
        float energyGain=energy/(1.0f+energy*.28f);
        float3 sourceColor=clamp(source.colorActive.xyz,float3(.12f),float3(3.0f));
        float2 sourcePosition=source.positionEnergyRadius.xy;
        float sourceRadius=source.positionEnergyRadius.w;

        // Two continuous analytic layers form a narrow bright diffraction ray
        // with a long, very soft tail. No sampled convolution is stretched
        // across the image, so the gradient cannot resolve into steps.
        float rayAmount=max(p.diffractionRayAmount,0.0f);
        if(rayAmount>1e-6f) {
            float2 delta=pixel-sourcePosition;
            float length=max(p.diffractionRayLength,1.0f);
            float coreWidth=1.15f*max(p.renderPixelScale,0.0001f)
                           +sourceRadius*.36f;
            float wingWidth=coreWidth*2.8f;
            float core=exp(-.5f*(delta.x/coreWidth)*(delta.x/coreWidth))
                      *exp(-abs(delta.y)/(length*.22f));
            float wing=exp(-.5f*(delta.x/wingWidth)*(delta.x/wingWidth))
                      *exp(-abs(delta.y)/(length*.62f))*.18f;
            float sourceBloom=exp(-dot(delta,delta)
                                  /max(sourceRadius*sourceRadius*5.0f,4.0f))*.22f;
            float3 rayTint=mix(float3(1.0f),
                               max(p.anamorphicFlareColor,float3(0.0f)),.22f);
            result+=(core+wing+sourceBloom)*energyGain*relative*rayAmount
                    *p.anamorphicFlareAmount*rayTint*sourceColor;
        }

        // One bounded reflection path, rendered as a soft filled ellipse plus
        // a restrained rim. Position follows the source around Optical Center;
        // the photographed scene itself is never copied into the primitive.
        float ghostAmount=max(p.anamorphicFlareGhostAmount,0.0f);
        // The dominant coherent source owns the internal-reflection path.
        if(ghostAmount>1e-6f&&index==0u) {
            float2 primaryGhostCentre=opticalCentre
                +p.anamorphicFlareGhostPosition*(sourcePosition-opticalCentre);
            float baseRadius=(24.0f*max(p.renderPixelScale,0.0001f)
                             +sourceRadius*3.0f)
                *clamp(p.anamorphicFlareGhostScale,.25f,3.0f);
            uint ghostCount=uint(clamp(round(p.anamorphicFlareGhostCount),1.0f,6.0f));
            float2 pathDirection=normalize(sourcePosition-opticalCentre+float2(1e-4f,0.0f));
            float spacing=max(p.anamorphicFlareGhostSpacing,0.0f);
            float scaleDecay=clamp(p.anamorphicFlareGhostScaleDecay,.35f,1.0f);
            float energyDecay=clamp(p.anamorphicFlareGhostEnergyDecay,.15f,1.0f);
            for(uint path=0u;path<ghostCount;++path) {
                float ordinal=float((path+1u)/2u)*(path%2u?1.0f:-1.0f);
                float pathScale=pow(scaleDecay,float(path));
                float pathEnergy=pow(energyDecay,float(path));
                float2 ghostCentre=primaryGhostCentre+pathDirection*spacing*ordinal;
                float2 ghostDelta=pixel-ghostCentre;
                float2 axes=float2(baseRadius*1.55f,baseRadius*.82f)*pathScale;
                float radiusSquared=dot(ghostDelta/axes,ghostDelta/axes);
                if(radiusSquared<9.0f) {
                    float fill=exp(-radiusSquared*2.35f);
                    float radius=sqrt(max(radiusSquared,0.0f));
                    float rim=exp(-.5f*pow((radius-.82f)/.16f,2.0f))*.16f;
                    float inner=exp(-radiusSquared*7.5f)*.10f;
                    float tintPhase=float(path)*1.73f;
                    float3 tintVariation=float3(.92f+.08f*sin(tintPhase),
                                                .92f+.08f*sin(tintPhase+2.1f),
                                                1.0f);
                    float3 ghostTint=max(p.anamorphicFlareGhostColor,float3(0.0f))*tintVariation;
                    result+=(fill+rim+inner)*energyGain*relative*ghostAmount
                            *p.anamorphicFlareAmount*ghostTint*pathEnergy
                            *mix(float3(1.0f),sourceColor,.18f)*.42f;
                }
            }
        }
    }
    return result;
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
                         device const LDBFlareSource* flareSources [[buffer(13)]],
                         device const float4* opticalScatterScattered [[buffer(14)]],
                         constant LDBScatterParameters& opticalScatter [[buffer(15)]],
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
    float3 flare=sampleBilinear(flareScattered,flarePixel,
        uint(flareScatter.imageSize.x),uint(flareScatter.imageSize.y)).rgb;
    float2 opticalScatterPixel = (float2(gid) + 0.5f) /
        float(opticalScatter.scale) - 0.5f;
    float3 opticalScatterLight = sampleBilinear(opticalScatterScattered,
        opticalScatterPixel,uint(opticalScatter.imageSize.x),
        uint(opticalScatter.imageSize.y)).rgb;
    flare+=analyticFlareElements(float2(gid)+.5f,flareSources,p);
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
        float opticalScatterDepth=normalizedDepth(sampleNearest(
            opticalScatterScattered,opticalScatterPixel,
            uint(opticalScatter.imageSize.x),uint(opticalScatter.imageSize.y)),p);
        opticalScatterLight*=protectedLayerAgreement(targetDepth,opticalScatterDepth,p);
    }
    float apertureMix=clamp(p.apertureResponse,0.0f,1.0f);
    // Without external depth, the shaped optical field is the focus model:
    // retain a usable centre and progressively blend the reconstructed pupil
    // toward the edge. Previously this happened only when Bokeh Swirl was
    // nonzero, so ordinary depth-free aperture blur was global and Field
    // Onset/Falloff could not create spherical edge defocus.
    #if !defined(LDB_EXPERIMENT_CONTINUOUS_FIELD_PSF)
    if(p.depthMode==0u&&apertureMix>0.0f) {
        float2 uv=(float2(gid)+0.5f)/p.imageSize;
        float2 field=uv-p.fieldCenter;
        float angle=p.fieldRotation*(M_PI_F/180.0f);
        float s=sin(angle),c=cos(angle);
        float2 local=float2(c*field.x+s*field.y,-s*field.x+c*field.y);
        float aspect=sqrt(clamp(p.fieldAspect,0.25f,4.0f));
        float radius=length(float2(local.x*aspect,local.y/aspect))*2.0f;
        float onset=clamp(p.responseFieldOnset,0.0f,1.5f);
        float fieldEnd=onset+max(clamp(p.responseFieldFalloff,0.0f,1.5f),0.08f);
        float envelope=smoothstep(onset,fieldEnd,clamp(radius,0.0f,1.5f));
        apertureMix*=envelope;
    }
    #endif
    float3 directOptics=mix(direct[index].rgb,apertureScattered[index].rgb,apertureMix);
    float2 wearUV=(float2(gid)+0.5f)/p.imageSize;
    float3 wearPattern=frontElementPattern(wearUV,p);
    float coatingPattern=coatingWearPattern(wearUV,p);
    float marksAmount=clamp(p.cleaningMarks,0.0f,2.0f);
    float scratchesAmount=clamp(p.scratchAmount,0.0f,2.0f);
    float coatingAmount=clamp(p.coatingWear,0.0f,2.0f);
    // Damage primarily changes the amount and tint of forward scatter. The
    // procedural masks add restrained unevenness; they must never read as
    // bright scratch artwork laid over the photographed scene.
    float wearScatterGain=clamp(p.frontHaze,0.0f,2.0f)*.14f
        +marksAmount*(.018f+wearPattern.x*.28f)
        +scratchesAmount*(.004f+wearPattern.y*.62f)
        +coatingAmount*(.018f+coatingPattern*.28f);
    float internalScatterGain=0.0f;
    if(p.internalDirtAmount>0.0f&&p.internalDirtScatter>0.0f) {
        float imageAspect=p.imageSize.x/max(p.imageSize.y,1.0f);
        float internalMask=internalContaminationPattern(
            wearUV,p.internalDirtScale,p.internalDirtSmear,p.internalDirtAmount,
            p.internalDirtSoftness,p.internalDirtComplexity,
            p.internalDirtSeed,imageAspect);
        float dirtAmount=clamp(p.internalDirtAmount,0.0f,10.0f);
        float scatterAmount=min(dirtAmount,2.0f)
            +2.0f*(1.0f-exp(-max(dirtAmount-2.0f,0.0f)*.35f));
        internalScatterGain=clamp(internalMask*scatterAmount
            *clamp(p.internalDirtScatter,0.0f,2.0f)*.16f,0.0f,1.0f);
    }
    float3 result = directOptics
                  + bloom * max(0.0f, p.bloomEnergy)
                  + opticalScatterLight * wearScatterGain
                  + opticalScatterLight * internalScatterGain
                  + glare * max(0.0f, p.glareEnergy) * glareTint
                  + halo * clamp(p.sphericalHalo, 0.0f, 2.0f) * 0.22f
                  + flare;
    uint diagnostic = p.processingFlags & LDBDiagnosticMask;
    if (diagnostic == LDBDiagnosticDifference)
        result = float3(0.18f) + (result - source[index].rgb) * 2.0f;
    else if (diagnostic == LDBDiagnosticScatter)
        result = (bloom * max(0.0f, p.bloomEnergy)
                + opticalScatterLight * (wearScatterGain + internalScatterGain)
                + glare * max(0.0f, p.glareEnergy) * glareTint
                + halo * clamp(p.sphericalHalo, 0.0f, 2.0f) * 0.22f
                + flare) * 2.0f;
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
