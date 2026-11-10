#!/usr/bin/env python3
"""One-off: add the menu_room prompts (Menu Tavern Room) to prompts.json. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, soft warm light, "
         "warm dark wood palette, original art, no text, no letters, no numbers, no logos, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background filling every empty pixel with no gradient, no shadow and no glow touching the edge, object centred with a margin, clean sharp edges"
d["menu_room_subjects"] = {
    "menu_room_wall": "the back wall and floor of a cosy tavern interior seen straight on, a stone fireplace glowing at the right, a window with a night sky at the left, wooden beams, a long bar counter along the lower third, no props on the walls or counter and no people, centre calm and clear, wide 16:9 composition" + STYLE,
    "menu_room_jukebox": "a standing wooden jukebox with brass pipes and a softly glowing front, portrait 3:4 composition" + STYLE + MAG,
    "menu_room_coinjar": "a big glass coin jar full of gold coins on a small wooden stand, square 1:1 composition" + STYLE + MAG,
    "menu_room_tome": "a huge open book on a carved wooden lectern with a soft glow, square 1:1 composition" + STYLE + MAG,
    "menu_room_scroll": "a rolled quest scroll tied with a ribbon hanging on a wall hook, square 1:1 composition" + STYLE + MAG,
    "menu_room_noticeboard": "a wooden notice board with pinned papers that have empty blank paper areas, landscape 4:3 composition" + STYLE + MAG,
    "menu_room_map": "a rolled road map on a small wall bracket, square 1:1 composition" + STYLE + MAG,
    "menu_room_rulebook": "a small book with a bookmark ribbon on a little shelf stand, square 1:1 composition" + STYLE + MAG,
    "menu_room_cardtable": "a round green felt card table with a deck of cards and two candles, front view, landscape 4:3 composition" + STYLE + MAG,
    "menu_room_lantern": "a hanging iron lantern with a warm flame, tall 1:2 composition" + STYLE + MAG,
    "menu_room_sign": "a hanging brass hand-painted sign shape with no text, wide 3:1 composition" + STYLE + MAG,
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["menu_room_subjects"]))
