#!/usr/bin/env python3
"""One-off helper: adds the set_skin_subjects category (6 images for every Card Set) to prompts.json.
Run from the project root: python3 -I tools/_add_set_skin_prompts.py"""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

# set id -> (theme words from the set's name, description and scenery, palette words from its face/accent colours, motif for ornaments)
SETS = {
    "classic_tavern": ("a cozy everyday wooden tavern", "warm cream, honey gold and dark walnut brown", "tiny wooden beams, gold studs and a small lantern"),
    "winter_evening": ("a frosted garden path with lanterns glowing in the snow", "icy pale blue, frost white and soft silver", "snowflakes, frosted leaves and tiny icicles"),
    "festival_night": ("a mountain festival night with lanterns and ribbons", "warm orange, cream and glowing amber", "paper lanterns, ribbons and tiny bunting flags"),
    "closing_time": ("a quiet tavern as the night winds down, dim lamps", "muted brown, dusty tan and low amber", "a small oil lamp, a sleeping candle and wood grain"),
    "golden_gala": ("a tavern dressed in gold for a grand evening", "rich gold, champagne cream and deep amber", "gold filigree, small stars and ribbon bows"),
    "meadow_picnic": ("a sunny wildflower meadow picnic", "soft green, butter yellow and cream", "wildflowers, clover and a checkered cloth pattern"),
    "riverside_evening": ("a quiet riverbank at evening with a footbridge and lanterns", "cool teal, twilight blue and pale mint", "willow leaves, ripples and small hanging lanterns"),
    "summit_camp": ("a mountain summit camp at dusk with a small campfire", "slate grey, pale snow white and ember orange", "pine branches, snowy peaks and a tiny flame"),
    "dune_market": ("a golden desert dune market at sunset", "sandy gold, warm terracotta and cream", "woven cloth patterns, tassels and small crescent shapes"),
    "marsh_lanterns": ("a misty marsh with glowing lanterns", "soft moss green, grey-green mist and warm lantern yellow", "reeds, cattails and tiny floating lanterns"),
    "snowy_hearth": ("a cozy hearth in the snowy hills", "pale blue-white, warm firelight orange and wood brown", "snow-capped logs, a small flame and knitted trim"),
    "harbor_lights": ("a harbor at night with glowing lighthouse lights", "deep sea teal, navy blue and warm lamp yellow", "rope knots, small anchors and tiny shells"),
    "tavern_feast": ("a big tavern feast table", "warm cream, roasted gold and rosy red", "wheat sheaves, bread and fruit leaves"),
    "harvest_table": ("a table dressed for the Harvest Moon", "harvest orange, cream and deep amber", "pumpkin vines, autumn leaves and a small moon"),
    "winter_table": ("a cozy winter welcome table", "cool periwinkle blue, snow white and soft silver", "holly-free pine sprigs, snowflakes and knitted scarf stitches"),
}

COMMON = ("blocky painted Roblox tavern style, chunky shapes, painted texture, warm lantern light, original art, "
          "no text, no letters, no numbers, no logos, kid-friendly")
KEY = ("flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges")

def prompts(theme, palette, motif):
    return {
        "face_frame": f"an ornate playing-card border frame overlay in portrait 5:7 proportion, theme: {theme}, palette: {palette}, decorated with {motif}; only a decorative border running around the edge with corner ornaments, the whole center of the card is empty flat magenta, {KEY}, {COMMON}",
        "face_paper": f"a seamless tileable paper texture for a playing card face, theme: {theme}, palette: {palette}, subtle fibers and faint painted wash, very gentle detail so dark card symbols stay readable, no border, no objects, no focal point, filling the whole frame, {COMMON}",
        "face_court": f"a small symmetrical ornamental crest medallion for the center of a king, queen or jack card, theme: {theme}, palette: {palette}, made of {motif} around a tiny crown, single isolated emblem centered with generous margin, {KEY}, {COMMON}",
        "panel_frame": f"a wide ornate UI panel border frame with decorative corner ornaments, theme: {theme}, palette: {palette}, decorated with {motif}; only the border and corners are drawn, the whole center is empty flat magenta, {KEY}, {COMMON}",
        "button_plate": f"a wide slim ornate button plate border with rounded ends, theme: {theme}, palette: {palette}, decorated with {motif}; only a thin border plate, the whole center is empty flat magenta, {KEY}, {COMMON}",
        "tab_plate": f"a small tab plaque border shaped like a short rounded rectangle, theme: {theme}, palette: {palette}, with a tiny accent of {motif}; only a thin border, the whole center is empty flat magenta, {KEY}, {COMMON}",
    }

out = {}
for sid, (theme, palette, motif) in SETS.items():
    for slot, text in prompts(theme, palette, motif).items():
        out[f"{sid}_{slot}"] = text
d["set_skin_subjects"] = out
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(len(out), "set skin prompts")
