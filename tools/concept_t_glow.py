"""Procedural soft gold glow ring for the Concept T scoring stage (no generation, no spend).
Writes art-wip/concept_t/ct_glow_ring.png: a wide ellipse (3:1) with a soft warm haze and a thin bright ring, transparent edges.
Usage: python3 tools/concept_t_glow.py
"""
import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "art-wip" / "concept_t" / "ct_glow_ring.png"
W, H = 768, 256


def main():
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    haze = np.clip(1 - r, 0, 1) ** 1.6 * 0.55
    ring = np.exp(-((r - 0.78) / 0.05) ** 2) * 0.85
    a = np.clip(haze + ring, 0, 1) * np.clip((1 - r) / 0.12, 0, 1)
    rgb = np.zeros((H, W, 3), dtype=np.float32)
    rgb[..., 0], rgb[..., 1], rgb[..., 2] = 255, 200 + 40 * ring, 80 + 100 * ring
    out = np.dstack([rgb, a * 255]).clip(0, 255).astype(np.uint8)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
