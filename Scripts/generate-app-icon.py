#!/usr/bin/env python3
"""Regenerate AppIcon PNG master, iconset, and .icns from the radar design."""

from __future__ import annotations

import math
import os
import subprocess
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("Pillow required: python3 -m pip install --user Pillow", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "Resources", "Icon")

TEAL = (15, 107, 99)
MINT = (61, 190, 175)
CHAR = (28, 29, 31)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base = Image.new("RGB", (size, size))
    px = base.load()
    for y in range(size):
        for x in range(size):
            t = (0.35 * x + 0.65 * (size - 1 - y)) / (size - 1)
            t = max(0.0, min(1.0, t))
            c = lerp(CHAR, TEAL, 0.25 + 0.75 * t)
            dx = (x - size / 2) / (size / 2)
            dy = (y - size / 2) / (size / 2)
            v = 1 - 0.12 * (dx * dx + dy * dy)
            c = tuple(max(0, min(255, int(c[i] * v))) for i in range(3))
            px[x, y] = c
    base = base.filter(ImageFilter.GaussianBlur(radius=max(1, size // 256)))
    radius = int(size * 0.223)
    margin = max(1, int(size * 0.01))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, size - 1 - margin, size - 1 - margin],
        radius=radius,
        fill=255,
    )
    plate = base.convert("RGBA")
    plate.putalpha(mask)
    img = Image.alpha_composite(img, plate)

    cx = cy = size / 2.0
    for scale, width_frac, alpha in [
        (0.20, 0.016, 130),
        (0.32, 0.020, 180),
        (0.44, 0.024, 230),
    ]:
        rad = size * scale
        w = max(1, int(size * width_frac))
        overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        bbox = [cx - rad, cy - rad, cx + rad, cy + rad]
        od.arc(bbox, start=205, end=495, fill=(*MINT, alpha), width=w)
        img = Image.alpha_composite(img, overlay)

    draw = ImageDraw.Draw(img)
    r0 = max(2, int(size * 0.052))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gr = int(r0 * 2.4)
    gd.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=(*MINT, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(1, size // 48)))
    img = Image.alpha_composite(glow, img)
    draw = ImageDraw.Draw(img)
    draw.ellipse([cx - r0, cy - r0, cx + r0, cy + r0], fill=(*MINT, 255))
    hr = max(1, int(r0 * 0.35))
    draw.ellipse(
        [cx - hr - r0 * 0.15, cy - hr - r0 * 0.2, cx + hr - r0 * 0.15, cy + hr - r0 * 0.2],
        fill=(220, 255, 250, 160),
    )

    angle = math.radians(-32)
    orad = size * 0.44
    nx = cx + orad * math.cos(angle)
    ny = cy + orad * math.sin(angle)
    r1 = max(2, int(size * 0.036))
    draw.line(
        [
            (cx + (r0 + 1) * math.cos(angle), cy + (r0 + 1) * math.sin(angle)),
            (nx - r1 * math.cos(angle), ny - r1 * math.sin(angle)),
        ],
        fill=(*MINT, 210),
        width=max(1, int(size * 0.011)),
    )
    draw.ellipse([nx - r1, ny - r1, nx + r1, ny + r1], fill=(*WHITE, 255))
    rin = r1 * 0.62
    draw.ellipse([nx - rin, ny - rin, nx + rin, ny + rin], fill=(*MINT, 255))
    return img


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    master = render(1024)
    master_path = os.path.join(OUT, "AppIcon-1024.png")
    master.save(master_path, format="PNG")

    iconset = os.path.join(OUT, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for f in os.listdir(iconset):
        os.remove(os.path.join(iconset, f))

    # Construct retina suffix at runtime (avoids tooling that mangles "@2x" literals).
    retina = "@" + "2x.png"
    entries = [
        ("icon_16x16.png", 16),
        ("icon_16x16" + retina, 32),
        ("icon_32x32.png", 32),
        ("icon_32x32" + retina, 64),
        ("icon_128x128.png", 128),
        ("icon_128x128" + retina, 256),
        ("icon_256x256.png", 256),
        ("icon_256x256" + retina, 512),
        ("icon_512x512.png", 512),
        ("icon_512x512" + retina, 1024),
    ]
    for fname, size in entries:
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            os.path.join(iconset, fname), format="PNG"
        )

    icns = os.path.join(OUT, "AppIcon.icns")
    subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", icns])
    print("Wrote", master_path)
    print("Wrote", icns)


if __name__ == "__main__":
    main()
