import { IconType } from "react-icons";
import { FaTabletAlt, FaFirstdraft, FaFlipboard, FaBarcode, FaCuttlefish, FaBraille, FaThLarge } from "react-icons/fa";

export type EffectKey = 'mura' | 'monitor' | 'brightness' | 'grain' | 'lgg' | 'aspectfix' | 'cas' | 'cas_slider' | 'pixelate' | 'pixelate_slider' | 'shadowguard' | 'loading';

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
  shadowguard: {
    title: "Shadow Guard",
    desc: "Holds mura correction back in dark areas. The mura map is a fixed offset, so on a near-black pixel it is a huge relative change — and since only red and green have maps, it shows up as coloured noise on dark greys and blues. Raise this if shadows look noisy; lower it if mura is visible in dark scenes.",
    icon: FaBarcode,
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
