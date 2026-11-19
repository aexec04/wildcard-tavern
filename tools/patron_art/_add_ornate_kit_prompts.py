#!/usr/bin/env python3
"""One-off: add six ornate frame pieces to the painted_kit category (pk_orn_*). No API calls."""
import json, pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
P = HERE / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
MAG = ", on a flat solid pure magenta #FF00FF background with no gradient, clean sharp edges, the piece centred with generous margin"
ORN = ("heavily ornate: dark brown carved wood fill, a thick carved gold trim border, scrolled gold filigree corner ornaments and small gold studs, "
       "painted warm candlelit look like the plates in the reference image, completely empty flat centre, no letters, no numbers, no icons")
subs = d["pk_subjects"]
new = {
    "pk_orn_pill_wide": "a wide short pill plate like the Target and Tips plates, " + ORN + MAG,
    "pk_orn_pill_small": "a small short rounded plate like the Hands and Discards count plates, " + ORN + MAG,
    "pk_orn_square": "a small square plate like the Rank and Suit buttons, " + ORN + MAG,
    "pk_orn_score": "a big wide Score plate with a small raised tab at the top centre and gold flourish end caps left and right, " + ORN + MAG,
    "pk_orn_btn_dark": "a wide dark wood button frame like the Discard button, " + ORN + MAG,
    "pk_orn_btn_green": ("a wide green enamel button frame like the Play Hand button with a thick carved gold trim, scrolled gold corner ornaments "
                         "and gold studs, completely empty flat green centre, no letters") + MAG,
}
subs.update(new)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# register the new keys in the painted_kit references dict (same reference image as the other pk_ pieces)
G = HERE / "generate_patron_art.py"
s = G.read_text(encoding="utf-8")
m = re.search(r'for k in \(([^)]*)\)\)\},', s)
if m and "pk_orn_pill_wide" not in m.group(1):
    add = ", ".join('"%s"' % k for k in new)
    s = s[:m.start(1)] + m.group(1) + ", " + add + s[m.end(1):]
    G.write_text(s, encoding="utf-8")
print("ok", len(new))
