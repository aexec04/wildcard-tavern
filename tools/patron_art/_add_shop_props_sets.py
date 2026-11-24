#!/usr/bin/env python3
"""One-off: per-Card-Set counter props sheets (edits of shop_counter_props so the crops stay valid). No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", keep exactly the same four props in exactly the same positions and sizes as the reference picture (brass service bell, closed ledger book, wooden mug, lit candle in a brass holder), "
         "blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, original art, no text, no letters, no numbers, no logos, kid-friendly, "
         "flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges")
LOOK = {
    "frost": "repaint the props as frosted winter versions: the book has an icy pale blue cover with silver corners and a dusting of snow on top, the bell is silvery brass with frost and a tiny icicle, the mug is pale blue ceramic with a snowy rim, the candle has frost on its brass holder",
}
subj = d["shop_scene_subjects"]
for k, v in LOOK.items():
    subj["shop_counter_props_" + k] = v + STYLE
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", list(LOOK))
