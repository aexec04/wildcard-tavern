#!/usr/bin/env python3
"""One-off: add the shop_scene prompts (Counter v2) to prompts.json. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, soft warm light, "
         "warm dark wood palette, original art, no text, no letters, no numbers, no logos, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
MARLO = ("Marlo, the same friendly hooded travelling peddler as the earlier shop art: brown hooded cloak, kind face in the shade of the hood, "
         "a glowing brass lantern hanging at his hip and a big bundle pack over his shoulder, exactly two hands, ")
d["shop_scene_subjects"] = {
    "shop_wall": "the back of a tavern bar seen from the customer side, wide 16:9 composition, warm dark wood back bar with shelves of jars, crates and wrapped goods, two glowing lanterns, a blank hanging wooden sign, a curtain at the left edge, no counter in front and no character, soft vignette, centre slightly darker so figures read" + STYLE,
    "shop_marlo_behind": MARLO + "shown from the waist up, large, facing the viewer, one arm extended palm up presenting goods toward the viewer's right, friendly smile, portrait 3:4 composition, centered" + STYLE + MAG,
    "shop_marlo_wave": MARLO + "shown from the waist up, large, facing the viewer, one hand raised in a small friendly wave, the other hand resting at his side, portrait 3:4 composition, centered" + STYLE + MAG,
    "shop_counter_top": "a long wooden tavern bar counter seen from the front and slightly above, worn top surface with a brass rail along the front edge, very wide strip composition, counter spanning the full width in the lower half, empty top surface" + STYLE + MAG,
    "shop_counter_props": "four separate small props spaced far apart on one flat horizontal row, left to right: a brass service bell, a closed ledger book, a wooden mug, a lit candle in a brass holder, very wide strip composition, each prop clearly separated by empty space" + STYLE + MAG,
    "shop_light_pool": "a soft warm elliptical pool of lamp light, wide 2:1 composition, very low contrast, faint glow fading to nothing at the edges" + STYLE + MAG,
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["shop_scene_subjects"]))
