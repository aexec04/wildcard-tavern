#!/usr/bin/env python3
"""One-off: add the badge_sockets prompts (category `badge_sockets`) to prompts.json. No API calls."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

TAIL = (", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges, "
        "blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, same warm "
        "tavern palette, original art, no text, no letters, no numbers, no logos, kid-friendly")

d["badge_socket_subjects"] = {
    "badge_socket_road": "a carved stone waypost base seen straight on with a round empty recess in the middle, square 1:1 composition, centered" + TAIL,
    "badge_socket_shelf": "a wooden shelf bracket seen straight on with a round felt-lined empty recess, square 1:1 composition, centered" + TAIL,
    "badge_socket_niche": "a round carved niche in a dark wood wall panel with a small brass rim, empty inside, seen straight on, square 1:1 composition, centered" + TAIL,
    "badge_socket_star": "a small brass constellation node ring with tiny rivets, hollow center, seen straight on, square 1:1 composition, centered" + TAIL,
    "badge_path_dash": "a short painted dotted path segment tile, a few evenly spaced dashes in a horizontal line, wide 3:1 composition, centered" + TAIL,
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["badge_socket_subjects"]))
