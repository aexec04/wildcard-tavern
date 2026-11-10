"""Despill the pink halo of a cut-out PNG without generating anything.
Usage: python3 tools/despill_menu_world.py <in.png> <out.png>
1. erode the alpha edge by 3 px (the halo lives in the soft band at the edge)
2. every pixel that is not solid any more, or is still magenta tinted, takes the colour of its nearest solid neighbours
   (colour bleed, 24 passes), so no pink is left in the fringe
3. feather the alpha by 1 px
Also writes <out>_check.png (the result over a green field) so it can be looked at."""
import sys

import numpy as np
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
eroded = im.getchannel("A").filter(ImageFilter.MinFilter(7))
a = np.asarray(im).astype(np.float32)
al = np.asarray(eroded).astype(np.float32)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
# Pink, rose and salmon fringe: a red or magenta hue (under 18 or over 325 degrees) with real saturation. Warm paint (wood, skin,
# flame) sits at 25 to 60 degrees. Only within 24 px of the transparent area, so red fruit and hair deeper in the art are never touched.
mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
delta = np.maximum(mx - mn, 1e-3)
hue = np.where(mx == r, ((g - b) / delta) % 6, np.where(mx == g, (b - r) / delta + 2, (r - g) / delta + 4)) * 60
sat = delta / np.maximum(mx, 1e-3)
trans = Image.fromarray(((al < 128) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(49))
near = np.asarray(trans) > 0
tint = near  # the whole 24 px edge band is repainted from the clean fog inside it (the band is soft fog, so nothing is lost)
solid = (al >= 250) & ~tint
rgb = a[..., :3].copy()
valid = solid.copy()
need = ~solid
for _ in range(50):
    if not need.any():
        break
    acc = np.zeros_like(rgb)
    cnt = np.zeros(valid.shape, np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            v = np.roll(valid, (dy, dx), axis=(0, 1))
            c = np.roll(rgb, (dy, dx), axis=(0, 1))
            acc += c * v[..., None]
            cnt += v
    fill = need & (cnt > 0)
    rgb[fill] = acc[fill] / cnt[fill][:, None]
    valid = valid | fill
    need = need & ~fill
# smooth the repainted band so the bleed leaves no blocks, then keep the solid colours outside it untouched
blur = np.asarray(Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(5))).astype(np.float32)
rgb[near] = blur[near]
out = np.dstack([np.clip(rgb, 0, 255), al]).astype(np.uint8)
out_img = Image.fromarray(out, "RGBA")
out_img.putalpha(out_img.getchannel("A").filter(ImageFilter.GaussianBlur(1)))
out_img.save(dst)

chk = Image.new("RGBA", out_img.size, (86, 120, 64, 255))
chk.alpha_composite(out_img)
chk.convert("RGB").save(dst.replace(".png", "_check.png"))

arr = np.asarray(out_img).astype(int)
vis = arr[..., 3] > 8
pink = vis & near & (((arr[..., 0] >= arr[..., 1]) & (arr[..., 0] - arr[..., 2] < 0)) | ((arr[..., 0] - arr[..., 1] > 40) & (arr[..., 2] - arr[..., 1] > -12)))
print("visible", int(vis.sum()), "pink left", int(pink.sum()))
