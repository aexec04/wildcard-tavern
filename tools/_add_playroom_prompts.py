"""One-off: add play_room_<setId>_bg / _front prompts (play_scene category) for the 14 non-classic Card Sets
and register them in the generator's play_scene options. Idempotent."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PJ = ROOT / "tools" / "patron_art" / "prompts.json"
GEN = ROOT / "tools" / "patron_art" / "generate_patron_art.py"

# setId -> (theme line, felt colour, wood colour)
SETS = {
    "winter_evening": ("a snowy garden pavilion with frost on the beams and snow falling outside open arches", "pale icy blue", "pale frosted grey-brown"),
    "festival_night": ("a mountain lodge hung with festival paper lanterns and colourful bunting, mountain night through the window", "deep midnight pine green leaning blue", "warm honey"),
    "closing_time": ("an empty late-night tavern, stools turned up on the other tables, everything dim and sleepy", "dark muted green", "dark worn brown"),
    "golden_gala": ("a gilded ballroom with gold columns, chandeliers and heavy curtains", "deep red", "dark wood with a gold-leaf inlay"),
    "meadow_picnic": ("a sunny flower meadow with a picnic table under a tree, a checkered cloth draped on the rim", "bright fresh green", "light honey oak"),
    "riverside_evening": ("a riverside terrace at dusk, calm water and strung lanterns reflecting in it", "deep teal", "weathered grey-blue driftwood"),
    "summit_camp": ("a mountain camp with a canvas tent, pine trees and a small campfire glow", "forest green", "rough pine"),
    "dune_market": ("a desert bazaar with sand-coloured stone, striped fabric awnings and hanging brass lamps", "warm terracotta orange", "sun-bleached sandy"),
    "marsh_lanterns": ("a misty marsh dock with hanging lanterns, moss and reeds", "mossy swamp green", "dark damp mossy"),
    "snowy_hearth": ("a cosy cabin with a big stone fireplace blazing, snow outside the window", "warm deep red-brown", "rich dark red-brown"),
    "harbor_lights": ("a harbor tavern with coiled ropes, nets and lanterns on the dock outside", "navy blue", "salt-weathered grey-brown"),
    "tavern_feast": ("a long feast hall with many candles and laden tables far behind", "rich burgundy", "warm polished brown"),
    "harvest_table": ("a barn with pumpkins, hay bales and hanging corn", "autumn olive-gold green", "warm orange-brown barn"),
    "winter_table": ("a winter holiday room with pine garlands, ribbons and warm string lights", "festive deep green", "warm cinnamon"),
}

TAIL_BG = ("The felt centre is empty and the lower third of the frame is clear for a hand tray. Matching thick wood rim all the way round. "
           "No text, no characters, no cards, no UI, no people.")


def bg(theme, felt, wood):
    return ("The inside of a cozy room seen from the player seat, painted in a warm painterly style. The setting is %s. "
            "A big oval card table with a deep %s felt top and a thick %s wood rim all the way round, soft light on the felt, "
            "dark vignette corners, the room dim and out of focus behind. %s" % (theme, felt, wood, TAIL_BG))


def front(theme, felt, wood):
    return ("Only the near wood front of a round-cornered card table seen from the player seat, straight on and flat, filling the bottom 40 percent of the frame only. "
            "Everything above the front rim is flat solid pure magenta #FF00FF background: no felt, no stitching, no table top, no rim along the top. "
            "A thick carved %s wooden front rim with visible wood grain running across the width, one long empty rounded wooden groove (a hand rail) whose left end is at 20 percent of the image width and right end at 80 percent, "
            "with its top at 76 percent of the image height and its bottom at 85 percent, one empty square recess for a deck box at the right whose left edge is at 81 percent of the width, right edge at 98 percent, "
            "top at 66 percent of the height and bottom at 80 percent, and a wide wood grain apron below the front rim. "
            "The wood continues an oval table rim in %s with a hint of the %s felt colour. Nothing else is painted: no room, no walls, no windows, no lanterns, no decorations. "
            "Blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, original art, no text, no letters, no numbers, no logos, kid-friendly. "
            "Everything empty: no cards, no chips, no people, no felt, flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
            % (wood, wood, felt))


def main():
    data = json.loads(PJ.read_text(encoding="utf-8"))
    subj = data["play_scene_subjects"]
    for sid, (theme, felt, wood) in SETS.items():
        subj["play_room_%s_bg" % sid] = bg(theme, felt, wood)
        if sid != "winter_evening":  # its front is already generated and uploaded
            subj["play_room_%s_front" % sid] = front(theme, felt, wood)
    PJ.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    src = GEN.read_text(encoding="utf-8")
    marker = "# ===== per-set play rooms ====="
    if marker not in src:
        block = (marker + "\n"
                 "for _sid in %r:\n"
                 "    _o = CATEGORY_OPTS[\"play_scene\"]\n"
                 "    _o[\"opaque\"].append(\"play_room_%%s_bg\" %% _sid)\n"
                 "    for _suf in (\"bg\", \"front\"):\n"
                 "        _o[\"sizes\"][\"play_room_%%s_%%s\" %% (_sid, _suf)] = \"1536x1024\"\n"
                 "    _o[\"references\"][\"play_room_%%s_bg\" %% _sid] = \"art-wip/play_scene/play_table_bg_b.png\"\n"
                 "    _o[\"references\"][\"play_room_%%s_front\" %% _sid] = \"art-wip/play_scene/play_table_front_c.png\"\n\n"
                 % (list(SETS),))
        anchor = "# set_skins: one id per"
        assert anchor in src
        src = src.replace(anchor, block + anchor, 1)
        GEN.write_text(src, encoding="utf-8")
    print("ok", len(SETS) * 2)


if __name__ == "__main__":
    main()
