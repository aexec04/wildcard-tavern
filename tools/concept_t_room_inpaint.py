"""Build the Concept T room plate FROM claude/reference/concept_t/full_reference.png by inpainting only the UI holes.
Everything outside the holes stays pixel identical to the reference (the original is composited back over the result).
Usage: python3 tools/concept_t_room_inpaint.py            (2 edit calls, medium quality, about 0.10 USD)
Writes art-wip/concept_t/ct_table_room_new.png; masks and raw results go to art-wip/concept_t/tmp/room_inpaint/.
The key comes from tools/patron_art/.env and is never printed.
"""
import base64
import io
import os
import pathlib
import sys

import numpy as np
import requests
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
REF = ROOT / "claude/reference/concept_t/full_reference.png"
OUT = ROOT / "art-wip/concept_t"
TMP = OUT / "tmp/room_inpaint"

# holes in reference pixels (x0, y0, x1, y1), a few px wider than the UI piece
TOP = [(8, 8, 330, 104), (566, 0, 962, 94), (1402, 4, 1518, 118), (276, 142, 1246, 512)]
BOTTOM = [(596, 552, 944, 704), (292, 688, 1214, 1014), (1212, 656, 1512, 952)]

STYLE = ("Fill ONLY the transparent areas so the picture continues seamlessly: the same warm hand-painted blocky Roblox tavern, "
         "same palette, same candle light. Show the room behind where the interface was: wooden beams and walls, hanging purple banners, "
         "the iron chandelier with candles, the blurred seated crowd, a wooden plank floor. In the lower middle a large dark red woven rug "
         "on the wooden floor, empty. Absolutely NO cards, NO text, NO letters or numbers, NO buttons, NO icons, NO plates, NO frames, "
         "NO coins, NO drinks, mugs or bottles in the filled areas. Keep the painted pixel-block texture.")
BOTTOM_NOTE = " At the bottom right: plain wooden floor and the barrel base, no deck, no book, no card pile."


def load_key():
    """Reads OPENAI_API_KEY (returned) and IMAGE_MODEL (set in os.environ) from tools/patron_art/.env, like the main generator."""
    env = ROOT / "tools/patron_art/.env"
    key = None
    for line in env.read_text().splitlines():
        k, _, v = line.partition("=")
        v = v.strip().strip('"').strip("'")
        if k.strip() == "OPENAI_API_KEY":
            key = v
        elif k.strip() == "IMAGE_MODEL" and v:
            os.environ.setdefault("IMAGE_MODEL", v)
    if not key:
        sys.exit("Missing OPENAI_API_KEY in tools/patron_art/.env")
    return key


def hole_mask(holes, size):
    w, h = size
    a = np.zeros((h, w), np.uint8)  # 255 = hole
    for x0, y0, x1, y1 in holes:
        a[max(0, y0):y1, max(0, x0):x1] = 255
    return a


def call(key, img, holes, prompt, tag):
    hole = hole_mask(holes, img.size)
    rgba = img.convert("RGBA")
    rgba.putalpha(Image.fromarray(255 - hole, "L"))  # alpha 0 = edit here
    TMP.mkdir(parents=True, exist_ok=True)
    rgba.save(TMP / (tag + "_input_masked.png"))
    ibuf, mbuf = io.BytesIO(), io.BytesIO()
    img.convert("RGB").save(ibuf, "PNG")
    mask = Image.new("RGBA", img.size, (0, 0, 0, 255))
    mask.putalpha(Image.fromarray(255 - hole, "L"))
    mask.save(mbuf, "PNG")
    r = requests.post(
        "https://api.openai.com/v1/images/edits",
        headers={"Authorization": "Bearer " + key},
        data={"model": os.environ.get("IMAGE_MODEL", "gpt-image-1"), "prompt": prompt, "size": "1536x1024", "quality": "medium", "n": "1"},
        files={"image": ("room.png", ibuf.getvalue(), "image/png"), "mask": ("mask.png", mbuf.getvalue(), "image/png")},
        timeout=300,
    )
    if r.status_code != 200:
        sys.exit("STOPPED at %s: HTTP %d %s" % (tag, r.status_code, r.text[:300]))
    out = Image.open(io.BytesIO(base64.b64decode(r.json()["data"][0]["b64_json"]))).convert("RGB")
    out.save(TMP / (tag + "_raw.png"))
    return out


def composite(orig, result, holes, feather=5):
    """Original outside the holes (the feather only grows INTO the hole), the inpainted result inside."""
    if result.size != orig.size:
        result = result.resize(orig.size, Image.LANCZOS)
    hole = hole_mask(holes, orig.size)
    soft = np.asarray(Image.fromarray(hole, "L").filter(ImageFilter.MinFilter(2 * feather + 1)).filter(ImageFilter.GaussianBlur(feather)))
    soft = np.where(hole > 0, soft, 0).astype(np.uint8)  # never leaks outside the hole
    return Image.composite(result, orig, Image.fromarray(soft, "L"))


def main():
    orig = Image.open(REF).convert("RGB")
    if "--retop" in sys.argv:  # one new top call, the saved bottom result is reused
        key = load_key()
        step1 = composite(orig, call(key, orig, TOP, STYLE, "top"), TOP)
        step2 = composite(step1, Image.open(TMP / "bottom_raw.png").convert("RGB"), BOTTOM)
    elif "--recompose" in sys.argv:  # no API calls: rebuild from the saved raw results
        step1 = composite(orig, Image.open(TMP / "top_raw.png").convert("RGB"), TOP)
        step2 = composite(step1, Image.open(TMP / "bottom_raw.png").convert("RGB"), BOTTOM)
    else:
        key = load_key()
        step1 = composite(orig, call(key, orig, TOP, STYLE, "top"), TOP)
        step1.save(TMP / "after_top.png")
        step2 = composite(step1, call(key, step1, BOTTOM, STYLE + BOTTOM_NOTE, "bottom"), BOTTOM)
    OUT.mkdir(parents=True, exist_ok=True)
    step2.save(OUT / "ct_table_room_new.png")
    # proof that everything outside the holes is the reference
    holes = hole_mask(TOP + BOTTOM, orig.size) > 0
    diff = np.abs(np.asarray(step2).astype(int) - np.asarray(orig).astype(int)).max(axis=2)
    print("max difference outside holes (expect 0):", int(diff[~holes].max()))
    print("wrote", OUT / "ct_table_room_new.png")


if __name__ == "__main__":
    main()
