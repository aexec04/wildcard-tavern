#!/usr/bin/env python3
"""Measure set skin art and write src/Shared/Engine/SetSkinMetrics.lua (generated, do not hand-edit).

Pure standard library (zlib), no Pillow needed. For every art-wip/set_skins/<set>_<slot>.png it records:
  w, h        full canvas size
  x, y, cw, ch  bounding box of visible art (alpha > ALPHA_MIN), the crop used for ImageRectOffset/Size
  For face_frame also: ix, iy, iw, ih = inner window (largest centred transparent rectangle, in canvas px)
  For button/tab/panel: l, r, t, b = border thickness inside the crop (cap sizes for 9-slice)

Usage: python3 tools/patron_art/measure_skin_art.py
"""
import os, re, struct, sys, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art-wip", "set_skins")
OUT = os.path.join(ROOT, "src", "Shared", "Engine", "SetSkinMetrics.lua")
ALPHA_MIN = 24
ALPHA_EDGE = 200  # the art bounding box ignores halos and shadows below this alpha
EDGE_ROW_FRACTION = 0.02  # a row or column needs this share of solid pixels, else it is a halo line and is trimmed
SLOTS = ["button_plate", "tab_plate", "panel_frame", "face_frame"]


def read_alpha(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat, plte = 8, b"", None
    w = h = depth = ctype = 0
    while pos < len(data):
        ln, = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
        elif kind == b"IDAT":
            idat += body
        pos += 12 + ln
    if ctype not in (6, 4):
        return w, h, None  # no alpha channel: treat as fully opaque
    bpp = (4 if ctype == 6 else 2) * (depth // 8)
    step = bpp
    stride = w * bpp
    raw = zlib.decompress(idat)
    prev = bytearray(stride)
    alpha = []
    off = 0
    for _ in range(h):
        ft = raw[off]
        line = bytearray(raw[off + 1:off + 1 + stride])
        off += 1 + stride
        if ft == 1:
            for i in range(step, stride):
                line[i] = (line[i] + line[i - step]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - step] if i >= step else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - step] if i >= step else 0
                b = prev[i]
                c = prev[i - step] if i >= step else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        a_off = (bpp - (depth // 8))
        alpha.append(bytes(line[a_off::bpp]) if depth == 8 else bytes(line[a_off::bpp]))
    return w, h, alpha


def bbox(w, h, alpha, threshold=ALPHA_MIN):
    """Bounding box of pixels with alpha > threshold. Rows and columns holding fewer than EDGE_ROW_FRACTION of solid
    pixels (stray halo, shadow or noise lines) are trimmed."""
    if alpha is None:
        return 0, 0, w, h
    rows = [sum(1 for a in row if a > threshold) for row in alpha]
    cols = [0] * w
    for row in alpha:
        for x, a in enumerate(row):
            if a > threshold:
                cols[x] += 1
    ys = [y for y, n in enumerate(rows) if n >= max(1, w * EDGE_ROW_FRACTION)]
    xs = [x for x, n in enumerate(cols) if n >= max(1, h * EDGE_ROW_FRACTION)]
    if not ys or not xs:
        return 0, 0, w, h
    return xs[0], ys[0], xs[-1] - xs[0] + 1, ys[-1] - ys[0] + 1


def edge_thickness(alpha, box):
    """Border thickness: how many px from each cropped edge until the centre row/column becomes mostly clear."""
    x, y, cw, ch = box
    midy, midx = y + ch // 2, x + cw // 2
    row = alpha[midy][x:x + cw]
    col = [alpha[yy][midx] for yy in range(y, y + ch)]

    def run(seq):
        n = 0
        for a in seq:
            if a > ALPHA_MIN:
                n += 1
            else:
                break
        return n
    # the centre line may be opaque everywhere (paper): then fall back to 12 percent of the side
    l, r = run(row), run(row[::-1])
    t, b = run(col), run(col[::-1])
    if l > cw * 0.4: l = r = int(cw * 0.12)
    if t > ch * 0.4: t = b = int(ch * 0.12)
    return l, r, t, b


def inner_window(alpha, box):
    """Largest rectangle grown from the centre while it stays clear (alpha <= ALPHA_MIN) of frame ink."""
    x, y, cw, ch = box
    cx, cy = x + cw // 2, y + ch // 2
    l, r, t, b = cx, cx, cy, cy

    def clear_col(xx, y0, y1):
        return all(alpha[yy][xx] <= ALPHA_MIN for yy in range(y0, y1 + 1))

    def clear_row(yy, x0, x1):
        row = alpha[yy]
        return all(row[xx] <= ALPHA_MIN for xx in range(x0, x1 + 1))
    if alpha[cy][cx] > ALPHA_MIN:
        return None
    grew = True
    while grew:
        grew = False
        if l > x and clear_col(l - 1, t, b): l -= 1; grew = True
        if r < x + cw - 1 and clear_col(r + 1, t, b): r += 1; grew = True
        if t > y and clear_row(t - 1, l, r): t -= 1; grew = True
        if b < y + ch - 1 and clear_row(b + 1, l, r): b += 1; grew = True
    return l, t, r - l + 1, b - t + 1


# Cleaned button plates (tools/make_button_plate_slice.py): <set>_button_plate_slice.png replaces <set>_button_plate and
# carries px0..px1, the plain rail span in crop px (left cap 0..px0, right cap px1..cw), so no stud lands in the stretch.
PLAIN_SPAN = {"classic_tavern": (319, 709)}


def main():
    out = {}
    pat = re.compile(r"^(.+)_(button_plate|tab_plate|panel_frame|face_frame)(_slice)?\.png$")
    names = sorted(os.listdir(SRC))
    for name in names:
        m = pat.match(name)
        if not m:
            continue
        sid, slot = m.group(1), m.group(2)
        if m.group(3) is None and (sid + "_" + slot + "_slice.png") in names:
            continue  # the cleaned slice copy is measured instead
        w, h, alpha = read_alpha(os.path.join(SRC, name))
        box = bbox(w, h, alpha, ALPHA_EDGE)
        print("CROP %s %s %.1f%% x %.1f%%" % (sid, slot, 100.0 * box[2] / w, 100.0 * box[3] / h), file=sys.stderr)
        entry = {"w": w, "h": h, "x": box[0], "y": box[1], "cw": box[2], "ch": box[3]}
        if alpha is not None:
            if slot == "face_frame":
                win = inner_window(alpha, box)
                if win:
                    entry.update({"ix": win[0], "iy": win[1], "iw": win[2], "ih": win[3]})
            l, r, t, b = edge_thickness(alpha, box)
            entry.update({"l": l, "r": r, "t": t, "b": b})
            if m.group(3) and sid in PLAIN_SPAN:
                entry.update({"px0": PLAIN_SPAN[sid][0] - box[0], "px1": PLAIN_SPAN[sid][1] - box[0]})
        out.setdefault(sid, {})[slot] = entry
        print(sid, slot, entry, file=sys.stderr)
    lines = ["--[[", "\tShared/Engine/SetSkinMetrics.lua",
             "\tGENERATED by tools/patron_art/measure_skin_art.py -- do not hand-edit.",
             "\tPer set and slot: canvas w,h; art bounding box x,y,cw,ch; frame inner window ix,iy,iw,ih;",
             "\tborder thickness l,r,t,b inside the crop. Pixels of the source PNG.", "]]", "", "return {"]
    for sid in sorted(out):
        lines.append('\t["%s"] = {' % sid)
        for slot in SLOTS:
            e = out[sid].get(slot)
            if not e:
                continue
            body = ", ".join("%s = %d" % (k, v) for k, v in e.items())
            lines.append("\t\t%s = { %s }," % (slot, body))
        lines.append("\t},")
    lines.append("}")
    open(OUT, "w").write("\n".join(lines) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
