"""Cleaned slice copy of classic_tavern_button_plate: left cap + one plain rail span + right cap, no stud block in the stretch."""
from PIL import Image
src = Image.open("art-wip/set_skins/classic_tavern_button_plate.png").convert("RGBA")
L, R, S0, S1 = 330, 1285, 335, 725  # left cap end, right cap start, plain rail span
top, bot = 292, 720
def crop(a, b): return src.crop((a, top, b, bot))
left, mid, right = crop(11, L), crop(S0, S1), crop(R, 1524)
out = Image.new("RGBA", (left.width + mid.width + right.width, bot - top), (0, 0, 0, 0))
x = 0
for part in (left, mid, right):
    out.paste(part, (x, 0)); x += part.width
out.save("art-wip/set_skins/classic_tavern_button_plate_slice.png")
for name, col in (("magenta", (255, 0, 255, 255)), ("green", (0, 200, 0, 255))):
    bg = Image.new("RGBA", out.size, col); bg.alpha_composite(out)
    bg.save(f"art-wip/set_skins/debug_button_plate_slice_{name}.png")
print(out.size, "mid starts at", left.width, "mid ends at", left.width + mid.width)
