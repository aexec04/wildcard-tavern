#!/usr/bin/env python3
"""Trim every art-wip/painted_kit/pk_*.png to its alpha box (the round icon is padded back to a square). Idempotent.
Usage: python3 -I tools/painted_kit_trim.py [folder]"""
import pathlib
import sys

from PIL import Image

root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1] / "art-wip" / "painted_kit"
for f in sorted(root.glob("pk_*.png")):
    im = Image.open(f).convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    if not box:
        print("EMPTY", f.name)
        continue
    im = im.crop(box)
    if f.stem == "pk_icon_round":
        side = max(im.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = sq
    im.save(f)
    print(f.name, im.size)
