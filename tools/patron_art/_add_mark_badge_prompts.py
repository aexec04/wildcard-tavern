#!/usr/bin/env python3
"""One-off: add mark_badge_subjects (category `mark_badges`: one per Card.MarkOrder id) to prompts.json. No generation, no API
calls. Generating costs credits: run `generate_patron_art.py generate -c mark_badges` only for a queue task marked ALLOWED: generate."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

TAIL = (", single centered subject filling about 75 percent of the square frame on flat pure magenta #FF00FF with no "
        "gradient, square composition, blocky painted Roblox tavern style, warm lantern light, painterly, readable at "
        "20 pixels, bold simple shapes, thick dark outline, no text, no letters, no numbers, kid-friendly")

SUBJECTS = {
    "gilded": "one shiny round gold coin with a raised rim and a small star stamped in the middle",
    "lucky": "one bright green four leaf clover with a tiny gold sparkle",
    "lively": "one bright golden spark burst, a small star with short rays, cheerful and energetic",
}
d["mark_badge_subjects"] = {k: v + TAIL for k, v in SUBJECTS.items()}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("mark_badge_subjects:", len(d["mark_badge_subjects"]))
