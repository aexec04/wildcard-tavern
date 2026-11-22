"""Adds the News panel notice board scene prompts (news_room_a/_b) to prompts.json panel_scene_subjects."""
import json
import pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

HEAD = ("the same warm timber-framed tavern as the main room, a tavern notice board wall, seen straight on and flat (no perspective skew), "
        "filling the whole 16:9 frame, dark vignette corners, warm candle and lantern glow from the corners, calm low contrast. ")
TAIL = (" Every pinned note area and banner completely EMPTY and blank so art and text can be placed on it, no people, no characters, "
        "no cards, no coins, no text, no letters, no numbers. Style: blocky painted Roblox tavern style, chunky shapes, painted texture, "
        "matte, calm, low contrast, soft warm light, warm dark wood palette, original art, no text, no letters, no numbers, "
        "no logos, kid-friendly.")

new = {
    "news_room_a": HEAD +
        "A big dark wood frame around an aged cork board. At the TOP CENTER a hanging blank cloth banner on two small chains for the title, "
        "with a blank pale parchment strip just under it. In the MIDDLE a row of 3 large, evenly spaced, identical blank pale parchment "
        "note areas, each held by a single round brass pin, with clear cork gaps between them. Across the BOTTOM a small wooden shelf ledge "
        "with one empty blank wooden plaque in the center. A small lantern in the left corner and a candle in the right corner." + TAIL,
    "news_room_b": HEAD +
        "A tall dark wood frame around a weathered cork board with faint pin holes. At the TOP CENTER a blank wooden sign board hanging from "
        "two ropes for the title, with a blank pale parchment strip under it. In the MIDDLE a row of 3 large, evenly spaced, identical blank "
        "pale parchment notes, each with its own round brass pin, wide clear gaps between them. At the BOTTOM a narrow shelf ledge with one "
        "empty blank brass plaque in the center. Warm lantern glow in both lower corners." + TAIL,
}
d["panel_scene_subjects"].update(new)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("added", len(new))
