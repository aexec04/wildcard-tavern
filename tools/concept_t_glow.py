"""Procedural soft gold glow ring for the Concept T scoring stage (no generation, no spend).
Writes art-wip/concept_t/ct_glow_ring.png: a wide ellipse (3:1), soft warm gold radial glow (brightest at the centre), transparent edges.
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
    # soft radial glow: bright warm centre fading smoothly to nothing, no dark fill and no hard ring edge
    core = np.exp(-(r / 0.55) ** 2)
    a = np.clip(core * 0.8, 0, 1) * np.clip((1 - r) / 0.35, 0, 1)
    rgb = np.zeros((H, W, 3), dtype=np.float32)
    rgb[..., 0], rgb[..., 1], rgb[..., 2] = 255, 205 + 40 * core, 90 + 110 * core
    out = np.dstack([rgb, a * 255]).clip(0, 255).astype(np.uint8)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
