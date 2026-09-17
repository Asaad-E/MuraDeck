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


// Pre-Contrast
uniform float PreContrast < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.5; ui_max = 4.0;
    ui_label = "Pre-Contrast";
    ui_tooltip = "Pre-contrast to normalize HDR color profile.";
> = 1.01;


// Lift Gamma Gain
uniform float3 RGB_Lift < __UNIFORM_SLIDER_FLOAT3
    ui_min = 0.0; ui_max = 2.0;
    ui_label = "RGB Lift";
    ui_tooltip = "Adjust shadows.";
> = float3(1.0, 0.99, 1.0);

uniform float3 RGB_Gamma < __UNIFORM_SLIDER_FLOAT3
    ui_min = 0.1; ui_max = 3.0;
    ui_label = "RGB Gamma";
    ui_tooltip = "Adjust midtones.";
> = 1.0;

uniform float3 RGB_Gain < __UNIFORM_SLIDER_FLOAT3
    ui_min = 0.0; ui_max = 2.0;
    ui_label = "RGB Gain";
    ui_tooltip = "Adjust highlights.";
> = 1.0;

uniform int LggFadeNearBright < __UNIFORM_SLIDER_INT1
    ui_min = 0; ui_max = 100;
    ui_label = "LGG Fade Near Bright";
    ui_tooltip = "Higher values give less LGG to brighter pixels. Higher = Faster fade.";
> = 90;


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
    ui_min = 0; ui_max = 100;
    ui_label = "Grain Fade Near Bright";
    ui_tooltip = "Higher values give less grain to brighter pixels. Higher = Faster fade.";
> = 90;

uniform float GrainFadeNearBlack < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.1; ui_max = 8.0;
    ui_label = "Grain Fade Near Black";
    ui_tooltip = "Higher values give less grain to dark pixels. Higher = Faster fade.";
> = 0.175;


// Mura
uniform float MuraFadeNearWhite < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.1; ui_max = 20.0;
    ui_label = "Mura Fade Near White";
    ui_tooltip = "Higher values give less mura to brighter pixels. Higher = Faster fade.";
> = 4.75;

uniform float MuraFadeNearBlack < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 20.0;
    ui_label = "Mura Fade Near Black";
    ui_tooltip = "Higher values give less mura to dark pixels. Higher = Faster fade.";
> = 0.0;

uniform float MuraBlackCutoff < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 0.1;
    ui_label = "Mura Black Cutoff";
    ui_tooltip = "Below this luma level, Mura correction is completely disabled.";
> = 0.001;

uniform float MuraMapScale < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 5.0;
    ui_label = "Mura Correction Strength";
    ui_tooltip = "Controls how aggressive mura map.";
> = 0.3;

uniform float MuraShadowGuard < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Mura Shadow Guard";
    ui_tooltip = "How far up the tone range mura correction stays suppressed. Higher = cleaner dark greys/blues, at the cost of leaving mura uncorrected in the shadows.";
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

// Box-averages the texels inside a block so pixelation reads as clean recreated "big
// pixels" instead of aliased point sampling. Blocks of ~1 screen pixel have nothing to
// average, so they short-circuit to a single texel and the slider's low end is a true
// pass-through.
float3 SampleBlockAverage(float2 blockOrigin, float2 blockUV)
{
    if (Pixelate_BlockSize < 1.5)
        return FetchTexel(blockOrigin + blockUV * 0.5);

    float3 sum = 0.0;
    sum += FetchTexel(blockOrigin + blockUV * float2(0.16667, 0.16667));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.50000, 0.16667));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.83333, 0.16667));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.16667, 0.50000));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.50000, 0.50000));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.83333, 0.50000));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.16667, 0.83333));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.50000, 0.83333));
    sum += FetchTexel(blockOrigin + blockUV * float2(0.83333, 0.83333));
    return sum * (1.0 / 9.0);
}

float3 SamplePixelated(float2 texcoord)
{
    if (Pixelate_Enabled <= 0.0)
        return tex2D(ReShade::BackBuffer, texcoord).rgb;

    float2 blockUV = PixelateBlockUV();
    float2 blockOrigin = floor(texcoord / blockUV) * blockUV;
    return SampleBlockAverage(blockOrigin, blockUV);
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

// --- CAS Helper ---
float3 SampleOffset(float2 texcoord, int2 offset)
{
    if (Pixelate_Enabled > 0.0)
    {
        // Step CAS's neighborhood by whole blocks so it sharpens between pixel-art blocks
        // rather than within one (which would have nothing to sharpen against).
        float2 blockUV = PixelateBlockUV();
        float2 blockOrigin = floor(texcoord / blockUV) * blockUV + blockUV * offset;

        // Only the block actually being output needs the full box average; neighbours just
        // need a representative colour for CAS's min/max window, so one texel is enough
        // and the combined cost stays at 17 taps instead of 81.
        if (offset.x == 0 && offset.y == 0)
            return SampleBlockAverage(blockOrigin, blockUV);
        return FetchTexel(blockOrigin + blockUV * 0.5);
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
float RcasSharpness
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
    lobe *= RcasSharpness * nz;

    float3 outColor = (lobe * (b + d + f + h) + e) / (4.0 * lobe + 1.0);
    return saturate(outColor);
}


float3 MuraDeck(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = ApplyRCAS(texcoord);

    // PRE-CONTRAST
    float3 contrasted = saturate((color - 0.5) * PreContrast + 0.5);
    float luma = dot(contrasted, float3(0.2126, 0.7152, 0.0722));

    if (luma <= 0.0001)
        return color;

    // GRAIN
    {
        float inv_luma = dot(contrasted, float3(-1.0 / 3.0, -1.0 / 3.0, -1.0 / 3.0)) + 1.0;
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

        // fade_dark alone never faded anything (MuraFadeNearBlack is tuned to ~0, and
        // pow(x, 0) is 1), so the map landed at near-full strength on dark greys and blues.
        // A fixed +/- offset there is a >100% *relative* perturbation of the pixel, and
        // since only R and G have maps it perturbs them chromatically — the colour noise
        // on dark blues. The smoothstep is the shadow fade that was missing.
        float fade_dark = pow(saturate(luma), MuraFadeNearBlack);
        float fade_bright = pow(1.0 - saturate(luma), MuraFadeNearWhite);
        float shadow_fade = smoothstep(
            MuraBlackCutoff, lerp(0.04, 0.40, MuraShadowGuard), luma);
        float mura_blend = fade_dark * fade_bright * shadow_fade;

        // Limit the offset to the headroom the pixel actually has on each side, so the
        // negative half of the map can't clip away on dark pixels and leave only its
        // positive half behind as a raised, blotchy black.
        float3 mura_offset =
            float3(red.r - 0.5, green.g - 0.5, 0.0) * MuraMapScale * mura_blend;
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
