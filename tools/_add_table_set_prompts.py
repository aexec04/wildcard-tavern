"""Adds per-set painted table front prompts (Mountain Festival, Frosted Garden; pairs _a/_b) to play_scene_subjects
and registers the keys in generate_patron_art.py (PLAY_KEYS and sizes)."""
import json
import pathlib

ROOT = pathlib.Path(__file__).parent
P = ROOT / "patron_art" / "prompts.json"
G = ROOT / "patron_art" / "generate_patron_art.py"
d = json.loads(P.read_text(encoding="utf-8"))
base = d["play_scene_subjects"]["play_table_front_a"]
OLD = "A dark green felt surface with a gold stitched border, a thick carved wooden rim in front, soft lantern glow,"
assert OLD in base
sets = {
    "festival": ("A deep midnight pine-green felt surface leaning blue with an amber-orange stitched border, a thick carved warm "
                 "honey-coloured wooden rim in front with tiny painted ribbon trim in red and gold along the rim edge, soft glow of paper lanterns,"),
    "frosted": ("A cool icy blue felt surface with a silver-white stitched border, a thick carved pale frosted wooden rim in front "
                "with tiny painted snowflake and frost leaf trim, soft cold moonlit glow,"),
}
keys = []
for name, desc in sets.items():
    for v in ("a", "b"):
        k = "play_table_front_%s_%s" % (name, v)
        s = base.replace(OLD, desc)
        if v == "b":
            s = s.replace("The felt ends in a clean flat edge at the top, no fade.",
                          "The felt ends in a clean flat edge at the top, no fade. A different look of the same piece.")
        d["play_scene_subjects"][k] = s
        keys.append(k)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

g = G.read_text(encoding="utf-8")
if keys[0] not in g:
    keylist = ", ".join("'%s'" % k for k in keys)
    g = g.replace("'play_rail_back_a', 'play_rail_back_b', 'play_rail_front_a', 'play_rail_front_b')",
                  "'play_rail_back_a', 'play_rail_back_b', 'play_rail_front_a', 'play_rail_front_b',\n             " + keylist + ")", 1)
    sizes = ", ".join('"%s": "1536x1024"' % k for k in keys)
    g = g.replace('"play_rail_front_a": "1536x1024", "play_rail_front_b": "1536x1024"},',
                  '"play_rail_front_a": "1536x1024", "play_rail_front_b": "1536x1024",\n                             ' + sizes + "},", 1)
    G.write_text(g, encoding="utf-8")
print(keys)
