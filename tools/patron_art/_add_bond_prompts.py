#!/usr/bin/env python3
"""One-off: add the 8 Bond prompts (category `bonds`: one per Engine/Bonds.lua id plus bond_locked) to prompts.json.
No generation, no API calls. Generating costs credits: run `generate_patron_art.py generate -c bonds` only for a
queue task marked ALLOWED: generate."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

MEDALLION = ("round gold-rimmed medallion emblem, single centered subject with generous margin on a plain dark brown "
             "background, blocky painted Roblox tavern style, warm lantern light, kid-friendly, no text, no letters")

subjects = {
    "pairs": "two friendly blocky avatars clinking cups of hot cocoa together, a pair of matching cards between them",
    "flush": "a curling blue wave pouring out of a large heart card-suit symbol",
    "straight": "a straight road of card-shaped steps climbing up to a glowing lantern on a hilltop",
    "economy": "a chubby pink piggy bank with a shiny gold coin dropping into its slot",
    "scaling": "a green sprout with two leaves growing out of a playing card",
    "rulebender": "gears and a wrench resting over an open rulebook",
    "ranks": "a gold crown floating above a king card and a queen card",
    "bond_locked": "a dim grey outline of two linked rings with a small padlock hanging on them, muted and mysterious",
}
d["bond_subjects"] = {k: v + ", " + MEDALLION for k, v in subjects.items()}

P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("bond_subjects:", len(d["bond_subjects"]))
