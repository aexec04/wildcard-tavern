#!/usr/bin/env python3
"""Contact sheet of the Concept T Patron cards for one rarity: python3 tools/patron_art/contact_sheet.py <rarity> [cols]
Writes art-wip/patron_contact_<rarity>.png (cards at 256 px wide, id and expression under each)."""
import json, pathlib, sys
from PIL import Image, ImageDraw
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    rarity = sys.argv[1]
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    variety = json.loads((HERE / "patron_variety.json").read_text(encoding="utf-8"))
    ids = [p for p, v in variety.items() if v["rarity"] == rarity]
    W, H, LAB = 256, 384, 34
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * W, rows * (H + LAB)), (40, 40, 40))
    dr = ImageDraw.Draw(sheet)
    for i, pid in enumerate(ids):
        x, y = (i % cols) * W, (i // cols) * (H + LAB)
        f = ROOT / "art-wip" / "concept_t_patrons" / ("ctp_%s.png" % pid)
        if f.exists():
            sheet.paste(Image.open(f).convert("RGB").resize((W, H)), (x, y))
        dr.text((x + 4, y + H + 4), "%s" % pid, fill=(255, 255, 255))
        dr.text((x + 4, y + H + 18), "plan: %s" % variety[pid]["expression"], fill=(255, 220, 120))
    out = ROOT / "art-wip" / ("patron_contact_%s.png" % rarity)
    sheet.save(out)
    print(out, len(ids))


main()
