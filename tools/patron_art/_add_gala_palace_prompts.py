#!/usr/bin/env python3
"""One-off: Golden Gala palace scenes (play room bg and front rewritten, menu, boss table, shop room). No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
ROOM = ("a grand tavern ballroom, polished dark wood walls with gold trim, tall arched windows with a night sky, a warm crystal chandelier glow, "
        "deep burgundy velvet drapes with gold tassels, gold candelabras with candle flames, a marble floor edge")
SAFE = "no text, no letters, no numbers, no logos, no people, no characters, no bottles, no glasses, no weapons, kid-friendly"
d["play_scene_subjects"]["play_room_golden_gala_bg"] = (
    "The inside of " + ROOM + ", seen from the player seat, painted in a warm painterly candlelit style. "
    "A big oval card table: a plain flat dark burgundy velvet felt top with no pattern, a thick carved gold rail all the way round with inlaid gold trim, "
    "soft warm light on the felt, dark vignette corners, the room dim and slightly out of focus behind. The felt centre is empty and the lower third "
    "of the frame is clear for a hand tray. Same oval footprint and camera as the reference table. No cards, no UI, " + SAFE + ".")
d["play_scene_subjects"]["play_room_golden_gala_front"] = (
    "Only the near front of a round-cornered card table seen from the player seat, straight on and flat, filling the bottom 40 percent of the frame only. "
    "Everything above the front rim is flat solid pure magenta #FF00FF background: no felt, no table top, no rim along the top. A thick carved polished gold "
    "front rail with inlaid gold trim and deep burgundy velvet padding, one long empty rounded groove (a hand rail) whose left end is at 20 percent of the "
    "image width and right end at 80 percent, with its top at 76 percent of the image height and its bottom at 85 percent, one empty square recess for a deck "
    "box at the right whose left edge is at 81 percent of the width, right edge at 98 percent, top at 66 percent of the height and bottom at 80 percent, and a "
    "wide dark burgundy velvet and gold apron below the front rim. Nothing else is painted. Blocky painted Roblox tavern style, chunky shapes, painted texture, "
    "matte, calm, original art, " + SAFE + ". Everything empty: no cards, no coins, no felt, flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges")
STYLE = (", painted not photographic, same painted warm tavern style as the classic tavern art, wide 3:2 composition, original art, " + SAFE)
d["table_scene_subjects"]["theme_gala_menu"] = "the inside of " + ROOM + " seen straight on from the front, a long polished wood and gold counter far back, the whole centre calm, dark and empty" + STYLE
d["table_scene_subjects"]["theme_gala_boss"] = "the same grand tavern ballroom card table room but darker with a deep vignette and a faint red glow at the edges, burgundy velvet drapes, gold candelabras, the large centre of the table an empty dark burgundy velvet felt" + STYLE
d["shop_scene_subjects"]["shop_room_gala"] = (
    "the same tavern market counter room as the reference, same layout and same camera, but dressed as a grand gold ballroom: dark polished wood and gold trim walls, burgundy velvet drapes, "
    "a long dark wood bar counter with a gold rail in the lower third, shelves of card boxes and jars with gold edges, the counter top clear and empty, a round card table with a dark burgundy velvet felt "
    "and a gold rail in front of the counter, a crystal chandelier glow, warm light, " + SAFE)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
