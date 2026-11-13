#!/usr/bin/env python3
"""One-off: add two card face candidates to play_scene_subjects and their sizes. No API calls."""
import json, pathlib
ROOT = pathlib.Path(__file__).resolve().parent
P = ROOT / "patron_art" / "prompts.json"
text = P.read_text(encoding="utf-8")
d = json.loads(text)
BASE = ("A single blank playing card face, portrait, centred, upright, rounded corners, on a flat transparent background. "
        "Aged warm ivory paper with subtle fibre grain and a faint warm vignette toward the edges, a thin dark-gold border line "
        "with a faint inner emboss, no orange or red anywhere, the centre is plain empty paper so rank, suit and pips can be drawn on top. "
        "Painterly storybook tavern style matching hand-painted dark-gold Patron card frames. "
        "No text, no letters, no numbers, no suit symbols, no pips, no characters, no UI, kid-friendly, original art. ")
VAR = {
    "card_face_ivory_a": "Very restrained: a single hairline gold edge and a soft paper texture, tiny corner flourishes.",
    "card_face_ivory_b": "Slightly richer: a double thin gold edge with a faint embossed inner frame and a gentle aged-paper stain at the corners.",
}
for k, v in VAR.items():
    d["play_scene_subjects"][k] = BASE + v
P.write_text(json.dumps(d, indent=2 if text.startswith("{\n  ") else 1, ensure_ascii=False) + "\n", encoding="utf-8")

G = ROOT / "patron_art" / "generate_patron_art.py"
s = G.read_text(encoding="utf-8")
old = '"play_nook_strip_c": "1536x1024"},'
new = '"play_nook_strip_c": "1536x1024",\n                             "card_face_ivory_a": "1024x1536", "card_face_ivory_b": "1024x1536"},'
assert old in s
G.write_text(s.replace(old, new, 1), encoding="utf-8")
