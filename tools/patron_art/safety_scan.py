#!/usr/bin/env python3
"""Scan prompts.json for words that Roblox moderation may dislike.

Usage: python3 tools/patron_art/safety_scan.py [--words] [--keys]
Prints one line per risky prompt: section, key, matched words. Read only.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# words that must never appear, even in "no X" form (test enforced)
BANNED = ["beer", "ale", "wine", "whiskey", "whisky", "rum", "liquor", "cigar", "cigarette",
          "tobacco", "skull", "blood", "gun", "pipe smoke"]
# wider watch list for the audit report only
WATCH = ["ales", "pipe", "pipes", "smoke", "smoking", "skulls", "guns", "keg", "kegs", "barrel", "barrels",
         "bottle", "bottles", "mug", "mugs", "tankard", "tankards", "goblet", "goblets", "toast", "toasts",
         "chips", "cash", "dagger", "sword", "swords", "knife", "knives", "pistol", "weapon", "weapons",
         "drunk", "mead", "cider", "cocktail", "gore", "gambling", "bet", "bets"]


def pattern(words):
    return re.compile(r"\b(" + "|".join(re.escape(w) for w in sorted(words, key=len, reverse=True)) + r")\b", re.I)


def walk(node, path=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, path + "/" + k)
    elif isinstance(node, str):
        yield path, node


def scan(words):
    data = json.loads((HERE / "prompts.json").read_text())
    pat = pattern(words)
    out = []
    for path, text in walk(data):
        found = sorted({m.group(1).lower() for m in pat.finditer(text)})
        if found:
            out.append((path, found, text))
    return out


if __name__ == "__main__":
    which = BANNED if "--banned" in sys.argv else BANNED + WATCH
    rows = scan(which)
    for path, found, text in rows:
        if "--full" in sys.argv:
            print(path, found, "::", text[:400])
        else:
            print(path, ",".join(found))
    print(len(rows), "prompts flagged")
