"""Cut the five reference Patron cards (claude/reference/concept_t/patron_*.png, never edited) with real alpha corners.
Writes art-wip/concept_t/ct_ref_patron_1..5.png in the order of the reference (Court Jester, Generous King, Arcane Sage,
Alchemy Adept, Royal Cat). They are used by the Studio reference scene ONLY, so the scene can match the reference.
Then: python3 tools/patron_art/generate_patron_art.py -c concept_t upload   (uploads the new ones, rewrites ConceptTArt.lua)
Usage: python3 tools/concept_t_ref_patrons.py
"""
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
REF = ROOT / "claude" / "reference" / "concept_t"
OUT = ROOT / "art-wip" / "concept_t"
ORDER = ["court_jester", "generous_king", "arcane_sage", "alchemy_adept", "royal_cat"]
SS = 4
INSET = 1
RADIUS = 13


def cut(src):
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    m = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (INSET * SS, INSET * SS, (w - INSET) * SS - 1, (h - INSET) * SS - 1), radius=RADIUS * SS, fill=255)
    im.putalpha(m.resize((w, h), Image.LANCZOS))
    return im


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, name in enumerate(ORDER, 1):
        cut(REF / ("patron_%s.png" % name)).save(OUT / ("ct_ref_patron_%d.png" % i))
        print("ct_ref_patron_%d from patron_%s.png" % (i, name))


if __name__ == "__main__":
    main()
