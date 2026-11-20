#!/usr/bin/env python3
"""One-off: add the ct_table_rim prompt to prompts.json and cut its reference crop. No generation, no API calls."""
import json, pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
P = ROOT / "tools/patron_art/prompts.json"
OUT = ROOT / "art-wip/table_art"
OUT.mkdir(parents=True, exist_ok=True)
im = Image.open(ROOT / "claude/reference/concept-table-reference.png").convert("RGB")
im.crop((0, 420, 1672, 941)).save(OUT / "ref_rim.png")
d = json.loads(P.read_text(encoding="utf-8"))
M = ("on a flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, no letters anywhere")
d["concept_t_subjects"]["ct_table_rim"] = (
    "only the thick carved dark oak wooden rim of the oval card table, taken from the lower half of the reference: a wide curved "
    "band that follows the bottom of the oval, runs up both sides and thickens at the bottom where the buttons sit, with a thin gold "
    "inlay line along its inner edge; remove the green felt, the cards, the deck, every button, pill and label, and fill the whole "
    "inside of the oval and the whole area outside the wood with flat magenta so only the wood band remains, " + M)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
