#!/usr/bin/env python3
"""One-off: register the hud_kit category in generate_patron_art.py."""
import pathlib
p = pathlib.Path(__file__).resolve().parent / "patron_art" / "generate_patron_art.py"
s = p.read_text()
if '"hud_kit"' in s:
    raise SystemExit("already patched")
s = s.replace('''    "rewards_emblems": ("rewards_emblem_subjects", "rewards_emblems", "RewardsEmblemArt.lua", "Rewards Emblem"),
''', '''    "rewards_emblems": ("rewards_emblem_subjects", "rewards_emblems", "RewardsEmblemArt.lua", "Rewards Emblem"),
    "hud_kit": ("hud_kit_subjects", "hud_kit", "HudKitArt.lua", "HUD Kit"),
''', 1)
opts = '''    # Per-Card-Set HUD kit (keys <setid>__<piece>): medium quality, cut out from magenta; panel frames are made with --quality high.
    # Wide plates use the 3:2 canvas and are trimmed to their alpha box by tools/patron_art/_crop_hud_kit.py before upload.
    "hud_kit": {"quality": "medium", "style_key": "hud_kit_style", "transparent": True, "sizes": {}, "references": {}},
'''
s = s.replace('''    "rewards_emblems": {"quality": "high", "style_key": "house_style", "transparent": True},
''', '''    "rewards_emblems": {"quality": "high", "style_key": "house_style", "transparent": True},
''' + opts, 1)
fill = '''
_KIT_PIECES = ("panel_frame", "banner", "score_track", "reward", "tile", "patron_tray", "purse_row", "icon_target", "icon_tips",
               "icon_hands", "icon_discards", "icon_slot", "btn_volume", "btn_journey", "btn_hand_ref", "btn_settings", "btn_collection")
for _sid, _card in (("meadow_picnic", "kitchen_checks"), ("winter_evening", "winter_frost")):
    for _p in ("banner", "score_track", "reward", "tile", "patron_tray", "purse_row"):
        CATEGORY_OPTS["hud_kit"]["sizes"][_sid + "__" + _p] = "1536x1024"
    CATEGORY_OPTS["hud_kit"]["sizes"][_sid + "__panel_frame"] = "1024x1536"
    for _p in _KIT_PIECES:  # style anchor: the set's own card back (palette and motifs only)
        CATEGORY_OPTS["hud_kit"]["references"][_sid + "__" + _p] = "art-wip/card_backs/" + _card + ".png"

# Rebound by set_category()'''
s = s.replace("\n# Rebound by set_category()", fill, 1)
p.write_text(s)
print("patched")
