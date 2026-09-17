# Project Brief

MuraDeck is a [Decky Loader](https://decky.xyz) plugin for the Steam Deck OLED that mitigates the "Mura effect"
(gray-uniformity noise) and raised gamma found on defective Samsung-panel OLED units. It layers three ReShade
effects — a per-device mura correction map, dithering (film grain), and lift/gamma correction — on top of
gamescope, and switches between SDR/HDR10PQ/HDRscRGB shader variants automatically based on what's running.

Design philosophy (from README/CONTRIBUTION): "install it and forget it" — minimal UI, everything reacts
automatically to brightness, HDR mode, game focus, and monitor changes, with manual overrides available per toggle.
Also bundles an unrelated-but-convenient AMD CAS (sharpening) implementation, global or per-game.

Target user: Steam Deck OLED owners with a known-defective Samsung panel. Not intended for LE (LG panel) models.

Repo: https://github.com/Moonveil-Kanata/MuraDeck — GPLv3.
