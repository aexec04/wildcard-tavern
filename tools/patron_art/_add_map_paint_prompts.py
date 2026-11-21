#!/usr/bin/env python3
"""One-off: add the Tavern Map redesign prompts (parchment countryside, six round node paintings, boss emblem) to prompts.json."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

d["style_map_paint"] = ("Hand-painted 2D fantasy storybook illustration, warm candlelit palette of amber, olive green and rich brown, soft painterly "
                        "brushwork with gentle dark ink outlines, glowing lantern light, cozy and kid-friendly, no people, no characters, no text, "
                        "no letters, no numbers, no logos, no alcohol")
d["map_paint_subjects"] = {
    "parchment_map": ("a wide aged parchment treasure-map painting of a cozy countryside seen from a slightly raised angle: a timber tavern with glowing "
                      "windows at the far left, a windmill on a hill near the top, a winding river with two small wooden bridges in the lower right, "
                      "clusters of pine and oak trees, golden fields, wooden fences, stone cairns and a few lanterns on posts. A wide open dirt-coloured "
                      "meadow band runs across the middle from left to right with no objects on it, so a route can be drawn over it. Torn parchment "
                      "edges fade into dark wood at the corners. 16:9 landscape, no frame, no UI"),
    "node_encounter": "a full-bleed square painting of a dusty country road with a wooden signpost (no writing) and a glowing tavern in the distance at golden dusk",
    "node_shop": "a full-bleed square painting of a red and cream striped market stall awning with baskets of fruit, bread and jars, warm lantern glow",
    "node_event": "a full-bleed square painting of a glowing hanging lantern in a flower garden at dusk with drifting fireflies",
    "node_shrine": "a full-bleed square painting of a small mossy stone shrine with a candle and flowers among trees, soft light rays",
    "node_rest": "a full-bleed square painting of a cozy campfire beside a little tent under a starry blue evening sky",
    "node_treasure": "a full-bleed square painting of an open wooden treasure chest overflowing with gold coins and gems, glowing, on grass",
    "boss_emblem": ("a friendly cartoon crowned white skull wearing a golden crown, inside a round dark crimson medallion with a gold rim, flanked by two "
                    "red banners on poles, single isolated emblem centered with generous margin, cute rather than scary, on a plain pure magenta #FF00FF background with no gradient and no shadow"),
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False), encoding="utf-8")
print("map_paint", len(d["map_paint_subjects"]))
