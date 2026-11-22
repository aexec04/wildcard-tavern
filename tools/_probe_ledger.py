from PIL import Image
import numpy as np

im = Image.open('art-wip/ledger_ui/ledger_book_open.png').convert('RGB')
print(im.size)
a = np.asarray(im).astype(float)
g = a.sum(2)
for name, x0, x1 in (('L', 240, 680), ('R', 880, 1290)):
    col = g[:, x0:x1].mean(1)
    sm = np.convolve(col, np.ones(15) / 15, 'same')
    d = sm - col
    pk = [y for y in range(150, 800) if d[y] > 12 and d[y] == d[max(0, y - 6):y + 7].max()]
    print(name, pk)
