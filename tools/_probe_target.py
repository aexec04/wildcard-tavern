import sys
from PIL import Image
import numpy as np
im = Image.open(sys.argv[1]).convert('RGBA')
print(im.size)
a = np.array(im)[:, :, 3]
cols = np.where(a.max(axis=0) > 20)[0]
rows = np.where(a.max(axis=1) > 20)[0]
print(cols.min(), cols.max(), rows.min(), rows.max())
w = im.size[0]
for x in [0, 5, 20, 50, 100, 150, 200, w - 200, w - 150, w - 100, w - 50, w - 20, w - 5, w - 1]:
    print(x, int((a[:, x] > 20).sum()))
