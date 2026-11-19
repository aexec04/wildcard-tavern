"""Second alpha cut for the Concept T Patron cards: the first cut (concept_t_card_alpha.py) seeded the gray backdrop only
from the corners and the top and bottom edges, so a gray strip about 12 px wide stayed opaque down the left and right
sides (the "grey frame" around filled Patron seats). This one also seeds every 32 px down both side edges.
Reads the untouched RGB cards in art-wip/concept_t_patrons/orig_v2/ and rewrites art-wip/concept_t_patrons/ctp_*.png.
Then: python3 tools/patron_art/generate_patron_art.py -c concept_t_patrons upload
Usage: python3 tools/concept_t_card_alpha_edges.py
"""
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

DIR = pathlib.Path(__file__).resolve().parent.parent / "art-wip" / "concept_t_patrons"
MARK = (255, 0, 255)


def is_backdrop(px):
    return px != MARK and min(px) > 150 and max(px) - min(px) < 14


def cut(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    work = im.copy()
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    seeds += [(x, 0) for x in range(0, w, 32)] + [(x, h - 1) for x in range(0, w, 32)]
    seeds += [(0, y) for y in range(0, h, 32)] + [(w - 1, y) for y in range(0, h, 32)]
    for s in seeds:
        if is_backdrop(work.getpixel(s)):
            ImageDraw.floodfill(work, s, MARK, thresh=16)
    bg = (np.asarray(work) == np.array(MARK)).all(axis=2)
    alpha = Image.fromarray((~bg * 255).astype(np.uint8), "L")
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out, float(bg.mean())


def main():
    src = DIR / "orig_v2"
    for p in sorted(src.glob("ctp_*.png")):
        out, frac = cut(p)
        a = out.split()[3]
        w, h = out.size
        edge = max(a.getpixel((3, h // 2)), a.getpixel((w - 4, h // 2)))
        out.save(DIR / p.name)
        print("%s cleared %.1f%% side strip alpha %d" % (p.name, frac * 100, edge))


if __name__ == "__main__":
    main()
