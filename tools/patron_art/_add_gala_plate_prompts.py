#!/usr/bin/env python3
"""One-off: Golden Gala palace button plates (3 painted_kit pieces), edits of the classic plates. No API calls."""
import json, pathlib
HERE = pathlib.Path(__file__).resolve().parent
P = HERE / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
MAG = ", on a flat solid pure magenta #FF00FF background with no gradient, clean sharp edges, the single piece centred with generous margin all round"
KEEP = "Keep exactly the same shape, proportions, border thickness and corner layout as the reference plate. "
GOLD = "a thin polished gold border with small gold corner flourishes and a few tiny gold studs, "
NO = ", completely blank centre, no letters, no numbers, no people, no bottles, no weapons"
subs = d["pk_subjects"]
subs["pk_gala_btn_dark"] = (KEEP + "Redraw it as a palace button plate: deep burgundy velvet face with soft fabric sheen, " + GOLD
                            + "darker and calmer than the primary plate so ivory text reads on it" + NO + MAG)
subs["pk_gala_btn_green"] = (KEEP + "Redraw it as a palace primary button plate: deep emerald green enamel face, " + GOLD
                             + "a slightly thicker bright gold border, ivory text must read on the green" + NO + MAG)
subs["pk_gala_orn_btn_green"] = (KEEP + "Redraw it as a palace wide primary bar plate: deep emerald green enamel face, " + GOLD
                                 + "the same flourishes in all four corners, border width equal on all four sides so it can be stretched" + NO + MAG)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
G = HERE / "generate_patron_art.py"
s = G.read_text(encoding="utf-8")
add = '''# Golden Gala palace button plates: edits of the classic plates, same aspect
for _k, _ref in (("pk_gala_btn_dark", "pk_w_btn_dark"), ("pk_gala_btn_green", "pk_w_btn_green"), ("pk_gala_orn_btn_green", "pk_orn_btn_green")):
    CATEGORY_OPTS["painted_kit"]["references"][_k] = "art-wip/painted_kit/%s.png" % _ref
'''
if "pk_gala_btn_dark" not in s:
    s = s.replace("# Golden Gala palace keeper:", add + "# Golden Gala palace keeper:", 1)
    G.write_text(s, encoding="utf-8")
print("ok")
