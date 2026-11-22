#!/usr/bin/env python3
"""Trim the three Golden Gala plates to their alpha box and resize each to the exact classic plate size (keeps nine-slice insets valid).
Writes a preview sheet to art-wip/painted_kit/_gala_plates_preview.png. Usage: python3 -I tools/_gala_plate_fit.py"""
import pathlib
from PIL import Image

R = pathlib.Path(__file__).resolve().parents[1] / "art-wip" / "painted_kit"
WANT = {"pk_gala_btn_dark": (1382, 402), "pk_gala_btn_green": (1498, 410), "pk_gala_orn_btn_green": (1348, 562)}
sheet = Image.new("RGB", (1600, 1500), (70, 55, 50))
y = 10
for k, sz in WANT.items():
    im = Image.open(R / (k + ".png")).convert("RGBA")
    print(k, "raw", im.size, "corner px", im.getpixel((2, 2)))
    box = im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    if not box:
        print("EMPTY", k)
        continue
    im = im.crop(box)
    print(k, "trimmed", im.size, "target", sz, "aspect", round(im.width / im.height, 2), "vs", round(sz[0] / sz[1], 2))
    im = im.resize(sz, Image.LANCZOS)
    im.save(R / (k + ".png"))
    sheet.paste(im, (10, y), im)
    y += sz[1] + 20
sheet.save(R / "_gala_plates_preview.png")
print("ok")
