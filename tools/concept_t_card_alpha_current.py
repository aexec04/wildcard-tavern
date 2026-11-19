"""Alpha corners for the CURRENT Concept T Patron cards (the variety pass regenerated them as RGB on a gray backdrop).
Backs the current files up once into art-wip/concept_t_patrons/orig_v2/ and rewrites each as RGBA using the same cut as
tools/concept_t_card_alpha.py (which reads the older orig/ files and must not be rerun over the regenerated cards).
Then: python3 tools/patron_art/generate_patron_art.py -c concept_t_patrons upload
Usage: python3 tools/concept_t_card_alpha_current.py
"""
import importlib.util
import pathlib
import shutil

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("cta", HERE / "concept_t_card_alpha.py")
cta = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cta)

D = cta.DIR
bk = D / "orig_v2"
bk.mkdir(exist_ok=True)
for p in sorted(D.glob("ctp_*.png")):
    if Image.open(p).mode == "RGBA":
        continue
    if not (bk / p.name).exists():
        shutil.copy2(p, bk / p.name)
    out, frac = cta.cut(bk / p.name)
    out.save(p)
    print(p.name, round(frac, 3))
