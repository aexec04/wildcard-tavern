import os
from PIL import Image
os.makedirs('art-wip/concept_t/tmp', exist_ok=True)
names = ['pill_green', 'pill_blue', 'pill_purple', 'pill_gold', 'label_common']
W = sum(Image.open('claude/reference/concept_t/%s.png' % n).size[0] * 3 for n in names)
c = Image.new('RGBA', (W, 160), (90, 60, 40, 255))
x = 0
for n in names:
    im = Image.open('claude/reference/concept_t/%s.png' % n)
    im = im.resize((im.size[0] * 3, im.size[1] * 3))
    c.paste(im, (x, 0), im)
    x += im.size[0]
c.save('art-wip/concept_t/tmp/pills.png')
