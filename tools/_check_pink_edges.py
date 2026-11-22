import glob
import sys

import numpy as np
from PIL import Image

folder = sys.argv[1] if len(sys.argv) > 1 else "art-wip/menu_world"
for f in sorted(glob.glob(folder + "/*.png")):
    im = Image.open(f).convert("RGBA")
    a = np.asarray(im).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    vis = al > 8
    pink = vis & (r - g > 40) & (b - g > 25)  # magenta-tinted: R and B both above G
    edge = vis & (al < 250)
    print(f.split("/")[-1], im.size, "visible", int(vis.sum()), "pink", int(pink.sum()), "pink share %.4f" % (pink.sum() / max(1, vis.sum())),
          "semi-alpha", int(edge.sum()), "pink&semi", int((pink & edge).sum()))
