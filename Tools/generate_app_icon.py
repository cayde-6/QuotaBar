#!/usr/bin/env python3
"""Generate the QuotaBar app icon at every size the asset catalogue needs.

The icon is a dark rounded square holding two vertical capsule "tracks",
each with a fill indicator anchored to the bottom of its track. The fill is
drawn as a rounded rectangle on all four corners, so its top follows the
capsule instead of being cut flat.

Everything is drawn on a large supersampled canvas and downsampled with
LANCZOS. The area outside the rounded square stays fully transparent, and
pixels under it carry the background colour rather than white, so no pale
fringe appears at the corners after downscaling.

Run it after changing any geometry or colour below; it overwrites the ten
PNGs in the asset catalogue in place. Contents.json is not touched.

    python3 Tools/generate_app_icon.py

Requires Pillow and numpy:

    python3 -m pip install pillow numpy
"""

import pathlib

import numpy as np
from PIL import Image, ImageDraw

# Supersampling base size
S = 4096

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "QuotaBar" / "Assets.xcassets" / "AppIcon.appiconset"

TARGETS = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def frac(v):
    """Convert a value given in /1024 units into a fraction of S."""
    return v / 1024.0 * S


def rounded_rect_mask(size, x0, y0, x1, y1, radius):
    """Return an 'L' mode PIL image mask (0..255) with a filled rounded
    rectangle from (x0,y0) to (x1,y1) with the given corner radius,
    anti-aliased by drawing at 4x supersample and downscaling.
    """
    ss = 4
    w, h = size
    big = Image.new("L", (w * ss, h * ss), 0)
    draw = ImageDraw.Draw(big)
    draw.rounded_rectangle(
        [x0 * ss, y0 * ss, x1 * ss, y1 * ss],
        radius=radius * ss,
        fill=255,
    )
    mask = big.resize((w, h), Image.LANCZOS)
    return mask


def vertical_gradient_rgb(size, y_top, y_bottom, color_top, color_bottom):
    """Build an (H, W, 3) uint8 array with a vertical linear gradient
    between color_top and color_bottom, spanning y_top..y_bottom in pixel
    rows. Rows before y_top get color_top, rows after y_bottom get
    color_bottom (clamped).
    """
    w, h = size
    rows = np.arange(h, dtype=np.float64)
    span = max(y_bottom - y_top, 1e-6)
    t = (rows - y_top) / span
    t = np.clip(t, 0.0, 1.0)
    color_top = np.array(color_top, dtype=np.float64)
    color_bottom = np.array(color_bottom, dtype=np.float64)
    grad_rows = color_top[None, :] + (color_bottom - color_top)[None, :] * t[:, None]
    grad = np.repeat(grad_rows[:, None, :], w, axis=1)
    return grad  # (H, W, 3) float64


def composite(base_rgba, mask_L, color_rgb):
    """Alpha-composite a solid/gradient color (masked by mask_L, 0..255)
    onto base_rgba (H,W,4 float64, values 0..255), using premultiplied
    logic so no white fringing appears at edges.
    """
    h, w = mask_L.shape
    a = mask_L.astype(np.float64) / 255.0  # 0..1
    a = a[:, :, None]

    if color_rgb.ndim == 1:
        color = np.broadcast_to(color_rgb, (h, w, 3)).astype(np.float64)
    else:
        color = color_rgb

    base_rgb = base_rgba[:, :, :3]
    base_a = base_rgba[:, :, 3:4] / 255.0

    out_a = a + base_a * (1 - a)
    # premultiplied compositing avoids white fringing under transparency
    out_rgb_premult = color * a + base_rgb * base_a * (1 - a)
    with np.errstate(invalid="ignore", divide="ignore"):
        out_rgb = np.where(out_a > 1e-6, out_rgb_premult / np.maximum(out_a, 1e-6), color)

    out = np.empty_like(base_rgba)
    out[:, :, :3] = out_rgb
    out[:, :, 3:4] = out_a * 255.0
    return out


def build_icon():
    w = h = S

    # Start fully transparent; RGB filled with a neutral bg-ish color so
    # that no white ever appears under transparent pixels, even after
    # LANCZOS downscaling touches edge pixels.
    canvas = np.zeros((h, w, 4), dtype=np.float64)
    canvas[:, :, 0] = 30.0
    canvas[:, :, 1] = 30.0
    canvas[:, :, 2] = 32.0
    canvas[:, :, 3] = 0.0

    # --- Background rounded square ---
    bg_radius = frac(206)
    bg_mask = np.array(
        rounded_rect_mask((w, h), 0, 0, S, S, bg_radius), dtype=np.float64
    )
    bg_grad = vertical_gradient_rgb((w, h), 0, S, (51, 51, 53), (30, 30, 32))
    canvas = composite(canvas, bg_mask, bg_grad)

    # --- Track geometry ---
    track_w = frac(180)
    track_r = track_w / 2.0
    y0 = frac(232)
    track_h = frac(560)
    y1 = y0 + track_h

    tracks = [
        {"x0": frac(292), "fraction": 0.85, "top": (63, 224, 106), "bottom": (39, 185, 75)},
        {"x0": frac(552), "fraction": 0.45, "top": (255, 207, 62), "bottom": (224, 163, 0)},
    ]

    for t in tracks:
        x0 = t["x0"]
        x1 = x0 + track_w

        # Track (capsule) mask + gradient over the track's own height.
        track_mask = np.array(
            rounded_rect_mask((w, h), x0, y0, x1, y1, track_r), dtype=np.float64
        )
        track_grad = vertical_gradient_rgb((w, h), y0, y1, (67, 67, 69), (53, 53, 55))
        canvas = composite(canvas, track_mask, track_grad)

        # Fill indicator: rounded rect on all four corners, bottom aligned
        # to track bottom, radius limited so it doesn't degenerate for
        # small fractions.
        fill_h = track_h * t["fraction"]
        fill_top = y1 - fill_h
        fill_r = min(track_r, fill_h / 2.0)

        fill_mask = np.array(
            rounded_rect_mask((w, h), x0, fill_top, x1, y1, fill_r), dtype=np.float64
        )
        # Constrain fill to stay within the track.
        fill_mask = np.minimum(fill_mask, track_mask)

        fill_grad = vertical_gradient_rgb(
            (w, h), fill_top, y1, t["top"], t["bottom"]
        )
        canvas = composite(canvas, fill_mask, fill_grad)

    canvas = np.clip(canvas, 0, 255).astype(np.uint8)
    img = Image.fromarray(canvas, mode="RGBA")
    return img


def clean_alpha_ringing(img, threshold=2):
    """Snap near-zero alpha down to exactly zero.

    Downsampling 4096 -> 32 is a 128x reduction, and LANCZOS rings slightly
    past the true edge, leaving stray pixels at alpha 1/255 in corners that
    should be fully transparent. Anything at or below `threshold` is that
    artefact, not coverage: the real antialiased edge spans a far wider
    alpha ramp and is untouched.
    """
    arr = np.array(img)
    a = arr[:, :, 3]
    a[a <= threshold] = 0
    arr[:, :, 3] = a
    return Image.fromarray(arr, mode="RGBA")


def main():
    big = build_icon()
    for filename, size in TARGETS:
        out = big.resize((size, size), Image.LANCZOS)
        out = clean_alpha_ringing(out)
        path = OUT_DIR / filename
        out.save(path)
        print(f"wrote {path} ({size}x{size})")


if __name__ == "__main__":
    main()
