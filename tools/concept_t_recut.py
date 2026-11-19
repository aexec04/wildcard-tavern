"""Re-cut Concept T pieces with real alpha (no dark rectangle corners) and blank the baked text out of the effect pills.

Reads claude/reference/concept_t/ (never edits it) and writes new files beside the originals in art-wip/concept_t/:
  ct_btn_play_a.png, ct_btn_discard_a.png, ct_deck_a.png  (cut from full_reference.png through a rounded rect or polygon mask)
  ct_pill_<green|blue|purple|gold>_blank.png               (the cut pill with its number painted out)
Usage: python3 tools/concept_t_recut.py
"""
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
REF = ROOT / "claude" / "reference" / "concept_t"
OUT = ROOT / "art-wip" / "concept_t"
SS = 4  # supersample for smooth mask edges


def mask_rrect(size, box, radius):
    m = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    x0, y0, x1, y1 = [v * SS for v in box]
    ImageDraw.Draw(m).rounded_rectangle((x0, y0, x1, y1), radius=radius * SS, fill=255)
    return m.resize(size, Image.LANCZOS)


def mask_poly(size, pts):
    m = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    ImageDraw.Draw(m).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return m.resize(size, Image.LANCZOS)


def erode(mask, px):
    return mask.filter(ImageFilter.MinFilter(px * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))


def cut(ref, box, mask_fn, inset):
    """box = (x0, y0, x1, y1) in the reference; the mask is built in the box's own coordinates."""
    im = ref.crop(box).convert("RGBA")
    m = erode(mask_fn(im.size), inset)
    im.putalpha(m)
    return im


def blank_pill(name):
    im = Image.open(REF / ("pill_%s.png" % name)).convert("RGBA")
    a = np.asarray(im, dtype=np.float32)
    h, w = a.shape[:2]
    x0, x1 = int(w * 0.21), int(w * 0.79)
    y0, y1 = int(h * 0.20), int(h * 0.80)
    left = a[y0:y1, x0 - 4:x0 - 1].mean(axis=1)   # (rows, 4)
    right = a[y0:y1, x1 + 1:x1 + 4].mean(axis=1)
    for x in range(x0, x1):
        t = (x - x0) / float(max(1, x1 - x0 - 1))
        a[y0:y1, x] = left * (1 - t) + right * t
    out = Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")
    out = out.filter(ImageFilter.GaussianBlur(0.4))
    # the cut kept a dark rectangle behind the pill: use a stadium alpha instead
    out.putalpha(erode(mask_rrect(out.size, (0, 0, w - 1, h - 1), h // 2 - 1), 1))
    return out


def main():
    ref = Image.open(REF / "full_reference.png").convert("RGB")
    OUT.mkdir(parents=True, exist_ok=True)
    play = cut(ref, (463, 895, 808, 1011), lambda s: mask_rrect(s, (0, 0, s[0] - 1, s[1] - 1), 30), 2)
    play.save(OUT / "ct_btn_play_a.png")
    disc = cut(ref, (823, 904, 1055, 1009), lambda s: mask_rrect(s, (0, 0, s[0] - 1, s[1] - 1), 28), 2)
    disc.save(OUT / "ct_btn_discard_a.png")
    ox, oy = 1213, 645  # deck crop origin = the probe origin; polygon points are half of the 2x probe pixels
    pts = [(90, 50), (408, 46), (570, 396), (566, 430), (540, 470), (190, 502), (168, 490), (52, 140)]
    box = (ox, oy, ox + 307, oy + 317)
    deck = cut(ref, box, lambda s: mask_poly(s, [(x / 2.0, y / 2.0) for x, y in pts]), 1)
    deck.save(OUT / "ct_deck_a.png")
    for n in ("green", "blue", "purple", "gold"):
        blank_pill(n).save(OUT / ("ct_pill_%s_blank.png" % n))
    print("wrote", sorted(p.name for p in OUT.glob("*_a.png")), sorted(p.name for p in OUT.glob("*_blank.png")))


if __name__ == "__main__":
    main()
