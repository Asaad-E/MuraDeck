// LICENSE
// =======
// Copyright (c) 2017-2019 Advanced Micro Devices, Inc. All rights reserved.
// -------
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
// -------
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.
// -------
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE

//Initial port to ReShade: SLSNe    https://gist.github.com/SLSNe/bbaf2d77db0b2a2a0755df581b3cf00c
//Optimizations by Marty McFly:
//     vectorized math, even with scalar gcn hardware this should work
//     out the same, order of operations has not changed
//     For some reason, it went from 64 to 48 instructions, a lot of MOV gone
//     Also modified the way the final window is calculated
//      
//     reordered min() and max() operations, from 11 down to 9 registers    
//
//     restructured final weighting, 49 -> 48 instructions
//
//     delayed RCP to replace SQRT with RSQRT
//
//     removed the saturate() from the control var as it is clamped
//     by UI manager already, 48 -> 47 instructions
//
//     replaced tex2D with tex2Doffset intrinsic (address offset by immediate integer)
//     47 -> 43 instructions
//     9 -> 8 registers

// Conversion Compability for Gamescope/vkBasalt reshade by Moonveil Kanata - RenvyRere

#include "ReShadeUI.fxh"

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

#include "ReShade.fxh"

float3 SampleOffset(float2 texcoord, int2 offset) {
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

float3 CASPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
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


technique ContrastAdaptiveSharpen
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = CASPass;
	}
}
