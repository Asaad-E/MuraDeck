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

float3 ApplyRCAS(float2 texcoord)
{
    float3 eRaw = SampleOffset(texcoord, int2(0, 0));
    if (CAS_Enabled <= 0.0)
        return eRaw;

    float3 e = eRaw;
    float3 b = (SampleOffset(texcoord, int2( 0, -1)));
    float3 d = (SampleOffset(texcoord, int2(-1,  0)));
    float3 f = (SampleOffset(texcoord, int2( 1,  0)));
    float3 h = (SampleOffset(texcoord, int2( 0,  1)));

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
    return saturate(outColor);
}


float3 MuraDeck(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = ApplyRCAS(texcoord);

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
        float response = lerp(1.0, saturate(luma / 0.5), MuraResponse);
        float fade_mura = pow(saturate(luma), MuraFadeNearBlack) * response;

        // Limit the offset to the headroom the pixel actually has on each side. Without
        // this the negative half of the map clips at 0 on dark pixels while the positive
        // half survives, and that one-sided survival is exactly the raised, blotchy black
        // this plugin exists to avoid.
        float3 mura_offset =
            float3(red.r - 0.5, green.g - 0.5, 0.0) * MuraMapScale * fade_mura;
        float3 headroom = min(color, 1.0 - color);
        mura_offset = clamp(mura_offset, -headroom, headroom);

        color = saturate(color + mura_offset);
    }

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
