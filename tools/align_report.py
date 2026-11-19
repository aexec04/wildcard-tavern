"""Usage: python3 tools/align_report.py <screenshot.png>
For each region of tools/pixel_match.py finds the shift (dx, dy in pixels on the 1536 x 1024 frame) and scale of the screenshot
that best matches the reference, so layout fixes can be exact numbers. Positive dx means our content is too far LEFT (move it
right by dx), positive dy means too high (move it down by dy). Scale above 1 means ours is too small."""
import sys, pathlib
import numpy as np
from PIL import Image, ImageFilter
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pixel_match as pm
ref = pm.load(pm.REFERENCE).filter(ImageFilter.GaussianBlur(2))
us = pm.load(sys.argv[1], bars=True).filter(ImageFilter.GaussianBlur(2))
def best(name, frac):
    x0, y0, x1, y1 = pm.box(frac)
    r = np.asarray(ref.crop((x0, y0, x1, y1)), dtype=np.float32)
    res = (1e9, 0, 0, 1.0)
    for s in (0.90, 0.95, 1.0, 1.05, 1.10):
        w, h = us.size
        big = us.resize((int(w * s), int(h * s)), Image.BILINEAR)
        cx, cy = w / 2, h / 2
        for dy in range(-30, 31, 3):
            for dx in range(-30, 31, 3):
                # sample region from the scaled image around the same centre, shifted by (dx, dy)
                sx0 = int(x0 * s + (cx * s - cx) + dx) ; sy0 = int(y0 * s + (cy * s - cy) + dy)
                c = np.asarray(big.crop((sx0, sy0, sx0 + (x1 - x0), sy0 + (y1 - y0))), dtype=np.float32)
                if c.shape != r.shape: continue
                d = float(np.abs(c - r).mean())
                if d < res[0]: res = (d, dx, dy, s)
    return res
for name, (frac, target) in pm.REGIONS.items():
    d, dx, dy, s = best(name, frac)
    print("%-11s best diff %5.1f at shift (%+d, %+d) px, our scale %.2f (move ours by %+d, %+d)" % (name, d, dx, dy, s, -dx, -dy))
