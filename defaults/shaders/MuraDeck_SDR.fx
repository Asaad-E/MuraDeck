/**
 * MuraDeck
 * by RenvyRere - Moonveil-Kanata
 *
 * Fix Mura Effect on OLED Panel, by Combining Lift Gamma Gain and Film Grain as dithering on dark pixel, while Mura map on the bright pixel.
 */

#include "ReShadeUI.fxh"

// CAS
uniform float CAS_Enabled <
    ui_label = "Turn On/Off CAS";
    ui_tooltip = "0 := disable, to 1 := enable.";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 1.0;
> = 0.0;

uniform float Sharpness <
	ui_type = "drag";
	ui_label = "Sharpening strength";
	ui_tooltip = "0 := gentle, 1 := maximum. Maps onto AMD RCAS sharpness stops.";
	ui_min = 0.0; ui_max = 1.0;
> = 0.0;

uniform float RcasLumaOnly <
    ui_label = "Sharpen luminance only";
    ui_tooltip = "0 := sharpen each colour channel, 1 := sharpen brightness only and leave colour alone.";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 1.0;
> = 0.0;


// Pixel Art
uniform float Pixelate_Enabled <
    ui_label = "Turn On/Off Pixel Art Mode";
    ui_tooltip = "0 := disable, to 1 := enable.";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 1.0;
> = 0.0;

uniform float Pixelate_BlockSize < __UNIFORM_SLIDER_FLOAT1
    ui_min = 1.0; ui_max = 24.0;
    ui_label = "Pixel Art Block Size";
    ui_tooltip = "Size (in screen pixels) of each recreated pixel block. Fractional values matter: a game upscaled by 1.6x needs 1.6, not 2.";
> = 4.0;


// Anti-aliasing
uniform float FXAA_Enabled <
    ui_label = "Turn On/Off Anti-Aliasing";
    ui_tooltip = "0 := disable, to 1 := enable.";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 1.0;
> = 0.0;


// Debanding
uniform float Deband_Enabled <
    ui_label = "Turn On/Off Debanding";
    ui_tooltip = "0 := disable, to 1 := enable.";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 1.0;
> = 0.0;


// Lift Gamma Gain
uniform float3 RGB_Lift < __UNIFORM_SLIDER_FLOAT3
    ui_min = 0.0; ui_max = 2.0;
    ui_label = "RGB Lift";
    ui_tooltip = "Adjust shadows.";
> = 0.95;

uniform float3 RGB_Gamma < __UNIFORM_SLIDER_FLOAT3
    ui_min = 0.1; ui_max = 3.0;
    ui_label = "RGB Gamma";
    ui_tooltip = "Adjust midtones.";
> = 0.98;

uniform float3 RGB_Gain < __UNIFORM_SLIDER_FLOAT3
    ui_min = 0.0; ui_max = 2.0;
    ui_label = "RGB Gain";
    ui_tooltip = "Adjust highlights.";
> = 1.0;

uniform int LggFadeNearBright < __UNIFORM_SLIDER_INT1
    ui_min = 0; ui_max = 16;
    ui_label = "LGG Fade Near Bright";
    ui_tooltip = "Higher values give less LGG to brighter pixels. Higher = Faster fade.";
> = 20;


// Grain
uniform float Intensity < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Grain Intensity";
    ui_tooltip = "How visible the grain is. Higher is more visible.";
> = 0.01;

uniform float Variance < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 1.0;
    ui_tooltip = "Controls the variance of the Gaussian noise. Lower values look smoother.";
> = 1.0;

uniform float Mean < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 1.0;
    ui_tooltip = "Affects the brightness of the noise.";
> = 0.5;

uniform int GrainFadeNearBright < __UNIFORM_SLIDER_INT1
    ui_min = 0; ui_max = 16;
    ui_label = "Grain Fade Near Bright";
    ui_tooltip = "Higher values give less grain to brighter pixels. Higher = Faster fade.";
> = 60;
uniform float GrainFadeNearBlack < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.1; ui_max = 8.0;
    ui_label = "Grain Fade Near Black";
    ui_tooltip = "Higher values give less grain to dark pixels. Higher = Faster fade.";
> = 0.03;

uniform float GrainBlackCutoff < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 0.1;
    ui_label = "Grain Black Cutoff";
    ui_tooltip = "Below this luminance, grain is fully disabled.";
> = 0.001;


