#!/usr/bin/env python3
"""Procedural mist puff textures for the Journey map fog (category "fx").

No AI credits and no Pillow needed: writes 512x512 RGBA PNGs with the standard library.
RGB is cream (250,240,220) everywhere; alpha is a smooth radial falloff (smoothstep from 1.0
at the centre to 0 at 95% of the radius) modulated by low-frequency value noise, so it reads
as mist and has no visible rim.

  python3 tools/patron_art/make_fog_puff.py        # writes art-wip/fx/fog_puff.png and fog_puff_b.png
"""
import math, pathlib, random, struct, zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "art-wip" / "fx"
SIZE = 512
RGB = (250, 240, 220)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def make_noise(seed, cells=5):
    """Tileless value noise grid sampled with smooth bilinear interpolation, returns f(u, v) in 0..1."""
    rng = random.Random(seed)
    n = cells + 1
    grid = [[rng.random() for _ in range(n)] for _ in range(n)]

    def sample(u, v):
        x, y = u * cells, v * cells
        x0, y0 = min(int(x), cells - 1), min(int(y), cells - 1)
        fx, fy = smoothstep(0, 1, x - x0), smoothstep(0, 1, y - y0)
        a = grid[y0][x0] * (1 - fx) + grid[y0][x0 + 1] * fx
        b = grid[y0 + 1][x0] * (1 - fx) + grid[y0 + 1][x0 + 1] * fx
        return a * (1 - fy) + b * fy

    return sample


def png_bytes(width, height, rows):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def render(seed):
    big, small = make_noise(seed, 3), make_noise(seed + 101, 7)
    rows = []
    half = SIZE / 2.0
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            dx, dy = (px + 0.5 - half) / half, (py + 0.5 - half) / half
            r = math.hypot(dx, dy)
            base = 1.0 - smoothstep(0.0, 0.95, r)           # 1 at centre, 0 at 95% radius
            base = base * base * (3 - 2 * base)              # extra-soft shoulders
            n = 0.65 * big(px / SIZE, py / SIZE) + 0.35 * small(px / SIZE, py / SIZE)
            a = base * (0.55 + 0.45 * n * 1.6)               # mist-like density variation
            a = max(0.0, min(1.0, a)) * (1.0 - smoothstep(0.80, 0.95, r))  # guarantee zero at the rim
            row += bytes((RGB[0], RGB[1], RGB[2], int(a * 255 + 0.5)))
        rows.append(bytes(row))
    return png_bytes(SIZE, SIZE, rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, seed in (("fog_puff", 11), ("fog_puff_b", 73)):
        data = render(seed)
        (OUT / f"{name}.png").write_bytes(data)
        print(f"wrote {OUT / (name + '.png')} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
