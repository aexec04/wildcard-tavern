# Draws the candidate arched opening of flair_room_a.png over the door. Run: python3 -I tools/_measure_flair_door.py x y w h
import sys
from PIL import Image, ImageDraw

x, y, w, h = [int(v) for v in sys.argv[1:5]]
im = Image.open("art-wip/panel_scene/flair_room_a.png").convert("RGB")
d = ImageDraw.Draw(im)
r = w // 2
d.arc([x, y, x + w, y + w], 180, 360, fill=(0, 255, 0), width=1)
d.line([x, y + r, x, y + h], fill=(0, 255, 0))
d.line([x + w, y + r, x + w, y + h], fill=(0, 255, 0))
d.line([x, y + h, x + w, y + h], fill=(0, 255, 0))
im.crop((1100, 150, 1480, 800)).save("/tmp/door_check.png")
