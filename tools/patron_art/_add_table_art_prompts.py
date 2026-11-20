#!/usr/bin/env python3
"""One-off: add the ct_deck_tray and ct_rail_strip prompts to prompts.json and cut their reference crops.
No generation, no API calls."""
import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
P = ROOT / "tools/patron_art/prompts.json"
OUT = ROOT / "art-wip/table_art"
OUT.mkdir(parents=True, exist_ok=True)

im = Image.open(ROOT / "claude/reference/concept-table-reference.png").convert("RGB")
im.crop((1410, 430, 1672, 660)).save(OUT / "ref_tray.png")
im.crop((0, 790, 1672, 941)).save(OUT / "ref_rail.png")

d = json.loads(P.read_text(encoding="utf-8"))
M = ("on a flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, "
     "the object centred with generous margin, no letters anywhere")
d["concept_t_subjects"]["ct_deck_tray"] = (
    "only the dark carved wooden tray with a raised lip that the card deck rests in, taken from the reference: remove the "
    "card deck completely so the tray is empty, keep the warm oak wood, gold edge highlight and the soft contact shadow, "
    "seen from the same angle, " + M)
d["concept_t_subjects"]["ct_rail_strip"] = (
    "only a long horizontal warm wooden table rail band with a carved decorative top edge and a thin gold inlay line, taken "
    "from the bottom edge of the reference: remove every button, pill, label and text so the band is plain, one straight "
    "horizontal band that fills the width of the canvas, about one fifth of the canvas tall, centred vertically, " + M)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
