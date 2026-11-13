#!/usr/bin/env python3
"""One-off: add three candidate prompts for the painted Patron Nook strip to play_scene_subjects. No API calls."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
text = P.read_text(encoding="utf-8")
d = json.loads(text)
BASE = ("A wide painted wooden display ledge for a tavern card table, seen straight on and flat, a very wide horizontal strip "
        "about 5 to 1, centred, with a flat solid pure magenta #FF00FF background around it. Five equal shallow arched alcoves "
        "in a row carved into dark recessed back wood, a carved wooden ledge in front with brass trim, a warm lantern glow along "
        "the top edge, wood grain and warm brown tones matching a dark oak tavern table rim, soft irregular worn edges, the "
        "bottom edge is a plain wooden lip that can tuck under a row of cards. The alcoves are empty. No text, no letters, no "
        "numbers, no characters, no cards, no UI, kid-friendly, original art. ")
VAR = {
    "play_nook_strip_a": "Slightly curved like the far rim of a round table, arches with small brass keystones.",
    "play_nook_strip_b": "Gently bowed upward in the middle, plain rounded alcoves, rope-wrapped brass trim, hanging lantern light.",
    "play_nook_strip_c": "Straight ledge with chunky carved corner posts, rounded alcoves, small brass rivets, warm candle glow.",
}
for k, v in VAR.items():
    d["play_scene_subjects"][k] = BASE + v
indent = 2 if text.startswith("{\n  ") else 1
P.write_text(json.dumps(d, indent=indent, ensure_ascii=False) + "\n", encoding="utf-8")
