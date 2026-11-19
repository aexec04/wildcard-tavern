"""Adds the concept_t_faces prompts (52 card faces) to tools/patron_art/prompts.json and cuts the style references
from claude/reference/concept_t/full_reference.png into art-wip/concept_t_faces/. Safe to rerun."""
import json, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PJ = os.path.join(ROOT, "tools", "patron_art", "prompts.json")
OUT = os.path.join(ROOT, "art-wip", "concept_t_faces")
os.makedirs(OUT, exist_ok=True)

# reference crops from the 1536x1024 reference (fractions of the frame): ace, king, queen, nine, six
im = Image.open(os.path.join(ROOT, "claude", "reference", "concept_t", "full_reference.png")).convert("RGB")
W, H = im.size
hx0, hy0 = int(.19 * W), int(.66 * H)  # the hand crop origin used when measuring
for name, (x0, y0, x1, y1) in {"ref_ace": (8, 38, 162, 255), "ref_king": (132, 25, 278, 222), "ref_queen": (258, 18, 408, 222),
                               "ref_nine": (402, 18, 532, 222), "ref_six": (632, 28, 782, 230)}.items():
    im.crop((hx0 + x0, hy0 + y0, hx0 + x1, hy0 + y1)).save(os.path.join(OUT, name + ".png"))

SUITS = {"spades": ("black", "spade"), "hearts": ("red", "heart"), "diamonds": ("red", "diamond"), "clubs": ("black", "club")}
RANKS = ["a", "2", "3", "4", "5", "6", "7", "8", "9", "10", "j", "q", "k"]
WORD = {"a": "A", "j": "J", "q": "Q", "k": "K"}
PIPS = {
    "a": "one single very large pip in the exact centre",
    "2": "two big pips, one at the top centre and one at the bottom centre (the bottom one upside down)",
    "3": "three big pips in a vertical line down the centre (the bottom one upside down)",
    "4": "four big pips, two in the upper corners and two in the lower corners of the pip area (the lower two upside down)",
    "5": "five big pips: four in the corners of the pip area and one in the centre",
    "6": "six big pips in two columns of three (the lower three upside down)",
    "7": "seven big pips: two columns of three plus one in the centre between the top and middle rows",
    "8": "exactly EIGHT big pips and not nine: a left column of three, a right column of three, and two pips in the centre column (one in the upper half and one in the lower half), with nothing at the exact middle of the card",
    "9": "nine big pips: two columns of four plus one in the exact centre",
    "10": "ten big pips: two columns of four plus two in the centre column, one above the middle and one below it",
}
COURT = {
    "k": ("a kind king with a gold crown", "ref_king"),
    "q": ("a kind queen with a gold crown", "ref_queen"),
    "j": ("a cheerful young jack in a feathered cap", "ref_king"),
}
STYLE = ("Edit the reference image: it is one hand-painted playing card of a blocky Roblox tavern game. Keep EXACTLY the same card: "
         "aged warm parchment face with paper grain, a thin darker rim line, thin dark outline, rounded corners, hand-painted blocky look, "
         "large bold rank letter or number with a small suit symbol under it in the top-left corner and the same pair rotated upside down in the "
         "bottom-right corner, and change ONLY the rank, the suit and the middle as described. The rank text must be spelled exactly as given and "
         "no other letters, numbers or words may appear anywhere. The card stands straight and front facing, filling the image with a small margin, "
         "on a flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, no perspective. "
         "Bright, kind, kid-friendly original art")

subjects, refs = {}, {}
for suit, (colour, sym) in SUITS.items():
    for r in RANKS:
        pid = f"{r}_{suit}"
        label = WORD.get(r, r)
        head = (f"the {label} of {suit}: the corner rank is the {'letter' if r in WORD else 'number'} \"{label}\" in {colour} ink with a small {colour} {sym} "
                f"symbol under it, ")
        if r in COURT:
            desc, ref = COURT[r]
            subjects[pid] = head + (f"and the middle shows a big painted blocky Roblox figure of {desc}, half-length, in {colour} and gold clothes, "
                                    f"a different friendly face for every suit, filling about 60 percent of the card face, with no pips")
            refs[pid] = ref
        else:
            subjects[pid] = head + f"and the middle shows {PIPS[r]}, every pip a bold painted {colour} {sym}"
            refs[pid] = "ref_ace" if r == "a" else ("ref_six" if r in ("6", "7", "8") else "ref_nine")

d = json.load(open(PJ))
d["ctf_style"] = STYLE
d["ctf_subjects"] = subjects
d["ctf_refs"] = refs
json.dump(d, open(PJ, "w"), indent=2, ensure_ascii=False)
print(len(subjects), "face prompts written")
