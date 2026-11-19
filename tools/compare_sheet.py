#!/usr/bin/env python3
"""Usage: python3 tools/compare_sheet.py <screenshot.png> [out.png]
Makes a 2x2 sheet: reference, screenshot, abs difference, 50% blend (bars cropped, both 1536x1024)."""
import sys
from PIL import Image, ImageChops
sys.path.insert(0, __file__.rsplit('/', 1)[0])
import pixel_match
ref = Image.open('claude/reference/concept_t/full_reference.png').convert('RGB').resize((1536, 1024))
us = pixel_match.crop_bars(Image.open(sys.argv[1]).convert('RGB')).resize((1536, 1024))
w, h = 768, 512
s = Image.new('RGB', (w * 2, h * 2))
s.paste(ref.resize((w, h)), (0, 0)); s.paste(us.resize((w, h)), (w, 0))
s.paste(ImageChops.difference(ref, us).resize((w, h)), (0, h))
s.paste(Image.blend(ref, us, 0.5).resize((w, h)), (w, h))
s.save(sys.argv[2] if len(sys.argv) > 2 else 'art-wip/concept_t/shots/compare.png')
