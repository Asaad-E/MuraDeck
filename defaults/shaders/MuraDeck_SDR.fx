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
	ui_tooltip = "0 := no sharpening, to 1 := full sharpening.";
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

float3 ApplyCAS(float2 texcoord)
{
    if (CAS_Enabled <= 0.0)
	{
		return SamplePixelated(texcoord);
	}

    float3 a = SampleOffset(texcoord, int2(-1, -1));
    float3 b = SampleOffset(texcoord, int2(0, -1));
    float3 c = SampleOffset(texcoord, int2(1, -1));
    float3 d = SampleOffset(texcoord, int2(-1, 0));
    float3 e = SampleOffset(texcoord, int2(0, 0));
    float3 f = SampleOffset(texcoord, int2(1, 0));
    float3 g = SampleOffset(texcoord, int2(-1, 1));
    float3 h = SampleOffset(texcoord, int2(0, 1));
    float3 i = SampleOffset(texcoord, int2(1, 1));

    float3 mnRGB = min(min(min(d, e), min(f, b)), h);
    mnRGB = min(mnRGB, min(min(a, c), min(g, i))) + mnRGB;

    float3 mxRGB = max(max(max(d, e), max(f, b)), h);
    mxRGB = max(mxRGB, max(max(a, c), max(g, i))) + mxRGB;

    float3 rcpMRGB = rcp(mxRGB);
    float3 ampRGB = saturate(min(mnRGB, 2.0 - mxRGB) * rcpMRGB);
    ampRGB = rsqrt(ampRGB);

    float peak = 8.0 - 3.0 * Sharpness;
    float3 wRGB = -rcp(ampRGB * peak);
    float3 rcpWeightRGB = rcp(1.0 + 4.0 * wRGB);

    float3 window = b + d + f + h;
    float3 outColor = saturate((window * wRGB + e) * rcpWeightRGB);

    return outColor;
}

float3 MuraDeck(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = ApplyCAS(texcoord);

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

        // pow(luma, MuraFadeNearBlack) alone never actually faded anything: with the
        // exponent tuned down to ~0.02 it evaluates to ~0.94 at luma 0.05, so the map was
        // landing at near-full strength on dark greys and blues. A fixed +/- offset there
        // is a >100% *relative* perturbation of the pixel, and since only R and G have
        // maps it perturbs them chromatically — which is the colour noise on dark blues.
        // The smoothstep is the fade that was intended: zero at the cutoff, full by the
        // time there is enough signal to hide a correction in.
        float shadow_fade = smoothstep(
            MuraBlackCutoff, lerp(0.04, 0.40, MuraShadowGuard), luma);
        float fade_mura = pow(saturate(luma), MuraFadeNearBlack) * shadow_fade;

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
