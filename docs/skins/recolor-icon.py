"""Recolor Ghostty's icon layers into Lostty's neon-pink look.

Usage: python3 docs/skins/recolor-icon.py <mode> <src> <dst>

Modes (run each against the *upstream* layer, not an already recolored one):
  screen  images/Ghostty.icon/Assets/Screen.png — vertical gradient from light
          neon pink (top) to hot pink (bottom); the original only supplies the
          rounded-rect alpha mask.
  bevel   images/Ghostty.icon/Assets/Inner Bevel 6px.png — tints the dark
          bevel deep magenta, keeping its shading.
  ghost   images/Ghostty.icon/Assets/Ghostty.png — turns the light-blue ghost
          pale neon pink; dark pixels (the prompt glyphs) keep their shade.

The frame colour lives in images/Ghostty.icon/icon.json (top-level "fill"),
and the flat fallback PNGs in macos/Assets.xcassets/AppIconImage.imageset are
exported from the built app's rendered icon rather than recolored here.
"""
import sys

import numpy as np
from PIL import Image

# Screen gradient stops (sRGB 0-1): top light neon pink -> bottom hot pink.
SCREEN_TOP = np.array([1.00, 0.46, 0.80])
SCREEN_MID = np.array([1.00, 0.36, 0.74])
SCREEN_BOTTOM = np.array([0.93, 0.16, 0.66])

# Bevel tint: deep magenta, scaled by the bevel's original brightness.
BEVEL_TINT = np.array([0.55, 0.08, 0.40])


def load(src):
    return np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255


def save(pixels, dst):
    Image.fromarray((np.clip(pixels, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(dst)


def recolor_screen(src, dst):
    img = load(src)
    h = img.shape[0]
    t = np.linspace(0.0, 1.0, h)[:, None, None]
    upper = SCREEN_TOP + (SCREEN_MID - SCREEN_TOP) * np.clip(t * 2, 0, 1)
    color = np.where(t < 0.5, upper, SCREEN_MID + (SCREEN_BOTTOM - SCREEN_MID) * np.clip(t * 2 - 1, 0, 1))
    color = np.broadcast_to(color, img.shape[:2] + (3,))
    save(np.concatenate([color, img[..., 3:]], axis=2), dst)


def recolor_bevel(src, dst):
    img = load(src)
    value = img[..., :3].max(axis=2, keepdims=True)
    # Lift dark greys into the tint while keeping highlights' relative shading.
    tinted = BEVEL_TINT * (0.6 + 0.4 * value / max(value.max(), 1e-6))
    save(np.concatenate([tinted, img[..., 3:]], axis=2), dst)


# Ghost tint: pale neon pink, scaled by each pixel's original brightness.
GHOST_TINT = np.array([1.00, 0.80, 0.95])


def recolor_ghost(src, dst):
    img = load(src)
    value = img[..., :3].max(axis=2, keepdims=True)
    save(np.concatenate([GHOST_TINT * value, img[..., 3:]], axis=2), dst)


if __name__ == "__main__":
    mode, src, dst = sys.argv[1:4]
    {"screen": recolor_screen, "bevel": recolor_bevel, "ghost": recolor_ghost}[mode](src, dst)
