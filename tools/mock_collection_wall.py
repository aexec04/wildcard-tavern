"""Mock of the Patrons wall (frames hung with chains, shadows, brass plates, tilt) using the same numbers as
Engine/CollectionSceneLayout.lua. Saves art-wip/_checks/collection_wall_mock.png. Run: python3 tools/mock_collection_wall.py"""
import math
import re

from PIL import Image, ImageDraw, ImageFont

SRC = open("src/Shared/Engine/CollectionSceneLayout.lua").read()


def crop_of(kind):
    m = re.search(kind + r" = \{ imgW = 1024, imgH = 1536, x = (\d+), y = (\d+), w = (\d+), h = (\d+)", SRC)
    return tuple(int(v) for v in m.groups())


W, H = 900, 520
wall = Image.open("art-wip/collection_scene/collection_wall.png").convert("RGBA")
sc = max(W / wall.width, H / wall.height)
wall = wall.resize((int(wall.width * sc), int(wall.height * sc)))
img = wall.crop(((wall.width - W) // 2, (wall.height - H) // 2, (wall.width - W) // 2 + W, (wall.height - H) // 2 + H))
scrim = Image.new("RGBA", img.size, (14, 8, 4, int(255 * 0.15)))
img = Image.alpha_composite(img, scrim)

CW, CH, FH, PH, OV = 92, 136, 108, 22, 6
GX, GY, CHAIN = 16, 28, 22
frames = {k: Image.open("art-wip/collection_scene/collection_frame_%s.png" % k).convert("RGBA") for k in ("owned", "empty")}
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 12)
x0, y0 = 60, 70
names = ["The Dealer", "Lucky Pete", "Sly Fox", "Old Marlo", "???", "???", "???", "???"]
for i, name in enumerate(names):
    kind = "empty" if name == "???" else "owned"
    col, row = i % 4, i // 4
    cx = x0 + col * (CW + GX) + 40
    cy = y0 + row * (CH + GY)
    cell = Image.new("RGBA", (CW + 20, CH + CHAIN + 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(cell)
    ox, oy = 10, CHAIN + 6
    # shadow
    d.rounded_rectangle([ox + 3, oy + 5, ox + 3 + CW, oy + 5 + FH], 8, fill=(0, 0, 0, 90))
    # chains and nail
    nx, ny = ox + CW / 2, oy - CHAIN
    for fx in (0.24, 0.76):
        d.line([(nx, ny), (ox + CW * fx, oy + 3)], fill=(122, 98, 62, 255), width=2)
    d.ellipse([nx - 4, ny - 4, nx + 4, ny + 4], fill=(190, 146, 64, 255))
    x, y, w, h = crop_of(kind)
    fr = frames[kind].crop((x, y, x + w, y + h)).resize((CW, FH))
    cell.alpha_composite(fr, (ox, oy))
    d = ImageDraw.Draw(cell)
    px, py = ox + 6, oy + FH - OV
    d.rounded_rectangle([px, py, px + CW - 12, py + PH], 4, fill=(190, 146, 64, 255), outline=(112, 80, 30, 255), width=2)
    d.text((px + 8, py + 4), name[:11], fill=(52, 32, 10, 255), font=font)
    tilt = ((i * 37) % 31) / 10 - 1.5
    cell = cell.rotate(-tilt, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(cell, (int(cx - cell.width / 2) - 10, int(cy - 10)))
img.convert("RGB").save("art-wip/_checks/collection_wall_mock.png")
print("saved")
