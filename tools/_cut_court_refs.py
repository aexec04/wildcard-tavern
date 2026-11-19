"""One-off: cut the king and queen figures out of the Concept T reference as edit references (art-wip/concept_t_cards/)."""
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
im = Image.open(ROOT / "claude/reference/concept_t/full_reference.png").convert("RGB")
out = ROOT / "art-wip" / "concept_t_cards"
out.mkdir(parents=True, exist_ok=True)
for name, box in (("ref_king", (445, 725, 575, 900)), ("ref_queen", (580, 715, 695, 895))):
    c = im.crop(box)
    c = c.resize((c.width * 6, c.height * 6), Image.LANCZOS)
    canvas = Image.new("RGB", (1024, 1024), (250, 245, 235))
    c.thumbnail((1000, 1000))
    canvas.paste(c, ((1024 - c.width) // 2, (1024 - c.height) // 2))
    # paint out the neighbouring card's corner letter, suit and edge so the edit cannot copy stray text
    from PIL import ImageDraw
    d = ImageDraw.Draw(canvas)
    ox = (1024 - c.width) // 2
    if name == "ref_king":
        d.rectangle((0, 0, 300, 380), fill=(250, 245, 235))
        d.rectangle((795, 0, 1024, 430), fill=(250, 245, 235))
        d.rectangle((845, 0, 1024, 1024), fill=(250, 245, 235))
        d.rectangle((0, 985, 1024, 1024), fill=(250, 245, 235))
    else:
        d.rectangle((0, 0, ox + 160, 330), fill=(250, 245, 235))
        d.rectangle((0, 0, 1024, 20), fill=(250, 245, 235))
    canvas.save(out / (name + ".png"))
    print(name, c.size)
