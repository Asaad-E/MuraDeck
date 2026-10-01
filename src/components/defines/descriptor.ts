import { IconType } from "react-icons";
import { FaTabletAlt, FaFirstdraft, FaFlipboard, FaBarcode, FaCuttlefish, FaBraille, FaThLarge, FaDrawPolygon } from "react-icons/fa";

export type EffectKey = 'mura' | 'monitor' | 'brightness' | 'grain' | 'lgg' | 'aspectfix' | 'cas' | 'cas_slider' | 'pixelate' | 'pixelate_slider' | 'fxaa' | 'deband' | 'muraresponse' | 'murastrength' | 'lumaonly' | 'loading';

export interface EffectMeta {
  title: string;
  desc: string;
  icon: IconType;
}

export const Desc: Record<EffectKey, EffectMeta> = {
  mura: {
    title: "Adaptive Mura Correction",
    desc: "Preserve black pixel, automatic HDR/SDR detection, and adaptive brightness correction.",
    icon: FaBraille,
  },
  monitor: {
    title: "Respect External Monitor",
    desc: "Automatically turn the plugin on/off, when external monitor detected. Disable it if you want to fully deactivate the plugin",
    icon: FaTabletAlt,
  },
  brightness: {
    title: "Brightness Adaptation",
    desc: "Automatically adapt mura map correction based on current brightness",
    icon: FaBarcode,
  },
  grain: {
    title: "Dithering",
    desc: "Smooth out fading effects by using small amount of film grain on dark areas. Disable it if you find distracting",
    icon: FaFirstdraft,
  },
  muraresponse: {
    title: "Mura Response",
    desc: "How the correction follows the picture. A panel's mura tracks how hard each pixel is driven, so at 1 the correction scales with the pixel's own level — which keeps it out of the shadows, where a flat offset was a huge relative change and showed up as coloured noise on dark greys and blues. At 0 it goes back to a flat offset. Real panels sit somewhere between, so trust your eyes over the default.",
    icon: FaBarcode,
  },
  murastrength: {
    title: "Mura Strength",
    desc: "Scales the mura correction on top of the value Brightness Adaptation picks for the current brightness, so it keeps adapting. 1 is the tuned strength; lower if mura looks overcorrected, higher if it still shows.",
    icon: FaBarcode,
  },
  lumaonly: {
    title: "Sharpen Luminance Only",
    desc: "Sharpens brightness and leaves colour alone. Sharpening each colour channel separately also sharpens whatever colour noise sits in them and can put thin colour fringes on coloured edges; this keeps the edge contrast without either.",
    icon: FaCuttlefish,
  },
  lgg: {
    title: "Gamma Correction",
    desc: "Fix Samsung panel raised gamma by reducing lift and gamma only on dark areas. Disable it if you find it's too dark",
    icon: FaFlipboard,
  },
  aspectfix: {
    title: "Aspect ratio fix",
    desc: "By default mura map will be designed to be works with 16:xx ratio. Enabling this will adapt game ratios, for example 1:1 games",
    icon: FaFlipboard,
  },
  cas: {
    title: "AMD RCAS",
    desc: "AMD's Robust Contrast Adaptive Sharpening, the sharpening pass of FSR 1.0. It is the one built for sharpening a frame that has already been scaled, which is what gamescope hands us, and it backs off where the local detail looks like noise rather than an edge",
    icon: FaCuttlefish,
  },
  cas_slider: {
    title: "Sharpness",
    desc: "0 is gentle, 1 is the most AMD considers natural. Mapped onto RCAS sharpness stops",
    icon: FaCuttlefish,
  },
  pixelate: {
    title: "Pixel Art Mode",
    desc: "Recreates a crisp, blocky pixel-art look on top of the (always LINEAR) system scaling — for fullscreen pixel-art games and old visual novels where Linear looks blurry and Nearest/Pixel isn't usable with reshade active.",
    icon: FaThLarge,
  },
  fxaa: {
    title: "Anti-Aliasing (FXAA)",
    desc: "Smooths jagged edges on games that have no anti-aliasing of their own. On a game that already has it, this only softens the picture, and it also softens 1px lines and small text a little. Only edges are touched, and it is switched off while Pixel Art mode is on. Costs a few extra texture reads on edge pixels, so it is off by default.",
    icon: FaDrawPolygon,
  },
  deband: {
    title: "Debanding",
    desc: "Smooths the visible steps in gradients, most noticeable as bands in dark fades on an OLED. It averages across each step to recover the gradient and then dithers it back into 8 bits, so it adds a very fine noise. Works on SDR games only; HDR has the range it needs. It helps most on shallow dark fades, where it roughly halves the banding; elsewhere the effect is small. It reads eight extra pixels per pixel, so it is off by default.",
    icon: FaBarcode,
  },
  pixelate_slider: {
    title: "Block Size",
    desc: "Size of each recreated pixel block, in screen pixels. Tune to match the game's native resolution scale.",
    icon: FaThLarge,
  },
  loading: {
    title: "Processing...",
    desc: "Please wait...",
    icon: FaCuttlefish,
  },
};
