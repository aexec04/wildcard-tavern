#!/usr/bin/env python3
"""One-off: add the blessing_icon_subjects prompts (category `blessing_icons`: one per Engine/RunModifiers.lua id) to
prompts.json. No generation, no API calls. Generating costs credits: run
`generate_patron_art.py generate -c blessing_icons` only for a queue task marked ALLOWED: generate."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

TAIL = (", single centered subject filling about 70 percent of the square frame on flat pure magenta #FF00FF with no "
        "gradient, square composition, blocky painted Roblox tavern style, warm lantern light, painterly, readable at "
        "40 pixels, bold simple shapes, no text, no letters, no numbers, kid-friendly")

SUBJECTS = {
    "open_hands": "two open friendly hands raised palms up with a few playing cards floating above them",
    "fat_purse": "a plump brown coin purse tied with a gold cord, a few shiny gold coins spilling out",
    "sharp_eyes": "a large bright eye with a golden iris and a small sparkle, framed by a gentle brow",
    "big_book": "a thick tall recipe book with a gold ribbon bookmark and a ladle on its cover",
    "generous_house": "a glowing red paper lantern with a gold tassel and a little stream of coins falling below it",
    "wide_table": "a long wooden tavern table with extra stools and a candle, seen from slightly above",
}
d["blessing_icon_subjects"] = {k: v + TAIL for k, v in SUBJECTS.items()}

P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("blessing_icon_subjects:", len(d["blessing_icon_subjects"]))