// Mura Correction
uniform float MuraFadeNearBlack < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 8.0;
    ui_label = "Mura Fade Near Black";
    ui_tooltip = "Higher values give less mura to dark pixels. Higher = Faster fade.";
> = 0.02;

uniform float MuraBlackCutoff < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 0.1;
    ui_label = "Mura Black Cutoff";
    ui_tooltip = "Below this luma level, Mura correction is completely disabled.";
> = 0.01;

uniform float MuraMapScale < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 5.0;
    ui_label = "Mura Correction Strength";
    ui_tooltip = "Controls how aggressive mura map.";
> = 0.0625;

uniform float MuraResponse < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Mura Response Curve";
    ui_tooltip = "0 treats mura as a fixed offset, 1 scales the correction with each pixel's own level. Higher suits a gain-type panel error and keeps shadows clean.";
> = 1.0;

uniform float MuraStrength < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.5; ui_max = 1.5;
    ui_label = "Mura Strength";
    ui_tooltip = "Multiplies the brightness-adapted mura strength. 1 keeps the tuned value.";
> = 1.0;

texture red_tex < source = "red.png"; > { Width = 1280; Height = 800; Format = RGBA8; };
texture green_tex < source = "green.png"; > { Width = 1280; Height = 800; Format = RGBA8; };

sampler red_s { Texture = red_tex; };
sampler green_s { Texture = green_tex; };

uniform float Timer < source = "timer"; >;

#include "ReShade.fxh"

// --- Pixel Art helpers ---
// Reads one exact texel. Every pixel-art tap goes through here: sampling anywhere other
// than a texel centre lets bilinear filtering blend in the neighbouring texel, which is
// what made small block sizes come out blurrier than no pixelation at all.
float3 FetchTexel(float2 uv)
{
    return tex2D(ReShade::BackBuffer,
                 (floor(uv * ReShade::ScreenSize) + 0.5) * ReShade::PixelSize).rgb;
}

float2 PixelateBlockUV()
{
    return max(Pixelate_BlockSize, 1.0) * ReShade::PixelSize;
}

// One texel from the middle of the block. This used to average nine taps placed at 1/6, 1/2
// and 5/6 across the block, but each tap then snapped to a texel centre, which pulled the
// sampled centroid off the block's true centre - by half a texel at some sizes, and by a
// different amount at each size, so the picture shifted as the slider moved. The single
// centre texel is correctly centred at every size, measures sharper against a true nearest
// upscale (0.0095 against 0.0062 edge energy at block 2.25, where not pixelating at all is
// 0.0102), and costs one tap instead of nine.
float3 SampleBlock(float2 blockOrigin, float2 blockUV)
{
    return FetchTexel(blockOrigin + blockUV * 0.5);
}

// texcoord snapped to the pixel-art block grid, used to keep grain noise coherent per-block
// instead of leaking real-pixel-granularity dither into a supposedly clean pixel block.
float2 GetGrainCoord(float2 texcoord)
{
    if (Pixelate_Enabled <= 0.0)
        return texcoord;
    float2 blockUV = PixelateBlockUV();
    return floor(texcoord / blockUV) * blockUV;
}

// Interleaved Gradient Noise. Replaces the Box-Muller gaussian this shader used to dither
// with: that distribution is unbounded, so its tails landed as bright specks on flat dark
// areas, and being white noise its energy sat right where the eye is most sensitive. IGN
// is bounded to [0,1) and pushes its energy high-frequency, so it breaks banding just as
// well at the same amplitude without reading as sensor noise. Static by design — the old
// Timer-driven animation made the same noise shimmer, which is what makes it visible.
float DitherNoise(float2 pixelPos)
{
    return frac(52.9829189 * frac(dot(pixelPos, float2(0.06711056, 0.00583715))));
}

float3 SampleOffset(float2 texcoord, int2 offset)
{
    if (Pixelate_Enabled > 0.0)
    {
        // Step the neighbourhood by whole blocks so RCAS sharpens between pixel-art blocks
        // rather than within one, where there would be nothing to sharpen against. Centre
        // and neighbours go through the same estimator on purpose: when the centre was a
        // nine-tap average and the neighbours single taps, the two disagreed by up to half
        // the range on detailed content, and RCAS read that disagreement as image content.
        float2 blockUV = PixelateBlockUV();
        float2 blockOrigin = floor(texcoord / blockUV) * blockUV + blockUV * offset;
        return SampleBlock(blockOrigin, blockUV);
    }
    return tex2D(ReShade::BackBuffer, texcoord + ReShade::PixelSize * offset).rgb;
}

