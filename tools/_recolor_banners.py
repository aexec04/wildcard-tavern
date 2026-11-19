# Recolor the dark indigo wall banner cloth to a rich royal purple (no image spend).
# Reads the untouched originals in art-wip/painted_kit/orig_dark, writes art-wip/painted_kit/pk_banner_l.png and _r.png.
import colorsys
from PIL import Image
import numpy as np

for side in ("l", "r"):
    im = Image.open("art-wip/painted_kit/orig_dark/pk_banner_" + side + ".png").convert("RGBA")
    a = np.array(im).astype(np.float32) / 255.0
    rgb = a[..., :3]
    v = rgb.max(-1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # cloth: blue is the strongest channel and it is dark (gold and wood are red dominant)
    cloth = (b >= r) & (b > g) & (v < 0.55) & (a[..., 3] > 0.5)
    out = rgb.copy()
    for y, x in zip(*np.nonzero(cloth)):
        h, s, vv = colorsys.rgb_to_hsv(*rgb[y, x])
        s2 = min(1.0, 0.55 + s * 0.6)
        v2 = min(0.85, 0.28 + vv * 1.55)
        out[y, x] = colorsys.hsv_to_rgb(0.76, s2, v2)  # 0.76 = royal purple
    res = a.copy()
    res[..., :3] = out
    Image.fromarray((res * 255).astype(np.uint8), "RGBA").save("art-wip/painted_kit/pk_banner_" + side + ".png")
    print(side, int(cloth.sum()), "cloth pixels recolored")
