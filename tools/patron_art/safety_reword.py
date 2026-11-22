#!/usr/bin/env python3
"""One-off: reword risky phrases in prompts.json (kid and Roblox safe). Safe to rerun."""
import json
import re
from pathlib import Path

P = Path(__file__).resolve().parent / "prompts.json"

# ordered; plain string replacements first, regex after
PLAIN = [
    ("no barrels, mugs, bottles or drinks anywhere", "only the described trim and nothing else"),
    ("Everything empty: no cards, no chips, no people", "Everything empty: no cards, no coins, no people"),
    ("raising a toast with cocoa mugs", "cheering with cocoa cups"),
    ("clinking cocoa mugs", "clinking cocoa cups"),
    ("raised mugs of cocoa", "raised cups of cocoa"),
    ("frozen barrels and crates", "frozen crates and sacks"),
    ("frozen barrels", "frozen crates"),
    ("stacked barrels of apples", "stacked crates of apples"),
    ("a wooden counter and barrels", "a wooden counter and crates"),
    ("shelves with jars and goblets", "shelves with jars and trophies"),
    ("gold goblet trophy", "gold trophy cup"),
    ("golden goblet trophy", "golden trophy cup"),
    ("old bottle-shaped jar", "old round jar"),
    ("dusty old bottle of syrup", "dusty old jar of syrup"),
    ("plain bottles and jars", "plain jars"),
    ("poker chips", "gold coins"),
    ("pile of golden chips", "pile of golden coins"),
    ("two or three tiny chips remaining", "two or three tiny crisps remaining"),
    ("a ruler and knife", "a ruler and cake server"),
    ("two crossed small swords", "two crossed small brass keys"),
    ("a trail of smoke from", "a trail of soft sparkles from"),
    ("space above the chimney for smoke", "space above the chimney for drifting sparkles"),
    ("brass pipes", "brass horns"),
    ("Outfit colour: wine red", "Outfit colour: burgundy red"),
    ("Not dark, no skulls, no hooded figures, no weapons", "Not dark, friendly and cheerful, no hooded figures"),
    ("not dark, no weapons", "not dark, friendly and cheerful"),
    ("original fictional characters, no weapons, no blood, no skulls, no real people", "original fictional characters, friendly and gentle"),
    ("barrel", "crate"),
    ("barrels", "crates"),
]

REGEX = [
    (r"\bmugs\b", "cups"),
    (r"\bmug\b", "cup"),
]


def fix(text):
    for a, b in PLAIN:
        text = text.replace(a, b)
    # longer first so "barrels" is not half-eaten by "barrel"
    text = text.replace("crates", "crates")
    for pat, rep in REGEX:
        text = re.sub(pat, rep, text)
    return text


def main():
    raw = P.read_text()
    new = fix(raw)
    json.loads(new)  # must stay valid
    P.write_text(new)
    print("changed" if new != raw else "no change")


if __name__ == "__main__":
    main()
