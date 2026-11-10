#!/usr/bin/env python3
"""One-off: add menu_world_subjects (Living Map menu landmarks) to prompts.json. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
MAGENTA = "flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, "
STYLE = ("blocky painted Roblox tavern style, slightly chunky proportions, hand-painted edges, painted texture, soft warm light, "
         "same palette as a painted fantasy world map, not photoreal, no text, no letters, no numbers, no logos, kid-friendly, no alcohol")
S = {
 "menu_tavern_hub": "a big cozy tavern building seen from a three-quarter top-down angle with a glowing open door, a blank hanging sign, space above the chimney for smoke and a small stone courtyard in front, 4:3 landscape",
 "menu_road_out": "a wide dirt road leaving a tavern door and running toward the bottom of the frame, seen from above at an angle, grass edges, 3:2 landscape",
 "menu_quest_board": "a wooden quest board landmark on two posts with blank pinned papers and a little roof, map-piece landmark",
 "menu_tome_library": "a small round library tower with a big open book resting on the roof, map-piece landmark",
 "menu_coin_jar_shop": "a little market stall with a striped awning and a giant glass coin jar on the counter, map-piece landmark",
 "menu_rulebook_stand": "a wooden lectern with a big open book and a small lantern beside it, map-piece landmark",
 "menu_jukebox_stage": "a small wooden stage with a brass horn gramophone and a few music note shapes without letters, map-piece landmark",
 "menu_map_table_tent": "a travelling cartographer tent with rolled maps sticking out and a map table beside it, map-piece landmark",
 "menu_notice_post": "a wooden signpost with several blank arrow signs pointing different ways, map-piece landmark",
 "menu_cloud_wisp": "a soft thin white cloud wisp, a wide 3:1 strip, only the cloud on the canvas",
 "menu_fog_edge": "a misty parchment fog edge for a map border, fog and aged parchment fading inward on all four sides, the whole center is empty, 16:9 landscape",
 "menu_map_frame": "an unrolled parchment map edge with two wooden rollers at top and bottom and curled paper corners, for a screen border, the whole center is empty, 16:9 landscape",
}
d["menu_world_subjects"] = {k: v + ", " + MAGENTA + STYLE for k, v in S.items()}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
