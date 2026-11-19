"""Procedural gold glow plate for the Concept T scoring stage (no generation, no spend).
Writes art-wip/concept_t/ct_glow_ring.png (3:1, transparent): a warm gold radial glow, a thin bright elliptical rim in the lower
half (like the reference ring under the total), and a few 4-point sparkles. No text, no dark fill.
Usage: python3 tools/concept_t_glow.py     then  python3 tools/patron_art/generate_patron_art.py -c concept_t upload
"""
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "art-wip" / "concept_t" / "ct_glow_ring.png"
W, H = 1024, 340


def main():
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    cx, cy = W / 2, H * 0.50
    r = np.sqrt(((x - cx) / (W * 0.5)) ** 2 + ((y - cy) / (H * 0.5)) ** 2)
    core = np.exp(-(r / 0.62) ** 2)
    a = np.clip(core * 0.75, 0, 1) * np.clip((1 - r) / 0.30, 0, 1)
    rgb = np.zeros((H, W, 3), dtype=np.float32)
    rgb[..., 0], rgb[..., 1], rgb[..., 2] = 255, 200 + 45 * core, 80 + 110 * core
    glow = Image.fromarray(np.dstack([rgb, a * 255]).clip(0, 255).astype(np.uint8), "RGBA")

    # thin bright rim: an ellipse 76 percent of the width, centred a little low, soft halo plus a crisp core line
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(rim)
    rw, rh = W * 0.38, H * 0.33
    rcx, rcy = W / 2, H * 0.66
    box = (rcx - rw, rcy - rh, rcx + rw, rcy + rh)
    d.ellipse(box, outline=(255, 214, 110, 255), width=7)
    halo = rim.filter(ImageFilter.GaussianBlur(9))
    d.ellipse(box, outline=(255, 244, 190, 255), width=3)

    # sparkles
    sp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sp)
    for sx, sy, s in [(0.12, 0.30, 26), (0.88, 0.34, 20), (0.30, 0.78, 12), (0.72, 0.80, 14),
                      (0.20, 0.62, 9), (0.80, 0.58, 10), (0.60, 0.12, 12), (0.40, 0.10, 9)]:
        px, py = sx * W, sy * H
        sd.polygon([(px, py - s), (px + s * 0.18, py - s * 0.18), (px + s, py), (px + s * 0.18, py + s * 0.18),
                    (px, py + s), (px - s * 0.18, py + s * 0.18), (px - s, py), (px - s * 0.18, py - s * 0.18)],
                   fill=(255, 240, 180, 255))
    out = Image.alpha_composite(Image.alpha_composite(Image.alpha_composite(glow, halo), rim), sp)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    print("wrote", OUT, out.size)


if __name__ == "__main__":
    main()
