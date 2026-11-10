#!/usr/bin/env python3
"""One-off: add prompts for the categories set_panels, ledger_ui and badge_wall to prompts.json.
No generation, no API calls. Generating costs credits: run `generate_patron_art.py generate -c <category>` only for a
queue task marked ALLOWED: generate."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

MAGENTA = ("flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, ")
STYLE = ("blocky painted Roblox tavern style, chunky shapes, painted texture, warm candlelight, original art, "
         "no text, no letters, no numbers, no logos, kid-friendly")

# ---- set_panels: one 9-slice friendly border per Card Set --------------------------------------------------------
PANEL_HEAD = ("a UI panel border designed for 9-slicing, drawn straight on, 3:2 landscape canvas, uniform border thickness "
              "about 6 percent of the canvas on all four sides, evenly repeating rails that stretch cleanly, only small "
              "simple corner brackets no bigger than twice the border thickness, no lanterns, no big corner ornaments, "
              "no characters, the whole center is empty; ")
PANELS = {
    "classic_tavern": "theme: dark oak rails with brass rivets and small brass corner caps, palette: deep brown oak and warm brass",
    "winter_evening": "theme: a frosted garden, frosted silver-blue rails with tiny snowflake corners, palette: icy pale blue, frost white and soft silver",
    "festival_night": "theme: a mountain festival, carved warm wood rails with tiny ribbon corners, palette: warm orange wood with red and gold ribbon",
    "closing_time": "theme: a quiet room at the end of the night, dim dark walnut rails with tiny candle-stub corners, palette: deep brown and dim amber",
    "golden_gala": "theme: a grand gold evening, polished gold rails with tiny star corners, palette: bright gold and cream",
    "meadow_picnic": "theme: a sunny meadow picnic, green vine rails with tiny wildflower corners, palette: leaf green, cream and soft yellow",
    "riverside_evening": "theme: a quiet river at evening, blue-grey driftwood rails with tiny ripple corners, palette: cool blue and weathered wood",
    "summit_camp": "theme: a mountain summit camp, rope-bound pine rails with tiny pennant corners, palette: pine green, rope tan and slate",
    "dune_market": "theme: a golden desert market, sand-colored rails with tiny striped awning corners, palette: sand gold, terracotta and teal stripes",
    "marsh_lanterns": "theme: a misty marsh, mossy reed rails with tiny firefly dot corners, palette: moss green, grey mist and soft yellow glow",
    "snowy_hearth": "theme: a snowy lodge, snow-capped log rails with tiny pine-sprig corners, palette: warm log brown with white snow caps",
    "harbor_lights": "theme: a lantern harbor, rope-wrapped teal planks with tiny anchor corners, palette: sea teal, rope tan and navy",
    "tavern_feast": "theme: a tavern feast, polished banquet wood rails with tiny garland corners, palette: rich brown wood with red and gold",
    "harvest_table": "theme: a harvest moon table, orange-brown wood rails with tiny wheat and leaf corners, palette: pumpkin orange, gold and brown",
    "winter_table": "theme: a cozy winter welcome table, pale pine rails with tiny holly corners, palette: pale wood, holly green and berry red",
}
d["set_panel_subjects"] = {
    k: PANEL_HEAD + v + ", " + MAGENTA + STYLE for k, v in PANELS.items()
}

# ---- ledger_ui ---------------------------------------------------------------------------------------------------
LEDGER = {
    "ledger_desk": ("a dark worn oak tavern desk surface seen from above with warm candle glow, large empty center, a quill and an "
                    "inkwell faintly at the edges, 16:9 landscape", False),
    "ledger_book_open": ("a big open leather-bound ledger book seen from above, two blank cream pages with soft ruled lines and a "
                         "visible binding in the middle, leather cover edges and brass corners, nothing outside the book, 16:10 landscape", True),
    "ledger_bookmark_ribbon": ("a single red silk bookmark ribbon with a brass tip, vertical, hanging straight down", True),
    "ledger_wax_seal_gold": ("a gold wax seal blob with a plain crown emblem pressed into it", True),
    "ledger_wax_seal_red": ("a red wax seal blob with a plain star emblem pressed into it", True),
    "ledger_chalkboard": ("a small framed tavern chalkboard slate, empty and clean, for tally marks, wooden frame", True),
    "ledger_photo_frame": ("a small wooden picture frame with brass corner pins and a faint empty cream photo area", True),
    "ledger_stamp_win": ("a round inked stamp print of a laurel wreath, no text, red ink, slightly rough edges", True),
    "ledger_stamp_loss": ("a round inked stamp print of a cracked mug, no text, faded blue ink, slightly rough edges", True),
    "ledger_quill_inkwell": ("a feather quill standing in a small brass inkwell", True),
    "ledger_paper_note": ("a pinned scrap of parchment note with a brass pin, empty and blank, slightly curled corners", True),
    "ledger_coffee_ring": ("a soft brown coffee ring stain, faint, like a mug was set down on paper", True),
}
d["ledger_ui_subjects"] = {
    k: v[0] + ", " + (MAGENTA if v[1] else "") + STYLE for k, v in LEDGER.items()
}

# ---- badge_wall --------------------------------------------------------------------------------------------------
WALL = {
    "badge_cabinet": ("an empty glass-front tavern trophy cabinet seen straight on, dark oak frame, deep velvet back panel, three "
                      "empty wooden shelves, warm inner light, 16:9 landscape", False),
    "badge_velvet_board": ("a navy velvet display board with gold edging and a grid of tiny brass pins, empty, 16:9 landscape", False),
    "badge_map_board": ("a pinned parchment map board with a cork frame and a few red pins, empty of badges, 16:9 landscape", False),
    "badge_night_sky": ("a deep blue night sky over a tavern roof with soft stars and a crescent moon, empty, 16:9 landscape", False),
    "badge_curio_shelf": ("a curio shelf of dark wood with small hooks and one hanging lantern, empty, 16:9 landscape", False),
    "badge_nameplate": ("a small brass nameplate, empty and blank, with tiny screws at the corners", True),
    "badge_hook_pin": ("a single brass display hook with a round pin head", True),
    "badge_spotlight": ("a soft warm light cone shining downward, glowing golden-white", True),
    "badge_shelf_rail": ("a wooden shelf plank seen from the front, long and thin, dark oak", True),
    "badge_ribbon_banner": ("a header banner ribbon, empty and blank, deep red with gold edges", True),
    "badge_glass_glare": ("a diagonal soft glass reflection streak, pale white glow", True),
}
d["badge_wall_subjects"] = {
    k: v[0] + ", " + (MAGENTA if v[1] else "") + STYLE for k, v in WALL.items()
}

P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print({k: len(d[k]) for k in ("set_panel_subjects", "ledger_ui_subjects", "badge_wall_subjects")})
