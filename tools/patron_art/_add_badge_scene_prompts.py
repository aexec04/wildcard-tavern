#!/usr/bin/env python3
"""One-off: add the three Badges sub-panel scenes (Masters, Night, Special) to badge_wall_subjects. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
TAIL = (", wide 16:9 composition, straight-on view, no people, no characters, no badges or medals inside the sockets (all empty), "
        "blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, soft warm light, "
        "warm dark wood palette, original art, no text, no letters, no numbers, no logos, kid-friendly")
b = d["badge_wall_subjects"]
b["badge_scene_masters"] = ("a navy blue velvet display board in a gold frame filling the picture, with exactly 8 empty round brass-rimmed sockets "
    "recessed into the velvet: one large socket centered near the top, and a row of seven equal smaller sockets evenly spaced in a line across the lower half, "
    "plenty of calm velvet between them, a little room under the lower row" + TAIL)
b["badge_scene_night"] = ("a deep wooden window ledge below a night window with a starry sky and a crescent moon, and exactly 4 equal empty round carved niches "
    "in a row evenly spaced along a dark oak sill in the lower half, brass rims, a small candle at the far right edge, calm space around each niche" + TAIL)
b["badge_scene_special"] = ("a warm wooden display shelf unit filling the picture, two long shelf planks, each with exactly 6 equal empty round felt-lined recesses "
    "evenly spaced in a row (12 recesses in total in 2 rows of 6), a small candle on the top corner, space under each row for small name plates" + TAIL)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
