#!/usr/bin/env python3
"""One-off: frost, palace and harvest paper variants of the Stranger's offer scroll (edits of shop_offer_scroll_a, same shape). No API calls."""
import json, pathlib
H = pathlib.Path(__file__).resolve().parent
P, G = H / "prompts.json", H / "generate_patron_art.py"
d = json.loads(P.read_text(encoding="utf-8"))
KEEP = ("Keep exactly the same shape, size, rolled ends, rod thickness, wax seal position and plain central writing area as the reference scroll. "
        "Only repaint the paper and trim as ")
TAIL = (", the large middle area of the paper stays a plain even light tone with no marks so dark ink text stays readable at high contrast, "
        "no text, no letters, no numbers, no figure, no bottles, no weapons, kid-friendly, blocky painted Roblox tavern style, painted texture, matte, "
        "flat solid pure magenta #FF00FF background filling every empty pixel with no gradient and no shadow, clean sharp edges")
V = {
    "frost": "frosted paper: pale ice white with a faint blue cast, tiny frost crystals along the edges only, silver blue rods with pale caps, a soft blue wax seal",
    "gala": "palace paper: ivory white with a fine gold edge line, deep burgundy rods with gold caps, a burgundy wax seal with a small gold crown mark",
    "harvest": "harvest paper: warm wheat cream, small wheat sheaf flourishes along the edges only, rods of warm barn wood with straw coloured caps, an orange wax seal",
}
for k, v in V.items():
    d["shop_scene_subjects"]["shop_offer_scroll_" + k] = KEEP + v + TAIL
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
add = (
    "# scroll paper variants (frost, palace, harvest): edits of shop_offer_scroll_a\n"
    "for _s in (\"frost\", \"gala\", \"harvest\"):\n"
    "    CATEGORY_OPTS[\"shop_scene\"].setdefault(\"sizes\", {})[\"shop_offer_scroll_\" + _s] = \"1024x1536\"\n"
    "    CATEGORY_OPTS[\"shop_scene\"].setdefault(\"references\", {})[\"shop_offer_scroll_\" + _s] = \"art-wip/shop_scene/shop_offer_scroll_a.png\"\n"
)
s = G.read_text(encoding="utf-8")
marker = "# Frosted Garden, Mountain Festival and Closing Time identity:"
if "scroll paper variants" not in s:
    assert marker in s
    G.write_text(s.replace(marker, add + marker, 1), encoding="utf-8")
print("ok")
