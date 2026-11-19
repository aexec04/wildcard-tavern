#!/usr/bin/env python3
"""Slice art-wip/painted_kit/pk_w_icons.png (3 x 2 sheet of round icons) into six square icon files and register them as painted_kit prompts
(so upload and lua pick them up; generation skips them because the files exist). Idempotent. No API calls.
Usage: python3 -I tools/painted_kit_icons.py"""
import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
FOLDER = ROOT / "art-wip" / "painted_kit"
NAMES = ["speaker", "pause", "bulb", "bars", "spade", "crown"]

sheet = Image.open(FOLDER / "pk_w_icons.png").convert("RGBA")
alpha = sheet.getchannel("A").point(lambda a: 255 if a > 16 else 0)
w, h = sheet.size
out = []
for i, name in enumerate(NAMES):
    col, row = i % 3, i // 3
    cell = (col * w // 3, row * h // 2, (col + 1) * w // 3, (row + 1) * h // 2)
    box = alpha.crop(cell).getbbox()
    if not box:
        raise SystemExit("empty cell " + name)
    im = sheet.crop((cell[0] + box[0], cell[1] + box[1], cell[0] + box[2], cell[1] + box[3]))
    side = max(im.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    sq = sq.resize((512, 512), Image.LANCZOS)
    key = "pk_w_icon_" + name
    sq.save(FOLDER / (key + ".png"))
    out.append(key)
    print(key, sq.size)

P = ROOT / "tools" / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
for k in out:
    d["pk_subjects"].setdefault(k, "cut from pk_w_icons by tools/painted_kit_icons.py (not generated)")
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
