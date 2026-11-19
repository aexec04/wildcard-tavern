#!/usr/bin/env python3
"""One-off: add the painted_kit prompts (reusable 9-slice friendly UI frames, no text) and register the category. No API calls."""
import json, pathlib

HERE = pathlib.Path(__file__).resolve().parent
P = HERE / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
d["pk_style"] = ("Edit the reference image. Redraw ONE user interface piece from it in exactly the same hand-painted blocky Roblox tavern style: "
                 "carved dark wood, gold filigree corner ornaments, warm candlelit palette, thick clean outline. Original art, kid-friendly, "
                 "no letters, no numbers, no text, no icons inside, the centre of the piece EMPTY and flat so it can be stretched. "
                 "Flat front view, no perspective, no shadow outside the piece")
MAG = ", on a flat solid pure magenta #FF00FF background with no gradient, clean sharp edges, the piece centred with generous margin"
subs = {
    "pk_wood_plate": "the dark carved wood plate frame used for the Target and Tips plates: a wide rounded rectangle, dark wood centre, gold filigree corners" + MAG,
    "pk_parchment": "the cream parchment scroll plate used for the boss rule, a wide rounded scroll with a red wax seal at the top centre, empty cream centre" + MAG,
    "pk_btn_green": "the green embossed Play Hand button shape, wide rounded rectangle with gold corner ornaments, completely blank, no words" + MAG,
    "pk_btn_dark": "the dark brown embossed Discard button shape, wide rounded rectangle with gold corner ornaments, completely blank, no words" + MAG,
    "pk_icon_round": "one round gold rimmed icon button, a circle with a dark wood face and a gold ring, completely empty inside, no icon" + MAG,
    "pk_count_tab": "the small wooden count tab used for Hands and Discards, a short wide rounded wooden tab with a thin gold edge, blank" + MAG,
    "pk_patron_slot": "one empty framed Patron slot, a tall rounded dark panel with a gold frame and a faint small ornament in the middle" + MAG,
    "pk_score_frame": "the ornate framed Score plate, a wide dark wood plate with gold end caps on the left and right, empty centre" + MAG,
}
d["pk_subjects"] = subs
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

G = HERE / "generate_patron_art.py"
s = G.read_text(encoding="utf-8")
if '"painted_kit"' not in s:
    s = s.replace('    "concept_t_faces": ("ctf_subjects",',
                  '    "painted_kit": ("pk_subjects", "painted_kit", "PaintedKitArt.lua", "Painted UI kit"),\n    "concept_t_faces": ("ctf_subjects",', 1)
    keys = ", ".join('"%s"' % k for k in subs)
    opt = ('    # Painted UI kit: nine-slice friendly frames, each an EDIT of the table mockup, cut from magenta, trimmed to the alpha box by tools/painted_kit_trim.py\n'
           '    "painted_kit": {"quality": "medium", "style_key": "pk_style", "transparent": True, "size": "1536x1024",\n'
           '                    "references": dict((k, "claude/reference/concept-table-reference.png") for k in (' + keys + '))},\n')
    s = s.replace('    "concept_t_faces": {"quality": "low",', opt + '    "concept_t_faces": {"quality": "low",', 1)
    G.write_text(s, encoding="utf-8")
print("ok", len(subs))
