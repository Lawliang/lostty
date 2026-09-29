"""Recolor Ghostty's blue icon screen into a hologram-pink gradient.

Brightness and alpha are kept from the original pixel; only hue changes,
sweeping violet -> magenta -> hot pink with a slight diagonal shimmer.
"""
import colorsys
import sys

import numpy as np
from PIL import Image


def recolor_screen(src, dst):
    img = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255
    h, w = img.shape[:2]
    rgb, alpha = img[..., :3], img[..., 3:]
    value = rgb.max(axis=2, keepdims=True)  # original brightness

    ys, xs = np.mgrid[0:h, 0:w]
    t = (ys / (h - 1)) * 0.8 + (xs / (w - 1)) * 0.2  # diagonal sweep
    # Hue stops (degrees): violet 292 -> magenta 318 -> hot pink 335.
    hue = np.interp(t, [0.0, 0.5, 1.0], [292, 318, 335]) / 360
    shimmer = 0.015 * np.sin((xs + ys) / w * 2 * np.pi)
    hue = (hue + shimmer) % 1.0
    sat = np.full_like(hue, 0.85)

    to_rgb = np.vectorize(colorsys.hsv_to_rgb)
    r, g, b = to_rgb(hue, sat, np.ones_like(hue))
    tint = np.stack([r, g, b], axis=2)
    out = np.concatenate([tint * value, alpha], axis=2)
    Image.fromarray((out * 255).round().astype(np.uint8), "RGBA").save(dst)


def recolor_rendered_icon(src, dst):
    """For flattened PNG fallbacks: shift only blue-dominant pixels to pink."""
    img = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255
    r, g, b, a = (img[..., i] for i in range(4))
    blueish = (b > r + 0.08) & (b > g + 0.08)
    value = np.maximum(np.maximum(r, g), b)
    ys, xs = np.mgrid[0:img.shape[0], 0:img.shape[1]]
    t = ys / (img.shape[0] - 1)
    hue = np.interp(t, [0.0, 0.5, 1.0], [292, 318, 335]) / 360
    sat = 0.85 * np.clip((b - np.minimum(r, g)) / np.maximum(b, 1e-6), 0, 1)
    to_rgb = np.vectorize(colorsys.hsv_to_rgb)
    nr, ng, nb = to_rgb(hue, sat, value)
    out = img.copy()
    for i, ch in enumerate((nr, ng, nb)):
        out[..., i] = np.where(blueish, ch, img[..., i])
    Image.fromarray((out * 255).round().astype(np.uint8), "RGBA").save(dst)


if __name__ == "__main__":
    mode, src, dst = sys.argv[1:4]
    {"screen": recolor_screen, "flat": recolor_rendered_icon}[mode](src, dst)