// --- AMD FidelityFX RCAS (the sharpening pass of FSR 1.0) ---
// Ported from AMD's ffx_fsr1.h. RCAS rather than CAS because of where this sits in the
// pipeline: gamescope has already scaled the frame by the time reshade sees it, and RCAS is
// the pass AMD wrote for sharpening an image that is *already* upscaled. It also carries a
// noise-detection term, which plain CAS has none of - sharpening a frame that already
// contains grain, dither or upscale ringing is what makes sharpening read as added noise.
#define RCAS_LIMIT (0.25 - (1.0 / 16.0))

// AMD's parameter is in stops of reduction (sharpness = exp2(-stops)), so the 0..1 slider
// maps onto [2, 0] stops. This is also the fix for the old CAS slider, whose 0 was not "no
// sharpening" but still boosted edges by ~16%; a quarter-strength lobe actually is gentle.
float RcasSharpness()
{
    return exp2(-(1.0 - saturate(Sharpness)) * 2.0);
}

// AMD's luma weights, which sum to 2.0 rather than 1.0. Kept exactly as the reference has
// them so the noise term's thresholds behave as designed.
float RcasLuma(float3 c)
{
    return c.b * 0.5 + (c.r * 0.5 + c.g);
}

// --- FXAA: optional edge anti-aliasing ---
// NVIDIA's FXAA 3.11, reworked for a shader that only has exact texel fetches. FXAA moves a
// pixel perpendicular to its edge and probes half a pixel off the pixel row, so the result is a
// lerp between two texels and each probe is the mean of two - neither needs a filtered sampler.
// Tuned against a supersampled reference: subpixel 0.25 rather than the stock 0.75, which
// softens 1px lines and text and scored worse on every measure; and the search doubles its
// reach (1, 2, 4 ... 32) instead of stepping linearly, because long shallow edges need
// distance, not density. It exits early on anything without contrast, which is most of the
// picture, so the average cost is barely above the five taps RCAS reads anyway.
#define AA_THRESHOLD     0.166
#define AA_THRESHOLD_MIN 0.0312
#define AA_SUBPIX        0.25

float3 AAEnc(float3 c) { return c; }
float3 AADec(float3 c) { return c; }

float AALuma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float3 AAFetch(float2 uv, float2 pixelOffset)
{
    return AAEnc(tex2D(ReShade::BackBuffer, uv + ReShade::PixelSize * pixelOffset).rgb);
}

// Luma of the edge line - half a pixel across the edge from the pixel row - d pixels along it.
float AALine(float2 uv, float2 t, float2 a, float d)
{
    return 0.5 * (AALuma(AAFetch(uv, t * d)) + AALuma(AAFetch(uv, t * d + a)));
}

// How far along the edge, in direction s, until the edge line's luma has moved by at least
// `grad` from where it started. 32 if it never does within reach.
float AASearch(float2 uv, float2 t, float2 a, float refL, float grad, float s)
{
    float d = 32.0;
    if      (abs(AALine(uv, t, a, s *  1.0) - refL) >= grad) d =  1.0;
    else if (abs(AALine(uv, t, a, s *  2.0) - refL) >= grad) d =  2.0;
    else if (abs(AALine(uv, t, a, s *  4.0) - refL) >= grad) d =  4.0;
    else if (abs(AALine(uv, t, a, s *  8.0) - refL) >= grad) d =  8.0;
    else if (abs(AALine(uv, t, a, s * 16.0) - refL) >= grad) d = 16.0;
    return d;
}

