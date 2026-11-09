"""Pure Python magenta cutout for generated PNGs (no Pillow needed).

The image model cannot output real alpha, so cutout props and layers are generated on a flat pure magenta (#FF00FF)
background and this step turns the magenta into transparency:
  * magentaness m = min(r, b) - g (about 255 on the background, negative on warm browns, golds and reds);
  * alpha ramps from opaque (m <= LOW) to clear (m >= HIGH), so edges stay soft;
  * magenta spill is removed from the kept pixels' red and blue.
Run directly to cut one file in place:  python3 tools/patron_art/cutout.py path/to/image.png
"""
import struct, sys, zlib

LOW, HIGH = 50, 150


def _read(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, ihdr = 8, [], None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = ihdr
    if depth != 8 or ctype not in (2, 6) or interlace:
        raise ValueError(f"unsupported PNG (depth {depth}, type {ctype}, interlace {interlace})")
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def _write(path, w, h, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(out)


def cutout(path):
    """Turns the magenta background of the PNG at `path` into transparency (in place). Returns the opaque pixel fraction."""
    w, h, bpp, rows = _read(path)
    out, opaque = [], 0
    span = float(HIGH - LOW)
    for line in rows:
        o = bytearray(w * 4)
        for x in range(w):
            r, g, b = line[x * bpp], line[x * bpp + 1], line[x * bpp + 2]
            m = (r if r < b else b) - g
            if m <= LOW:
                a = 255
            elif m >= HIGH:
                a = 0
            else:
                a = int(255 * (HIGH - m) / span)
            if a == 0:  # clear pixels carry a dark wood colour, never magenta, so filtering at the edges cannot bleed pink
                r, g, b = 60, 40, 26
            elif m > 0:  # remove magenta spill from the kept edge pixels
                r = max(g, r - int(m * 0.8))
                b = max(g, b - int(m * 0.8))
            j = x * 4
            o[j], o[j + 1], o[j + 2], o[j + 3] = r, g, b, a
            if a > 128:
                opaque += 1
        out.append(o)
    _write(path, w, h, out)
    return opaque / float(w * h)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(p, "opaque fraction %.2f" % cutout(p))
