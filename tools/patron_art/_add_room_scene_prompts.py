#!/usr/bin/env python3
"""One-off: add the painted room prompts to prompts.json (no API calls).

  collection_scene / collection_room   the Collection's gallery room, six objects in two rows of three
  badge_wall       / badge_room        the Badges trophy room, four objects in two rows of two
  shop_scene       / shop_table        the Counter's round card table, a cut-out placed over the counter

The two rooms are restyled toward the Menu room wall (art-wip/menu_room/menu_room_wall.png, see CATEGORY_OPTS references in
generate_patron_art.py) so they read as rooms of the same tavern. Layout of the objects follows Engine/CollectionRoomLayout (3 x 2) and
Engine/BadgeRoomLayout (2 x 2), so a painted room can take the same hotspots. No text in any image, kid-friendly.
"""
import json, pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, soft warm light, "
         "warm dark wood palette, original art, no text, no letters, no numbers, no logos, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"

d.setdefault("collection_scene_subjects", {})["collection_room"] = (
    "the same warm timber-framed tavern as the main room, a quiet back-room gallery seen straight on, wide 16:9 composition, plaster wall "
    "panels between dark wood beams, six clear display spots in two rows of three with calm empty space between them. Top row, left to right: "
    "a wall of three empty gilded picture frames hung close together, a cork board with a few blank paper notes and red pins, a wooden "
    "trophy shelf with small brass cups on a plank. Bottom row, left to right: a wooden key rack with blank hanging brass tags, a dark wooden "
    "rail with a few brass nameplates screwed on, a small cork board with red string pulled between pins. Warm lantern light from both "
    "sides, a wooden plank floor along the bottom, no people, no characters" + STYLE)

d.setdefault("badge_wall_subjects", {})["badge_room"] = (
    "the same warm timber-framed tavern as the main room, a trophy room seen straight on, wide 16:9 composition, plaster wall panels between "
    "dark wood beams, four clear display spots in two rows of two with calm empty space between them. Top left: a big pinned parchment road map "
    "with red pins and a winding dotted road across it. Top right: a navy blue velvet display board in a gold frame with a row of empty round "
    "sockets. Bottom left: a window onto a night sky with stars and a crescent moon over small rooftops. Bottom right: a wooden wall of "
    "shelves with empty round niches on two planks. Warm lantern light from both sides, a wooden plank floor along the bottom, no people, "
    "no characters" + STYLE)

d.setdefault("shop_scene_subjects", {})["shop_table"] = (
    "a round wooden card table seen from above and slightly from the front, a wide oval with a smooth brown wood rim and a soft muted "
    "green felt top, a faint warm lantern glow on the left side of the felt, the felt completely empty so playing cards can be laid on it, "
    "the table fills the canvas width and is centred, no chairs, no cards, nothing on the table, wide 3:2 composition" + STYLE + MAG)

P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["collection_scene_subjects"]), len(d["badge_wall_subjects"]), len(d["shop_scene_subjects"]))
