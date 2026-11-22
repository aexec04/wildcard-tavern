"""Adds the Legend, Card Sets and Stats panel scene prompts (pairs _a/_b) to prompts.json panel_scene_subjects."""
import json
import pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

HEAD = ("the same warm timber-framed tavern as the main room, {scene}, seen straight on and flat (no perspective skew), "
        "filling the whole 16:9 frame, dark vignette corners, warm lantern light from the sides, calm low contrast. ")
TAIL = (" Every slot completely EMPTY so art and text can be placed in it, no people, no characters, no cards, no coins, "
        "no text, no letters, no numbers. Style: blocky painted Roblox tavern style, chunky shapes, painted texture, matte, "
        "calm, low contrast, soft warm light, warm dark wood palette, original art, no text, no letters, no numbers, "
        "no logos, kid-friendly.")

new = {
    "legend_room_a": HEAD.format(scene="a quiet trophy hall") +
        "In the MIDDLE a wide recessed display alcove in a carved wooden frame with an empty dark velvet back and a low empty stand, "
        "big enough to show one card back. Along the BOTTOM a row of 5 evenly spaced empty blank brass plaques on a dark wood rail. "
        "On the RIGHT a tall wooden shelf unit with 3 evenly spaced empty recessed shelf slots for titles." + TAIL,
    "legend_room_b": HEAD.format(scene="a quiet trophy hall with a stone arch") +
        "A tall central stone-arched niche with an empty dark velvet back and a small empty pedestal for one card back. "
        "On the LEFT a column of 5 empty blank brass plaques stacked evenly on a wooden board. "
        "On the RIGHT a wall shelf with 3 evenly spaced empty recessed slots for titles." + TAIL,
    "cardsets_room_a": HEAD.format(scene="a tailor and card maker's shelf wall") +
        "Across the TOP a row of empty blank wooden tab plates. Below it a wide wooden shelf wall with a regular grid of 5 columns by "
        "2 rows of identical EMPTY framed slots with dark velvet backs, evenly spaced with clear gaps, and under each slot a small "
        "empty blank brass price plaque. Spools of thread and a measuring tape only at the far edges, nothing inside the slots." + TAIL,
    "cardsets_room_b": HEAD.format(scene="a card maker's workshop wall with a pegboard") +
        "Across the TOP a strip of empty blank brass tab plates. Below it a dark wooden display case with 5 columns by 2 rows of "
        "identical EMPTY glass-fronted compartments with velvet backs, evenly spaced, and under each compartment a small empty blank "
        "wooden price tag." + TAIL,
    "stats_room_a": HEAD.format(scene="a ledger desk in a quiet corner of the tavern") +
        "In the MIDDLE a large open ledger book lying on the desk with two completely blank pale parchment pages as the main empty area. "
        "ABOVE it three evenly spaced empty blank small brass plaques on the wall. BELOW the desk a row of 6 empty recessed wooden "
        "shelf slots for streak and best-run items. A candle and inkwell only at the far edges." + TAIL,
    "stats_room_b": HEAD.format(scene="a clerk's counter in a quiet corner of the tavern") +
        "A wide open ledger book on a sloped reading stand with two completely blank pale parchment pages as the main empty area. "
        "Above it three empty blank round brass plaques on a beam. At the bottom a long shelf with a row of 6 empty recessed slots." + TAIL,
}
d["panel_scene_subjects"].update(new)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("added", len(new))
