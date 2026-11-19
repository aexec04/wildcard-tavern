#!/usr/bin/env python3
"""Cut the side flourishes off the two button frames so the plate is symmetric (nothing squashed into a corner cap).
Reads art-wip/painted_kit/pk_btn_dark.png and pk_btn_green.png (originals stay), writes pk_btn_dark_p.png and pk_btn_green_p.png
and prints the left and right border brightness. Usage: python3 -I tools/painted_kit_plain.py"""
import pathlib

import numpy as np
from PIL import Image

root = pathlib.Path(__file__).resolve().parents[1] / "art-wip" / "painted_kit"
for name in ("pk_btn_dark", "pk_btn_green"):
    im = Image.open(root / f"{name}.png").convert("RGBA")
    a = np.asarray(im.getchannel("A")) > 16
    h = a.shape[0]
    cover = a.sum(axis=0) / h
    cols = np.where(cover > 0.55)[0]  # the plate body is tall; the flourishes only cover the middle band
    shave = 10  # the last few columns still hold the tips of the flourishes
    out = im.crop((int(cols.min()) + shave, 0, int(cols.max()) + 1 - shave, h))
    box = out.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    out = out.crop(box)
    out.save(root / f"{name}_p.png")
    arr = np.asarray(out).astype(float)
    w = out.width
    band = max(8, w // 40)

    def lum(s):
        return float(s[:, :, :3].mean())

    print(name, im.size, "->", out.size, "left lum %.1f right lum %.1f" % (lum(arr[:, :band]), lum(arr[:, -band:])))
