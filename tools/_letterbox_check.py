import sys
sys.path.insert(0, 'tools')
from PIL import Image
import pixel_match as pm

ref = Image.open(pm.REFERENCE).convert('RGB')
shot = ref.resize((1435, 957), Image.LANCZOS)
canvas = Image.new('RGB', (1920, 957), (0, 0, 0))
canvas.paste(shot, (242, 0))
canvas.save('art-wip/concept_t/tmp/letterboxed.png')
a = pm.load('art-wip/concept_t/tmp/letterboxed.png', bars=True)
b = pm.load(pm.REFERENCE)
scores, _ = pm.compare(b, a)
print({k: round(v, 2) for k, v in scores.items()})
