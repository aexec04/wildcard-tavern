from PIL import Image
d = 'art-wip/concept_t/'
names = ['ct_btn_play_a', 'ct_btn_discard_a', 'ct_deck_a', 'ct_pill_green_blank', 'ct_pill_blue_blank', 'ct_pill_purple_blank', 'ct_pill_gold_blank']
c = Image.new('RGBA', (1500, 700), (255, 0, 255, 255))
x, y = 0, 0
for n in names:
    im = Image.open(d + n + '.png')
    if n.startswith('ct_pill'):
        im = im.resize((im.size[0] * 2, im.size[1] * 2))
    if x + im.size[0] > 1500:
        x, y = 0, y + 330
    c.paste(im, (x, y), im)
    x += im.size[0] + 10
c.save(d + 'tmp/recut_preview.png')
