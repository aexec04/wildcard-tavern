#!/usr/bin/env python3
"""One-off: add the boon_icon_subjects prompts (category `boon_icons`: one per Engine/NightBoons.lua id) to prompts.json.
No generation, no API calls. Generating costs credits: run `generate_patron_art.py generate -c boon_icons` only for a
queue task marked ALLOWED: generate."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

TAIL = (", single centered subject filling about 70 percent of the square frame on flat pure magenta #FF00FF with no "
        "gradient, square composition, blocky painted Roblox tavern style, warm lantern light, painterly, readable at "
        "40 pixels, bold simple shapes, no text, no letters, no numbers, no people, kid-friendly")

SUBJECTS = {
    "extra_hand": "a friendly open glove-less cartoon hand with a small gold sparkle above it holding one playing card",
    "extra_discard": "a playing card flipping through the air with two gold curved arrows circling it",
    "wider_grip": "two wide open cartoon hands side by side cupping a fan of extra playing cards",
    "opening_flourish": "a tall black top hat with a gold band and a bright gold star burst popping out of it",
    "warm_welcome": "a small glowing orange lantern with a warm flame and soft golden rays around it",
    "pocket_change": "a small brown coin pouch with three shiny gold coins resting in front of it",
    "free_reroll": "a pair of wooden dice with a gold sparkle and a tiny gold ribbon",
    "patron_discount": "a round gold price tag tied with a string, with a small downward gold arrow on it",
    "pack_discount": "a red gift box tied with a gold ribbon with a small downward gold arrow beside it",
    "boss_hand": "a round wooden shield with a gold rim and a small playing card in the middle",
    "boss_discard": "a small wooden toolbox with a gold latch and a playing card tucked in the lid",
    "steady_pace": "a friendly cartoon turtle wearing a tiny gold crown walking calmly",
}
d["boon_icon_subjects"] = {k: v + TAIL for k, v in SUBJECTS.items()}

P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("boon_icon_subjects:", len(d["boon_icon_subjects"]))
