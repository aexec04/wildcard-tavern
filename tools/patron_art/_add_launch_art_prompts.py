#!/usr/bin/env python3
"""One-off: add launch_art_style and launch_art_subjects to prompts.json (thumbnails, icons, pass and product icons).
No API calls. Generating costs credits: `generate_patron_art.py launch_art` only for a queue task marked ALLOWED: generate."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

d["launch_art_style"] = ("painted game art style, blocky Roblox tavern look, rich purple and gold palette, warm lantern glow, "
                         "bold clear shapes, kid-friendly, no text, no letters, no numbers, no logos, no watermark, "
                         "no drinks, no real people, original art")
ICON = "square icon, one clear subject centred, readable at 64 px, deep purple background with a soft golden glow, bold outlines. "
WIDE = ", wide shot, keep the left third calm and empty"
d["launch_art_subjects"] = {
    "thumb_1": "a cozy fantasy tavern table at night, warm lantern glow, a fan of five ivory playing cards with gold edges in the centre, gold coins and a purple velvet cloth" + WIDE,
    "thumb_2": "a cheerful blocky Roblox-style tavern keeper holding a golden crown over a table of cards, coins spilling out of a treasure chest, hanging purple banners, candlelight, celebratory mood" + WIDE,
    "thumb_3": "three quirky fantasy characters (a wizard, a knight and a cat in a hat) sitting around a card table, each with a glowing playing card, warm lanterns, wooden beams, painted storybook style, a bare stone wall with one window on the left and no furniture, props or containers other than the table and chairs" + WIDE,
    "thumb_4": "a giant friendly boss character (an ogre in a chef hat) looming over a small card table with a royal flush of cards glowing gold, dramatic but not scary, purple and gold lighting" + WIDE,
    "thumb_5": "an ice tavern variant: frosty blue walls, icicles on beams, frozen crates, cold lantern light, a fan of cards on the table with snowflakes" + WIDE,
    "icon_1": ICON + "a single ivory playing card with a gold crown emblem and gold edge, tilted slightly",
    "icon_2": ICON + "a golden knave (jack) card figure wearing a small crown, with a gold coin behind it",
    "pass_vip": ICON + "a big glowing gold star",
    "pass_music_pack": ICON + "a golden music note",
    "pass_starter_pack": ICON + "a gift box with a playing card and a ribbon",
    "pass_card_set_bundle": ICON + "two fanned card backs, purple and gold",
    "pass_flair_bundle": ICON + "a gift box with sparkles",
    "pass_rainbow_numbers": ICON + "a glowing score display showing the digits 1 2 3 4 in rainbow colours, one digit per colour, soft rounded bubble digits",
    "pass_ribbon_trail": ICON + "colourful ribbons curling in a trail behind a playing card",
    "pass_crown_flash": ICON + "a gold crown with a bright flash of light",
    "pass_star_aura": ICON + "a glowing ring of stars, a star aura",
    "pass_harvest_moon": ICON + "a big harvest moon rising over a golden field",
    "pass_winter_welcome": ICON + "a snowflake with a cozy scarf",
    "pass_one_more_round": ICON + "a playing card with a circular arrow around it",
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(len(d["launch_art_subjects"]))
