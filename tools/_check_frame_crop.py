from PIL import Image

for n in ("collection_frame_owned", "collection_frame_empty"):
    im = Image.open("art-wip/collection_scene/%s.png" % n).convert("RGBA")
    c = im.crop((88, 350, 88 + 849, 350 + 986)).resize((92 * 3, 108 * 3))
    bg = Image.new("RGBA", c.size, (40, 28, 20, 255))
    bg.alpha_composite(c)
    bg.convert("RGB").save("art-wip/_checks/frame_crop_%s.png" % n)
print("ok")
