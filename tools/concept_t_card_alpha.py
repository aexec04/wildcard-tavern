"""Give the Concept T Patron cards real alpha corners (the gray backdrop outside the card becomes transparent).
Reads art-wip/concept_t_patrons/ctp_*.png (backs the originals up once into art-wip/concept_t_patrons/orig/),
flood fills the light gray backdrop from the corners and edges, and rewrites each file as RGBA.
Then: python3 tools/patron_art/generate_patron_art.py -c concept_t_patrons upload   (re-uploads the changed files, rewrites ConceptTPatronArt.lua)
Usage: python3 tools/concept_t_card_alpha.py
"""
import pathlib
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

DIR = pathlib.Path(__file__).resolve().parent.parent / "art-wip" / "concept_t_patrons"
MARK = (255, 0, 255)


def cut(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    work = im.copy()
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] + [(x, 0) for x in range(0, w, 64)] + [(x, h - 1) for x in range(0, w, 64)]
    for s in seeds:
        if work.getpixel(s) != MARK and min(work.getpixel(s)) > 150 and max(work.getpixel(s)) - min(work.getpixel(s)) < 14:
            ImageDraw.floodfill(work, s, MARK, thresh=16)
    bg = (np.asarray(work) == np.array(MARK)).all(axis=2)
    alpha = Image.fromarray((~bg * 255).astype(np.uint8), "L")
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))  # shave the light fringe, soften
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out, float(bg.mean())


def main():
    orig = DIR / "orig"
    orig.mkdir(exist_ok=True)
    for p in sorted(DIR.glob("ctp_*.png")):
        if not (orig / p.name).exists():
            shutil.copy2(p, orig / p.name)
        out, frac = cut(orig / p.name)
        out.save(p)
        print("%s cleared %.1f%%" % (p.name, frac * 100))


if __name__ == "__main__":
    main()
