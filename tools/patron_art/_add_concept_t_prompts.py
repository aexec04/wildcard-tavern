#!/usr/bin/env python3
"""One-off: add the concept_t art kit prompts (blank HUD plates, card back, empty table room). No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
d["concept_t_style"] = ("Edit the reference image. Keep exactly the same hand-painted blocky Roblox tavern style, palette, wood grain, gold trim and lighting. "
                        "Original art, kid-friendly, no letters, no numbers, no text anywhere")
MAG = ", on a flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, the object centred with generous margin"
subs = {
    "ct_hud_coins": "the same coin counter plate, but remove the number completely so the plate is empty to the right of the coin icon; keep the coin icon, wood and gold frame" + MAG,
    "ct_hud_hands": "the same hands counter plate, but remove the number completely so the plate is empty next to the icon; keep the icon, wood and gold frame" + MAG,
    "ct_hud_round": "the same round banner plate, but remove all text and all numbers, and show an EMPTY progress bar track (a dark empty channel, no gold fill) inside the banner; keep the wood and gold frame" + MAG,
    "ct_deck_count": "the same small deck count plate, but remove the text completely so the plate is empty; keep the wood and gold frame" + MAG,
    "ct_pill_plain": "the same green pill plate, but remove the text completely so the pill is empty and plain; keep the shape, colour and rim" + MAG,
    "ct_card_back": "a flat playing card back seen straight on, no perspective, no tilt, a portrait rectangle with rounded corners, deep purple with a thin gold border and the same gold crown as the reference in the centre, painted blocky Roblox style" + MAG,
    "ct_table_room": "redraw this whole picture with ALL playing cards, Patron cards, labels, pills, buttons, HUD plates, counters, deck pile and any text removed, so only the tavern room, the crowd (slightly softer and blurrier), the cat on the barrel, the banners, the fireplace glow and the empty felt table remain; same layout, same palette, same lighting; the felt table top is empty and calm",
}
d["concept_t_subjects"] = subs
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(subs))