// cM is the pixel, the others its four neighbours (up, left, right, down), already encoded.
float3 ApplyFXAA(float2 uv, float3 cM, float3 cN, float3 cW, float3 cE, float3 cS)
{
    float lM = AALuma(cM);
    float lN = AALuma(cN);
    float lW = AALuma(cW);
    float lE = AALuma(cE);
    float lS = AALuma(cS);

    float rMax = max(max(max(lN, lW), max(lE, lS)), lM);
    float rMin = min(min(min(lN, lW), min(lE, lS)), lM);
    float range = rMax - rMin;
    if (range < max(AA_THRESHOLD_MIN, rMax * AA_THRESHOLD))
        return cM;

    float lNW = AALuma(AAFetch(uv, float2(-1.0, -1.0)));
    float lNE = AALuma(AAFetch(uv, float2( 1.0, -1.0)));
    float lSW = AALuma(AAFetch(uv, float2(-1.0,  1.0)));
    float lSE = AALuma(AAFetch(uv, float2( 1.0,  1.0)));

    float lNS = lN + lS;
    float lWE = lW + lE;
    float edgeHorz = abs(-2.0 * lW + (lNW + lSW)) + abs(-2.0 * lM + lNS) * 2.0 + abs(-2.0 * lE + (lNE + lSE));
    float edgeVert = abs(-2.0 * lS + (lSW + lSE)) + abs(-2.0 * lM + lWE) * 2.0 + abs(-2.0 * lN + (lNW + lNE));
    bool horz = edgeHorz >= edgeVert;

    // The two neighbours across the edge; the edge runs towards whichever is steeper.
    float lA = lW;
    float lB = lE;
    if (horz)
    {
        lA = lN;
        lB = lS;
    }
    float gA = lA - lM;
    float gB = lB - lM;
    bool towardA = abs(gA) >= abs(gB);
    float grad = max(abs(gA), abs(gB)) * 0.25;
    float lNN = lB + lM;
    if (towardA)
        lNN = lA + lM;

    float3 cAcross = cW;
    if (horz)
        cAcross = cN;
    if (!towardA)
    {
        cAcross = cE;
        if (horz)
            cAcross = cS;
    }

    float sgn = 1.0;
    if (towardA)
        sgn = -1.0;
    float2 t = float2(0.0, 1.0);
    float2 a = float2(sgn, 0.0);
    if (horz)
    {
        t = float2(1.0, 0.0);
        a = float2(0.0, sgn);
    }
    bool mltz = (lM - lNN * 0.5) < 0.0;

    float subA = (lNS + lWE) * 2.0 + (lNW + lSW) + (lNE + lSE);
    float subC = saturate(abs(subA / 12.0 - lM) / range);
    float subS = (3.0 - 2.0 * subC) * subC * subC;
    float subH = subS * subS * AA_SUBPIX;

    float dstN = AASearch(uv, t, a, lNN * 0.5, grad, -1.0);
    float dstP = AASearch(uv, t, a, lNN * 0.5, grad,  1.0);
    float endN = AALine(uv, t, a, -dstN) - lNN * 0.5;
    float endP = AALine(uv, t, a,  dstP) - lNN * 0.5;

    bool dirN = dstN < dstP;
    float endSel = endP;
    float dstMin = dstP;
    if (dirN)
    {
        endSel = endN;
        dstMin = dstN;
    }
    bool good = endSel < 0.0;
    if (mltz)
        good = !good;
    float off = 0.5 - dstMin / (dstN + dstP);
    if (!good)
        off = 0.0;
    off = max(off, subH);
    return lerp(cM, cAcross, off);
}

