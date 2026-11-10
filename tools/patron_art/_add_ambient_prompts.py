#!/usr/bin/env python3
"""One-off: add the ambient sprite prompts (living backdrops) to prompts.json. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky soft shapes, painted texture, matte, calm, soft colours, no outline, "
         "original art, no text, no letters, no numbers, no logos, kid-friendly")
ONE = "exactly one small object, centered with generous empty margin, "
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
BF = "a small warm orange butterfly seen from above with a dark brown body, "
BB = "a small soft blue butterfly seen from above with a dark brown body, "
BIRD = "a small distant bird in flight seen from the side, dark slate colour, simple silhouette, "
d["ambient_subjects"] = {
    "ambient_butterfly_open": ONE + BF + "wings fully open and flat" + STYLE + MAG,
    "ambient_butterfly_closed": ONE + BF + "the same butterfly with wings half closed, narrower" + STYLE + MAG,
    "ambient_butterfly_blue_open": ONE + BB + "wings fully open and flat" + STYLE + MAG,
    "ambient_butterfly_blue_closed": ONE + BB + "the same butterfly with wings half closed, narrower" + STYLE + MAG,
    "ambient_cloud_a": ONE + "a soft painted white wisp of cloud, long and flat, wide 2:1 shape" + STYLE + MAG,
    "ambient_cloud_b": ONE + "a different soft painted white wisp of cloud, two puffs joined, wide 2:1 shape" + STYLE + MAG,
    "ambient_leaf_green": ONE + "a single green leaf" + STYLE + MAG,
    "ambient_leaf_gold": ONE + "a single golden autumn leaf" + STYLE + MAG,
    "ambient_petal": ONE + "a single pink blossom petal" + STYLE + MAG,
    "ambient_snowflake": ONE + "a soft round white snowflake" + STYLE + MAG,
    "ambient_firefly": ONE + "a tiny warm yellow glow dot with a soft halo" + STYLE + MAG,
    "ambient_ember": ONE + "a small orange glowing spark" + STYLE + MAG,
    "ambient_sand_streak": ONE + "a thin pale sandy wind streak, very wide thin 4:1 shape" + STYLE + MAG,
    "ambient_bird": ONE + BIRD + "wings raised up" + STYLE + MAG,
    "ambient_bird_down": ONE + BIRD + "the same bird with wings down" + STYLE + MAG,
    "ambient_lantern_float": ONE + "a small paper sky lantern with a warm glow" + STYLE + MAG,
    "ambient_ribbon": ONE + "a short curling cloth ribbon in festive red" + STYLE + MAG,
    "ambient_gold_mote": ONE + "a soft gold sparkle" + STYLE + MAG,
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["ambient_subjects"]))
