#!/usr/bin/env python3
"""Trim every art-wip/hud_kit PNG to its alpha box (icons and buttons are padded back to a square). Run before upload. Idempotent.
Usage: python3 -I tools/patron_art/_crop_hud_kit.py [folder]"""
import pathlib, sys
from PIL import Image

root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / "art-wip" / "hud_kit"
for f in sorted(root.glob("*__*.png")):
    im = Image.open(f).convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    if not box:
        print("EMPTY", f.name)
        continue
    im = im.crop(box)
    piece = f.stem.split("__", 1)[1]
    if piece.startswith(("icon_", "btn_")):
        side = max(im.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = sq
    im.save(f)
    print(f.name, im.size)