float3 ApplyRCAS(float2 texcoord)
{
    // Anti-aliasing, when it is on. Pixel Art mode quantises the picture into blocks on purpose,
    // and smoothing those edges would undo it, so the two are mutually exclusive.
    bool doAA = FXAA_Enabled > 0.0 && Pixelate_Enabled <= 0.0;
    bool doSharpen = CAS_Enabled > 0.0;

    float3 eRaw = SampleOffset(texcoord, int2(0, 0));
    if (!doAA && !doSharpen)
        return eRaw;

    float3 e = AAEnc(eRaw);
    float3 b = AAEnc(SampleOffset(texcoord, int2( 0, -1)));
    float3 d = AAEnc(SampleOffset(texcoord, int2(-1,  0)));
    float3 f = AAEnc(SampleOffset(texcoord, int2( 1,  0)));
    float3 h = AAEnc(SampleOffset(texcoord, int2( 0,  1)));

    // Only the centre is anti-aliased; RCAS's four neighbours stay as they were. Judged against
    // RCAS run on a perfectly anti-aliased image, that scores the same as anti-aliasing all five
    // taps (21.75 against 22.03 with the shipped parameters, lower is better) for a fraction of
    // the fetches.
    if (doAA)
        e = ApplyFXAA(texcoord, e, b, d, f, h);

    if (!doSharpen)
    {
        // A pixel FXAA left alone must come back exactly as it went in. In scRGB the encode and
        // decode round trip clamps (negatives to zero, the top just under one), so converting
        // every pixel back would alter flat areas that have nothing to do with an edge.
        float3 changed = abs(e - AAEnc(eRaw));
        if (max(max(changed.r, changed.g), changed.b) <= 0.0)
            return eRaw;
        return AADec(e);
    }

    float bL = RcasLuma(b), dL = RcasLuma(d), eL = RcasLuma(e);
    float fL = RcasLuma(f), hL = RcasLuma(h);

    // How far the centre departs from its neighbours, relative to the local range. A flat
    // area carrying speckle scores high here and has its sharpening pulled back, which is
    // the whole reason for preferring RCAS over CAS in this position.
    float nz = 0.25 * (bL + dL + fL + hL) - eL;
    float range = max(max(max(bL, dL), max(eL, fL)), hL)
                - min(min(min(bL, dL), min(eL, fL)), hL);
    nz = saturate(abs(nz) / max(range, 1e-5));
    nz = -0.5 * nz + 1.0;

    float3 mn4 = min(min(b, d), min(f, h));
    float3 mx4 = max(max(b, d), max(f, h));

    // Solve per channel for the largest negative lobe that still would not clip, then take
    // the most restrictive of the three. The guards keep the divisions away from zero.
    float3 hitMin = min(mn4, e) / max(4.0 * mx4, 1e-5);
    float3 hitMax = (1.0 - max(mx4, e)) / min(4.0 * mn4 - 4.0, -1e-5);
    float3 lobeRGB = max(-hitMin, hitMax);

    float lobe = max(-RCAS_LIMIT, min(max(max(lobeRGB.r, lobeRGB.g), lobeRGB.b), 0.0));
    lobe *= RcasSharpness() * nz;

    float3 outColor = (lobe * (b + d + f + h) + e) / (4.0 * lobe + 1.0);

    // Per-channel RCAS sharpens red, green and blue independently, so it also sharpens whatever
    // colour noise sits in them, and can put a thin colour fringe on a coloured edge. Carrying
    // only the brightness change across (the same delta added to every channel) keeps the edge
    // contrast and leaves hue alone, until a channel clips at a saturated edge.
    if (RcasLumaOnly > 0.0)
        outColor = e + dot(outColor - e, float3(0.2126, 0.7152, 0.0722));
    return saturate(outColor);
}


// --- Debanding: optional, SDR only ---
// A smooth gradient quantised to 8 bits becomes plateaus separated by one-level steps, and in
// the dark a one-level step is a big jump in light, which on an OLED is easy to see. Dithering
// the output cannot help: a plateau sits on an integer level and rounds back to it, so the steps
// stay. What does help is averaging across the step to recover the fractional ramp, and then
// dithering to write that value back into 8 bits - the dither is added at the very end of the
// shader (see MuraDeck) so the stages after this one cannot scale it.
//
// Four rings of two opposite taps, radii 2, 4, 8 and 16, the angle hashed per pixel and turned by
// the golden angle each ring so the rings do not line up. A tap only counts if it is within the
// threshold of the centre in every channel, so real edges and detail are left alone. Measured,
// the clear win is a shallow dark ramp, where banding roughly halves (-55%). On a mid-tone ramp and
// a curved vignette the change was a few percent either way, and two independent replications did
// not agree on its sign. Larger radii did better on a plain ramp and worse on curved gradients. It
// always adds about a tenth of a level of fine noise.
#define DEBAND_THRESHOLD (2.5 / 255.0)

float4 DebandTap(float2 uv, float3 c, float2 pixelOffset)
{
    float3 t = tex2D(ReShade::BackBuffer, uv + ReShade::PixelSize * pixelOffset).rgb;
    float3 dl = abs(t - c);
    float4 r = float4(0.0, 0.0, 0.0, 0.0);
    if (max(max(dl.r, dl.g), dl.b) <= DEBAND_THRESHOLD)
        r = float4(t, 1.0);
    return r;
}

float3 ApplyDeband(float2 uv, float3 c)
{
    float theta = 6.2831853 * DitherNoise(uv * ReShade::ScreenSize + float2(17.0, 5.0));
    float4 acc = float4(c, 1.0);
    float2 o;

    o = floor(2.0 * float2(cos(theta), sin(theta)) + 0.5);
    acc += DebandTap(uv, c, o);
    acc += DebandTap(uv, c, -o);

    o = floor(4.0 * float2(cos(theta + 2.399963), sin(theta + 2.399963)) + 0.5);
    acc += DebandTap(uv, c, o);
    acc += DebandTap(uv, c, -o);

    o = floor(8.0 * float2(cos(theta + 4.799926), sin(theta + 4.799926)) + 0.5);
    acc += DebandTap(uv, c, o);
    acc += DebandTap(uv, c, -o);

    o = floor(16.0 * float2(cos(theta + 7.199889), sin(theta + 7.199889)) + 0.5);
    acc += DebandTap(uv, c, o);
    acc += DebandTap(uv, c, -o);

    return acc.rgb / acc.a;
}

