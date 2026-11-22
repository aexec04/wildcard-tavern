def L(c):
    f = lambda v: (v / 255 / 12.92) if v / 255 <= 0.03928 else ((v / 255 + 0.055) / 1.055) ** 2.4
    return .2126 * f(c[0]) + .7152 * f(c[1]) + .0722 * f(c[2])


def C(a, b):
    x, y = sorted([L(a), L(b)], reverse=True)
    return (x + .05) / (y + .05)


ink = (40, 26, 14)
cr = (250, 235, 200)
cs = dict(tome=(112, 72, 40), tomeglow=(150, 104, 60), tomeglow2=(205, 160, 100), green=(40, 92, 60),
          greenglow=(70, 138, 92), greenglow2=(120, 185, 140), gold=(176, 132, 48), goldglow=(222, 182, 104),
          back=(92, 62, 36), backact=(150, 104, 52), backact2=(205, 160, 100))
for n, c in cs.items():
    print(n, round(C(ink, c), 2), round(C(cr, c), 2))
