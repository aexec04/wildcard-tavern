#!/usr/bin/env python3
"""One-off: add whole-picture HUD plates (pk_w_*) to the painted_kit category.
Each is a COMPLETE finished plate at its display aspect, not nine-sliced. No API calls."""
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
P = HERE / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
MAG = ", on a flat solid pure magenta #FF00FF background with no gradient, clean sharp edges, the single piece centred with generous margin all round"
ORN = ("dark brown carved wood fill, a thick two-tone gold beveled border with scrolled gold filigree corner ornaments and small gold studs, "
       "painterly candlelit game UI exactly like the Target and Tips plates in the reference image, completely blank flat centre, no letters, no numbers, no icons")
new = {
    "pk_w_target": "ONE complete finished plate, very wide and short (about 3.5 times as wide as tall), like the Target: 130 plate in the reference, " + ORN + MAG,
    "pk_w_scroll": ("ONE complete finished cream parchment scroll plate, very wide and short (about 4.8 times as wide as tall), like the Short Notice plate in the reference: "
                    "aged cream paper with torn curled edges, a small rolled scroll icon with a red wax seal at the far left, the rest blank cream paper for dark ink text, no letters, no numbers") + MAG,
    "pk_w_score": ("ONE complete finished Score plate like the one in the reference: wide (about 3.5 times as wide as tall), dark wood with thick gold trim, a small raised "
                   "tab at the top centre, and scrolled gold flourish end caps sticking out at the left and right, completely blank centre, no letters, no numbers") + MAG,
    "pk_w_pill_small": "ONE complete finished small pill plate, wide and short (about 3.8 times as wide as tall), like the Hands: 4 plate in the reference, " + ORN + MAG,
    "pk_w_btn_dark": "ONE complete finished wide button plate (about 3.9 times as wide as tall), like the Discard button in the reference, " + ORN + MAG,
    "pk_w_btn_green": ("ONE complete finished wide button plate (about 3.9 times as wide as tall), like the Play Hand button in the reference: deep green enamel centre, "
                       "thick two-tone gold beveled border with scrolled gold corner ornaments and small studs and gold flourish ends, completely blank centre, no letters") + MAG,
    "pk_w_btn_sq": ("ONE complete finished small button plate (about 2 times as wide as tall), like the Rank and Suit buttons in the reference, " + ORN
                    + ", with the left third left empty for an icon") + MAG,
    "pk_w_count": "ONE complete finished plate, wide and short (about 3.3 times as wide as tall), like the 44 / 52 deck count plate in the reference, " + ORN + MAG,
    "pk_w_hint": ("ONE complete finished hint panel (about 2.3 times as wide as tall) like the Patron Power panel in the reference: dark brown carved wood panel with a thick gold trim and "
                  "scrolled corners, and at the left a small cream parchment square with a gold crown medallion inside it, the rest of the panel blank dark wood for text, no letters, no numbers") + MAG,
    "pk_w_icons": ("A sheet of SIX separate small round game icons in a 3 by 2 grid with wide gaps, each in a dark brown round carved-wood button with a gold rim like the round buttons in the reference, "
                   "painted in the same style: top row left to right a speaker with sound waves, a pause symbol (two bars), a glowing yellow light bulb; bottom row a three-bar bar chart, a black spade card suit, a gold crown. "
                   "No letters, no numbers") + MAG,
}
d["pk_subjects"].update(new)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
G = HERE / "generate_patron_art.py"
s = G.read_text(encoding="utf-8")
m = re.search(r'for k in \(([^)]*)\)\)\},', s)
if m and "pk_w_target" not in m.group(1):
    add = ", ".join('"%s"' % k for k in new)
    s = s[:m.start(1)] + m.group(1) + ", " + add + s[m.end(1):]
    G.write_text(s, encoding="utf-8")
print("ok", len(new))