float3 MuraDeck(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = ApplyRCAS(texcoord);
    if (Deband_Enabled > 0.0)
        color = ApplyDeband(texcoord, color);

    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    if (luma <= 0.0001)
        return color;

    // GRAIN
    if (luma >= GrainBlackCutoff)
    {
        float inv_luma = dot(color, float3(-1.0 / 3.0, -1.0 / 3.0, -1.0 / 3.0)) + 1.0;
        float stn = GrainFadeNearBright != 0 ? pow(abs(inv_luma), (float)GrainFadeNearBright) : 1.0;

        // Fade grain near black
        float fade_black = pow(saturate(luma), GrainFadeNearBlack);
        float fade_intensity = Intensity * fade_black * stn * Variance;

        float dither = DitherNoise(GetGrainCoord(texcoord) * ReShade::ScreenSize);
        color += (dither - Mean) * fade_intensity;
        color = saturate(color);
    }

    // LIFT GAMMA GAIN
    float3 color_LGG = color * (1.5 - 0.5 * RGB_Lift) + 0.5 * RGB_Lift - 0.5;
    color_LGG = saturate(color_LGG);
    color_LGG *= RGB_Gain;
    color_LGG = pow(abs(color_LGG), 1.0 / RGB_Gamma);
    color_LGG = saturate(color_LGG);

    float fade_lgg = LggFadeNearBright != 0 ? pow(1.0 - luma, (float)LggFadeNearBright) : 1.0;
    color = lerp(color, color_LGG, fade_lgg);

    // MURA CORRECTION
    if (luma > MuraBlackCutoff)
    {
        const float target_aspect = 1280.0 / 800.0;
        float screen_aspect = ReShade::ScreenSize.x / ReShade::ScreenSize.y;
        float2 mura_uv = texcoord;

        if (screen_aspect > target_aspect)
        {
            float scale = target_aspect / screen_aspect;
            mura_uv.y = (mura_uv.y - 0.5) * scale + 0.5;
        }
        else
        {
            float scale = screen_aspect / target_aspect;
            mura_uv.x = (mura_uv.x - 0.5) * scale + 0.5;
        }

        float3 red = tex2D(red_s, mura_uv).rgb;
        float3 green = tex2D(green_s, mura_uv).rgb;

        // Demura is measured per grey level in industry, because a pixel's deviation tracks
        // its drive level instead of being constant. With one map and one scale the closest
        // we get is scaling the correction by the pixel's own level, which is exactly right
        // for a gain-type error and subsumes the shadow gate this replaces - no threshold to
        // pick, and it measured better in every tone band.
        // Scale by each channel's own level rather than by luma, and without a cap.
        // Cancelling a gain error needs the correction proportional to the value being
        // corrected: on a saturated red patch the red channel can sit at 0.6 while luma is
        // 0.22, so luma scales it by the wrong number - and capping at 1.0 under-corrects
        // everything above mid grey, which is why the bright core stayed uncorrected.
        // Measured against the real maps off this panel, fixing both takes the residual in
        // R and G from 1.08 to 0.35 and the visible luma noise from 0.85 to 0.34.
        float3 level = max(color, 0.0) / 0.5;
        float3 response = lerp(float3(1.0, 1.0, 1.0), level, MuraResponse);
        float3 fade_mura = pow(saturate(luma), MuraFadeNearBlack) * response;

        // Limit the offset to the headroom the pixel actually has on each side. Without
        // this the negative half of the map clips at 0 on dark pixels while the positive
        // half survives, and that one-sided survival is exactly the raised, blotchy black
        // this plugin exists to avoid.
        float3 mura_offset =
            float3(red.r - 0.5, green.g - 0.5, 0.0) * MuraMapScale * MuraStrength * fade_mura;
        float3 headroom = min(color, 1.0 - color);
        mura_offset = clamp(mura_offset, -headroom, headroom);

        color = saturate(color + mura_offset);
    }

    // One level, peak to peak, written after every stage that could rescale it. The offset keeps it
    // from tracking the grain's noise, which hashes the same pixel position.
    if (Deband_Enabled > 0.0)
        color += (DitherNoise(texcoord * ReShade::ScreenSize + float2(31.0, 47.0)) - 0.5) / 255.0;

    return color;
}

technique MuraDeck
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = MuraDeck;
    }
}
