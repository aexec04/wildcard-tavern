#!/usr/bin/env python3
"""One-off: add the hud_kit prompts (per-Card-Set HUD kit, phase 1: two sets). No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
d["hud_kit_style"] = ("Blocky painted Roblox tavern UI art, chunky shapes, painted texture, matte, calm, low contrast, soft light, "
                      "original art, no text, no letters, no numbers, no logos, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
SETS = {
    "meadow_picnic": dict(
        theme="a sunny wildflower meadow picnic", pal="soft green, butter yellow and cream",
        mat="woven wicker basket rim, gingham picnic cloth, clover leaves and small daisies",
        btn="a round woven wicker ring with a small daisy at the top"),
    "winter_evening": dict(
        theme="a frosted garden path with lanterns glowing in the snow", pal="icy pale blue, frost white and soft silver",
        mat="frosted glass, ice crystals, snowflakes and tiny icicles",
        btn="a faceted round frosted-glass medallion with a small ice crystal at the top"),
}
ICON = "one isolated object centred with generous margin, simple readable silhouette at 48 px"
BTN = "one isolated round object centred with generous margin, flat front view, calm low contrast, readable at 48 px"


def pieces(s):
    t, p, m = s["theme"], s["pal"], s["mat"]
    th = f"theme: {t}, palette: {p}, made of {m}"
    b = s["btn"]
    return {
        "panel_frame": f"a tall ornate UI side panel frame in portrait proportion, {th}; only the border and four corner ornaments are drawn, the whole inside is empty flat magenta",
        "banner": f"a wide slim header plate for a round title, rounded ends, a solid {p} surface with a light inner highlight and a soft inner shadow, {th}, empty plate with nothing on it, centred on the canvas",
        "score_track": f"a wide empty progress bar trough, rounded ends, a sunken darker channel inside a raised rim, {th}, nothing inside the channel, centred on the canvas",
        "reward": f"a wide slim reward line plate, rounded ends, a solid surface with a subtle rim, {th}, empty plate with nothing on it, centred on the canvas",
        "tile": f"a small square-ish stat tile plate with rounded corners, a solid surface with a soft inner shadow and a thin rim, {th}, empty tile with nothing on it, centred on the canvas",
        "patron_tray": f"a wide shallow tray for holding small round seats, a raised rim with a soft recessed floor, {th}, empty with nothing in it, centred on the canvas",
        "purse_row": f"a wide slim bottom bar plate for a coin purse and a blessing chip, rounded ends, a solid surface with a thin rim, {th}, empty plate with nothing on it, centred on the canvas",
        "icon_target": f"a single small icon of a round target with an arrow in the middle, {th}, {ICON}",
        "icon_tips": f"a single small icon of a coin pouch tied with a string, {th}, {ICON}",
        "icon_hands": f"a single small icon of a fanned hand of three playing cards, {th}, {ICON}",
        "icon_discards": f"a single small icon of two playing cards tossed away with a small curved arrow, {th}, {ICON}",
        "icon_slot": f"a single empty round seat ring for a patron portrait, a raised rim with a soft recessed centre, {th}, one isolated object centred with generous margin",
        "btn_volume": f"a round UI button face: {b}, with a small speaker with sound waves painted in the middle, {th}, {BTN}",
        "btn_journey": f"a round UI button face: {b}, with a small folded map and a tiny route line painted in the middle, {th}, {BTN}",
        "btn_hand_ref": f"a round UI button face: {b}, with a small open book painted in the middle, {th}, {BTN}",
        "btn_settings": f"a round UI button face: {b}, with a small cog wheel painted in the middle, {th}, {BTN}",
        "btn_collection": f"a round UI button face: {b}, with a small closed album book with a ribbon painted in the middle, {th}, {BTN}",
    }


out = {}
for sid, s in SETS.items():
    for piece, text in pieces(s).items():
        out[f"{sid}__{piece}"] = text + MAG
d["hud_kit_subjects"] = out
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(out))
