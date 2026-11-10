#!/usr/bin/env python3
"""One-off: add the flair_ui_subjects prompts (category `flair_ui`, the Flair dressing room pieces) to prompts.json.
No generation, no API calls. Generating costs credits: run `generate_patron_art.py generate -c flair_ui` only for a
queue task marked ALLOWED: generate."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

MAGENTA = "flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, "
STYLE = ("blocky painted Roblox tavern style, chunky shapes, painted texture, warm candlelight, original art, "
         "no text, no letters, no numbers, no logos, kid-friendly")

PIECES = {
    "flair_stage": ("a dark red curtained stage with an ornate gold mirror frame and a soft spotlight, large empty center, "
                    "16:9 landscape", False),
    "flair_drawer_front": ("a long wooden drawer front with a brass pull, seen straight on", True),
    "flair_cabinet": ("a tall wooden cabinet frame seen straight on with empty drawer slots, nothing outside the cabinet", True),
    "flair_velvet_tray": ("a deep green velvet tray, empty, wide, seen from slightly above", True),
    "flair_medallion_ring": ("an empty round brass medallion frame, seen straight on, hollow center", True),
    "flair_medallion_ring_locked": ("an empty round medallion frame in dull dark iron with a small padlock at the bottom, "
                                    "hollow center", True),
    "flair_on_ribbon": ("a small gold ribbon tag, empty and blank", True),
    "flair_brass_tag": ("a small brass price tag with a hole and string, empty and blank", True),
    "flair_sparkle_burst": ("a soft gold sparkle burst overlay with a few small star glints", True),
}
d["flair_ui_subjects"] = {k: v[0] + ", " + (MAGENTA if v[1] else "") + STYLE for k, v in PIECES.items()}

P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("flair_ui_subjects:", len(d["flair_ui_subjects"]))
