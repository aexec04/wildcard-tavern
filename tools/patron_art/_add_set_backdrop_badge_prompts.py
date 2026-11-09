#!/usr/bin/env python3
"""One-off: add prompts for the 8 biome Card Set backdrops (category `set_backdrops`) and the 32 badge icons
(category `badges`: 8 biome + 8 master + 16 rule badges) to prompts.json. No generation, no API calls.
Generating costs credits: run `generate_patron_art.py generate -c set_backdrops|badges` only for a queue task
marked ALLOWED: generate.
"""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

COMP = ("Composition: calm darker center and lower third (soft shadow, ground, no busy detail), interest in the "
        "upper half and the edges, strong dark vignette, clear horizontal light-to-dark flow, wide empty scenery, "
        "no people, no characters, no props where cards would sit, no text, no letters, no logos, kid-friendly")

sets = {
    "meadow_picnic": "wide backdrop, a sunny wildflower meadow picnic spot with a checkered cloth on the grass, butterflies and soft golden light",
    "riverside_evening": "wide backdrop, a quiet riverbank at evening with a wooden footbridge, glowing lanterns on posts and cool blue water",
    "summit_camp": "wide backdrop, a mountain summit camp at dusk with a small campfire glow, tents and pale snowy peaks beyond",
    "dune_market": "wide backdrop, a desert market at sunset with striped awnings, hanging lamps and warm sand dunes",
    "marsh_lanterns": "wide backdrop, a misty marsh at night with floating paper lanterns, lily pads and gentle fireflies",
    "snowy_hearth": "wide backdrop, a snowy cabin porch at dusk with a glowing window, pine boughs and drifting snow",
    "harbor_lights": "wide backdrop, a small harbor at night with moored boats, string lights on the pier and calm teal water",
    "tavern_feast": "wide backdrop, a festive tavern hall with long wooden tables, golden chandeliers, bunting and warm firelight",
}
d["set_backdrop_subjects"] = {k: v + ". " + COMP for k, v in sets.items()}

# Round medal badge icons: single object on a plain dark background (the style_icon prefix), no characters.
biome = {
    "meadow": ("Meadow", "a bouquet of wildflowers"),
    "river": ("River", "a wooden bridge over a stream"),
    "peaks": ("Peaks", "a snowy mountain peak"),
    "desert": ("Dunes", "a sand dune with a small sun"),
    "swamp": ("Marsh", "a lily pad with a tiny frog"),
    "snow": ("Frost", "a large snowflake crystal"),
    "coast": ("Coast", "a small lighthouse on a rock"),
    "tavern": ("Tavern", "a tavern door with a glowing lantern"),
}
badges = {}
for region, (name, thing) in biome.items():
    badges["biome_" + region] = "a round bronze medal badge with " + thing + " embossed in the center, " + name + " road explorer award"
    badges["master_" + region] = ("a round gold medal badge with a laurel wreath around " + thing + ", " + name +
                                  " road master award, richer and shinier than a bronze medal")
rules = {
    "wins_1": "a bronze trophy cup on a small plinth",
    "wins_5": "a silver trophy cup with two handles",
    "wins_25": "a tall gold crown on a cushion with small gems",
    "night_3": "a crescent moon over three small stars",
    "night_5": "a crescent moon over five small stars",
    "night_8": "a golden lantern star with eight rays",
    "night_10": "a purple swirling night sky with a glowing doorway portal",
    "minigame_1": "a single pair of dice with a small gold sparkle",
    "minigame_10": "a fan of playing cards with a gold ribbon",
    "collection_25": "an open book with a small gold bookmark",
    "collection_50": "a stack of two thick books with a gold clasp",
    "collection_100": "a tall bookcase of leather books with a glowing gold star on top",
    "streak_3": "a small campfire flame with three embers",
    "streak_7": "a bright bonfire flame with seven sparks",
    "streak_14": "a big golden flame inside a lantern with a ribbon",
    "season_winter_lanterns": "a red and gold paper lantern with a snowflake and falling snow",
}
for k, v in rules.items():
    badges[k] = "a round medal badge showing " + v
d["badge_subjects"] = badges

P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("added", len(sets), "set backdrop prompts and", len(badges), "badge prompts")
