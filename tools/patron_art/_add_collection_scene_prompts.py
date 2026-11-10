#!/usr/bin/env python3
"""One-off: add the collection_scene prompts (Collection Gallery) to prompts.json. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, soft warm light, "
         "warm dark wood palette, original art, no text, no letters, no numbers, no logos, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
d["collection_scene_subjects"] = {
    "collection_wall": "a panelled dark wood tavern back-room wall with a wainscot, two wall lanterns glowing softly at the left and right sides, a window with a night sky in one corner, the floor edge visible at the bottom, wide 16:9 composition, no furniture and no picture frames, calm centre" + STYLE,
    "collection_frame_owned": "an ornate gilt picture frame hanging from a short chain, a small blank brass nameplate at the bottom, empty dark centre window, portrait 3:4 composition, centered" + STYLE + MAG,
    "collection_frame_empty": "the same ornate gilt picture frame hanging from a short chain with a grey dust cloth draped over it and a blank brass plate at the bottom, portrait 3:4 composition, centered" + STYLE + MAG,
    "collection_corkboard": "a cork pin board in a wooden frame with a few empty pins, landscape 4:3 composition, centered" + STYLE + MAG,
    "collection_trophy_shelf": "a wooden shelf with a brass rail and three empty round trophy stands, very wide strip composition, centered" + STYLE + MAG,
    "collection_key_rack": "a wooden key and ticket rack with six brass hooks in a row, very wide strip composition, centered" + STYLE + MAG,
    "collection_nameplate_shelf": "a narrow wooden shelf with small empty brass plate holders in a row, very wide thin strip composition, centered" + STYLE + MAG,
    "collection_chest_closed": "a small iron-banded wooden treasure chest, closed, square 1:1 composition, centered" + STYLE + MAG,
    "collection_chest_open": "the same small iron-banded wooden treasure chest with the lid open and a soft warm glow inside, square 1:1 composition, centered" + STYLE + MAG,
    "collection_moth": "a small pale moth with wings open, seen from above, square 1:1 composition, centered" + STYLE + MAG,
    "collection_dust_cloth": "a soft grey cloth draped over an invisible shape, square 1:1 composition, centered" + STYLE + MAG,
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["collection_scene_subjects"]))
