#!/usr/bin/env python3
"""One-off: add the menu_scene v2 candidates (one painted tavern interior, 3 candidates of the same prompt). No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, soft warm light, "
         "warm dark wood palette, original art, no text, no letters, no numbers, no logos, blank signs and blank paper, kid-friendly, "
         "wide 16:9 landscape composition")
SCENE = ("ONE cosy tavern interior painted as a single picture, seen straight on at a slightly high angle, every item standing on a surface "
         "with soft contact shadows and correct relative scale. LEFT: a stone fireplace with a glowing fire, and in front of it a carved wooden "
         "lectern holding a huge open book. CENTRE BACK: a long wooden bar counter running across the middle with a big glass jar of gold coins "
         "and a small closed rulebook sitting ON the counter top, and above the counter on the back wall a window with a starry night sky, with a "
         "rolled quest scroll pinned to the wall by a ribbon on one side of the window and a rolled road map on a wall bracket on the other side. "
         "RIGHT: a tall wooden jukebox with brass pipes standing on the floor right next to the end of the counter, and above it on the right wall "
         "a large empty wooden notice board with a few pinned blank papers, the board face mostly empty and calm. FOREGROUND CENTRE: a round green "
         "felt card table with a deck of cards and two candles and four wooden chairs, standing on the floor in front of the counter, drawn larger "
         "because it is closer, with the chairs on the floor and not on the table. Wooden plank floor across the bottom, two small hanging lanterns. "
         "Keep the bottom 12 percent of the image calm with no props and the top 8 percent calm with no props")
subs = d.setdefault("menu_scene_subjects", {})
for k in ("menu_scene_a", "menu_scene_b", "menu_scene_c"):
    subs.setdefault(k, SCENE + STYLE)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
