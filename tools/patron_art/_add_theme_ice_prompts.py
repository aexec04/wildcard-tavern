#!/usr/bin/env python3
"""One-off: add the winter_evening ice tavern theme scenes to prompts.json (table_scene_subjects). No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, hand painted texture, matte, cold blue lantern light with a little warm glow, walls of ice and frost, "
         "icicles hanging from dark beams, painted not photographic, original art, wide 3:2 composition, "
         "no text, no letters, no numbers, no logos, no user interface, no cards, no characters, kid-friendly")
d["table_scene_subjects"].update({
    "theme_ice_menu": "the inside of an ice tavern seen from the front, frosted stone and ice block walls, frozen barrels and crates at the sides, blue paper lanterns, a long frosted wooden counter far back, the whole centre calm, dark and empty" + STYLE,
    "theme_ice_boss": "the same ice tavern card table room but darker and colder with a deep vignette, a faint red ember glow at the edges, frozen barrels, icicles on the beams, the large centre of the table empty and calm" + STYLE,
    "theme_ice_map": "a painted top down map ground of a snowy land with frozen ponds, snowy pines, ice ridges and wind swept drifts, soft blue light, gentle low contrast, wide open empty paths in the middle so map markers will stand out, no buildings, no roads drawn in dark lines" + STYLE,
})
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
