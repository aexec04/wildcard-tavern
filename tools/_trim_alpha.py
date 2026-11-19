import sys
from PIL import Image
p = sys.argv[1]
im = Image.open(p)
b = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
print(b)
im.crop(b).save(p)
print(Image.open(p).size)
