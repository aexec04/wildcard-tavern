"""Mock of the Ledger v5 look: desk art, the book at about 62 percent of the panel width resting on the table, the contact
shadow, and Story page text placed with the same maths as Engine/LedgerLayout.lua. Saves art-wip/_checks/ledger_mock.png.
Run: python3 tools/mock_ledger_composite.py"""
import math
import re
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

GEO = open("src/Shared/Engine/LedgerBookGeometry.lua").read()
ASPECT = float(re.search(r"aspect = ([0-9.]+)", GEO).group(1))


def parse(side):
    blk = GEO[GEO.index(side + " = {"):]
    quad = [(float(a), float(b)) for a, b in re.findall(r"\{ ([0-9.]+), ([0-9.]+) \}", blk.split("lines")[0])]
    lines = []
    for m in re.finditer(r"x0 = ([0-9.]+), y0 = ([0-9.]+), x1 = ([0-9.]+), y1 = ([0-9.]+), angle = (-?[0-9.]+)", blk):
        lines.append(tuple(float(v) for v in m.groups()))
        if len(lines) == 9:
            break
    return quad, lines


def span(quad, ln):
    x0, y0, x1, y1, ang = ln
    slope = (y1 - y0) / (x1 - x0)

    def edge(y, left):
        a, b = (quad[0], quad[3]) if left else (quad[1], quad[2])
        t = max(0, min(1, (y - a[1]) / (b[1] - a[1])))
        return a[0] + (b[0] - a[0]) * t
    xa, xb = max(x0, edge(y0, True)), min(x1, edge(y1, False))
    ins = 0.08 * (xb - xa)
    xa, xb = xa + ins, xb - ins
    return xa, y0 + slope * (xa - x0), xb, y0 + slope * (xb - x0), ang


PW, PH = 1640, 972
desk = Image.open("art-wip/ledger_ui/ledger_desk.png").convert("RGBA").resize((PW, PH))
book = Image.open("art-wip/ledger_ui/ledger_book_open.png").convert("RGBA")
bw = min(PW * 0.62, PH * 0.76 * ASPECT)
bh = bw / ASPECT
book = book.resize((int(bw), int(bh)))
bx = int((PW - bw) / 2 + 0)
by = int(PH * 0.86 - bh)
shadow = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([bx - bw * 0.03, PH * 0.86 - bh * 0.03, bx + bw * 1.03, PH * 0.86 + bh * 0.03], fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(8))
comp = Image.alpha_composite(desk, shadow)
comp.alpha_composite(book, (bx, by))

FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
if not os.path.exists(FONT):
    FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
sp = (parse("left")[1][8][1] - parse("left")[1][0][1]) / 8 * bh
body = max(14, min(22, round(sp * 0.58)))
head = max(18, min(26, round(sp * 0.74)))
big = max(24, min(40, round(sp * 1.0)))
INK = (40, 26, 14, 255)
DIM = (70, 48, 28, 255)


def put(side, i, t0, t1, s, size, col=INK, right=False):
    quad, lines = parse(side)
    xa, ya, xb, yb, ang = span(quad, lines[i - 1])
    x = xa + (xb - xa) * t0
    y = ya + (yb - ya) * t0
    w = (xb - xa) * (t1 - t0) * bw
    f = ImageFont.truetype(FONT, size)
    tw = int(f.getlength(s))
    layer = Image.new("RGBA", (int(max(w, tw)) + 4, size * 2), (0, 0, 0, 0))
    ox = int(w - tw) if right else 0
    ImageDraw.Draw(layer).text((ox, size * 2 - 6), s, font=f, fill=col, anchor="ls")
    a = math.radians(ang)
    rot = layer.rotate(-ang, resample=Image.BICUBIC, expand=True)  # PIL rotates counter-clockwise
    # anchor = bottom-left of the layer, lifted 3 px perpendicular to the line
    px = bx + x * bw + math.sin(a) * 3
    py = by + y * bh - math.cos(a) * 3
    # bottom-left of the layer after rotation about its bottom-left corner: place the rotated image so that point lands at px,py
    cx, cy = rot.size[0] / 2, rot.size[1] / 2
    lw, lh = layer.size
    # vector from layer centre to its bottom-left corner, rotated clockwise by ang on screen
    vx, vy = -lw / 2, lh / 2
    rx = vx * math.cos(a) - vy * math.sin(a)
    ry = vx * math.sin(a) + vy * math.cos(a)
    comp.alpha_composite(rot, (int(px - (cx + rx)), int(py - (cy + ry))))


put("left", 1, 0, 1, "My Story", head)
for k, (lab, num) in enumerate((("Runs won", "12"), ("Runs started", "47"), ("Best Night", "9"))):
    put("left", 2 + k * 2, 0, 1, lab, body, DIM)
    put("left", 3 + k * 2, 0, 1, num, big)
put("left", 8, 0, 1, "Win rate", body)
put("left", 8, 0, 1, "26%", body, right=True)
put("right", 1, 0, 1, "Regulars' Corner", head)
put("right", 2, 0.36, 1, "Favorite Patron", body, DIM)
put("right", 3, 0.36, 1, "The Dealer", head)
put("right", 4, 0.36, 1, "Won 5 runs with it", max(14, body - 2), DIM)
put("right", 5, 0, 1, "Lifetime", head)
for k, (a, b) in enumerate((("Title", "None"), ("Hands played", "1,204"), ("Best hand score", "88,420"), ("Tips earned", "3,310"))):
    put("right", 6 + k, 0, 1, a, body)
    put("right", 6 + k, 0, 1, b, body, right=True)
os.makedirs("art-wip/_checks", exist_ok=True)
comp.convert("RGB").save("art-wip/_checks/ledger_mock.png")
print("book px", int(bw), int(bh), "sizes", body, head, big)
