/**
 * MuraDeck multi-pass probe
 *
 * Not an effect anyone should leave on. It exists to answer one question about gamescope's
 * embedded reshade: does it honour a second pass that reads a render target written by the
 * first? Every shader MuraDeck ships is single-pass, and an AA stage that has to feed the
 * sharpener needs the answer before it can be designed.
 *
 *   pass 1  swaps red and blue into PassTestTex
 *   pass 2  reads PassTestTex and cuts green by ~45%
 *
 * What the screen shows:
 *   red and blue swapped, with a magenta cast  -> both passes ran, render targets work
 *   picture unchanged                          -> pass 2 was dropped, or the target ignored
 *   black or garbage                           -> the target is bound but never written
 *   the session restarts                       -> the technique compiler rejected it
 */

#include "ReShade.fxh"

texture PassTestTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler PassTestS { Texture = PassTestTex; };

float3 SwapPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;
    return c.bgr;
}

float3 TintPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 c = tex2D(PassTestS, texcoord).rgb;
    return c * float3(1.0, 0.55, 1.0);
}

technique MuraDeckPassTest
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = SwapPass;
        RenderTarget = PassTestTex;
    }
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = TintPass;
    }
}
