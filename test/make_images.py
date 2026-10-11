"""Draws the radial's ring images into graphics/ (white: tinted in game). python test/make_images.py
512 px squares centred on (256, 256), outer radius 250, inner 150: the ring, its outline, and per slice count N
(1..32) one slice centred at the top, for each gap (sector-<gap>-<N>.png), turned into place in game; and glow.png
(128 px), the soft light behind an icon."""
import math
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "graphics" / "ring"
S, K = 512, 4  # size, supersampling
R_OUT, R_IN = 250, 150
GAPS = {"none": 0.0, "small": 2.5, "large": 6.0}
MAX = 32


def canvas():
    return Image.new("L", (S * K, S * K), 0)


def save(mask, name):
    m = mask.resize((S, S), Image.LANCZOS)
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    img.putalpha(m)
    img.save(OUT / name, optimize=True)


def sector(span, gap):
    m = canvas()
    d = ImageDraw.Draw(m)
    c = S * K / 2
    a0, a1 = -90 - span / 2 + gap / 2, -90 + span / 2 - gap / 2
    pts = []
    steps = max(8, int((a1 - a0) / 2))
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        pts.append((c + R_OUT * K * math.cos(a), c + R_OUT * K * math.sin(a)))
    for k in range(steps + 1):
        a = math.radians(a1 - (a1 - a0) * k / steps)
        pts.append((c + R_IN * K * math.cos(a), c + R_IN * K * math.sin(a)))
    d.polygon(pts, fill=255)
    return m


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    c = S * K / 2
    m = canvas()
    d = ImageDraw.Draw(m)
    d.ellipse([c - R_OUT * K, c - R_OUT * K, c + R_OUT * K, c + R_OUT * K], fill=255)
    d.ellipse([c - R_IN * K, c - R_IN * K, c + R_IN * K, c + R_IN * K], fill=0)
    save(m, "ring.png")
    m = canvas()
    d = ImageDraw.Draw(m)
    w = 3 * K
    for r in (R_OUT, R_IN):
        d.ellipse([c - r * K, c - r * K, c + r * K, c + r * K], outline=255, width=w)
    save(m, "outline.png")
    for gname, gap in GAPS.items():
        for n in range(1, MAX + 1):
            save(sector(360 / n, gap if n > 1 else 0), f"sector-{gname}-{n}.png")
    # the white glow behind an icon: a soft disc, full at the middle, gone at the edge
    g = Image.new("L", (128, 128), 0)
    px = g.load()
    for y in range(128):
        for x in range(128):
            d = math.hypot(x - 63.5, y - 63.5) / 64
            px[x, y] = int(255 * min(1.0, 1.6 * max(0.0, 1 - d)) ** 1.2)
    img = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
    img.putalpha(g)
    img.save(OUT / "glow.png", optimize=True)
    print("wrote", len(list(OUT.glob("*.png"))), "images to", OUT)


main()
