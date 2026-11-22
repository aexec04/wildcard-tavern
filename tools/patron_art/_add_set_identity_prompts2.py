#!/usr/bin/env python3
"""One-off: shop room, keeper (behind and wave) and two button plates for ten more card sets. No API calls.
Same recipe as _add_set_identity_prompts.py."""
import json, pathlib
H = pathlib.Path(__file__).resolve().parent
P, G = H / "prompts.json", H / "generate_patron_art.py"
d = json.loads(P.read_text(encoding="utf-8"))
SAFE = "no text, no letters, no numbers, no logos, no people, no characters, no bottles, no glasses, no weapons, kid-friendly"
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, soft warm light, original art, "
         "no text, no letters, no numbers, no logos, no bottles, no alcohol, no weapons, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
PMAG = ", on a flat solid pure magenta #FF00FF background with no gradient, clean sharp edges, the single piece centred with generous margin all round"
KEEPFIT = "Keep exactly the same shape, proportions, border thickness and corner layout as the reference plate. "
NO = ", completely blank centre, no letters, no numbers, no people, no bottles, no weapons"
SETS = {
    "dune": dict(room="a warm desert bazaar with striped sand and terracotta awnings, clay pots and woven rugs, sandy stone walls", counter="sun-bleached wood with a striped awning",
        outfit="a light linen robe in sand colour with a wide straw sun hat", look="a sandy gold and terracotta plate", trim="woven rug pattern trim", dark="deep terracotta", green="sandy gold"),
    "marsh": dict(room="a misty marsh boardwalk at dusk with paper lanterns on poles, reeds and soft fog, deep green planks and soft yellow light", counter="damp mossy dark wood with hanging paper lanterns",
        outfit="a green raincoat and a wide brim hat, holding a small glowing paper lantern", look="a moss green and lantern yellow plate", trim="reed and lantern trim", dark="deep moss green", green="warm lantern yellow"),
    "hearth": dict(room="a snowed-in cabin by a crackling fireplace: cream log walls, a warm red rug, snow outside the window, soft firelight", counter="honey log wood with a knitted runner",
        outfit="a chunky cream knit sweater with a warm red pattern and fluffy red earmuffs", look="a cream and warm red plate", trim="knitted wool trim", dark="warm deep red", green="soft cream"),
    "harbor": dict(room="a lantern lit harbor dock at dusk: navy blue sky, wooden pier, ropes and crates, glowing brass lanterns", counter="weathered navy painted wood with brass fittings",
        outfit="a navy sailor coat with brass buttons and a sailor cap", look="a navy and brass plate", trim="brass rope trim", dark="deep navy", green="polished brass"),
    "feast": dict(room="a grand feast hall with long wooden tables, rich red banners with gold trim, candle chandeliers and platters of bread and fruit", counter="polished dark wood with red and gold cloth",
        outfit="a white chef coat with gold buttons and a tall white chef hat", look="a deep red and gold plate", trim="gold braid trim", dark="deep red", green="rich gold"),
    "harvest": dict(room="an autumn harvest barn: orange pumpkins, wheat sheaves, hay bales and warm wooden beams, soft golden light", counter="warm barn wood with wheat sheaves",
        outfit="blue denim overalls over a plaid shirt and a straw hat", look="an orange and wheat plate", trim="wheat sheaf trim", dark="deep autumn orange", green="golden wheat"),
    "wtable": dict(room="a snowy winter dining table scene: ice blue and cream, frosted window, a long cream tablecloth, pine branches and candles", counter="pale frosted wood with a cream cloth",
        outfit="a thick scarf in ice blue and cream and woolly mittens with a warm coat", look="an ice blue and cream plate", trim="frosted snowflake trim", dark="deep ice blue", green="soft cream"),
    "meadow": dict(room="a sunny meadow picnic: soft green grass, yellow wildflowers, a checkered picnic cloth, blue sky with white clouds", counter="light wood with a green checkered cloth",
        outfit="a yellow sun dress with a wide straw hat", look="a meadow green and sunny yellow plate", trim="wildflower trim", dark="deep meadow green", green="sunny yellow"),
    "river": dict(room="a riverside evening with fireflies: teal water, violet dusk sky, wooden jetty, glowing fireflies, reeds", counter="dusky dark wood with glowing fireflies",
        outfit="a light teal jacket, holding a small glowing lantern", look="a teal and violet plate", trim="firefly glow trim", dark="deep violet", green="bright teal"),
    "summit": dict(room="a mountain summit camp at sunrise: stone grey rocks, orange sunrise sky, a small tent and a flag, thin snow peaks", counter="flat stone slabs and rough wood",
        outfit="a hiking jacket in orange with a sturdy backpack and a woolly hat", look="a stone grey and orange plate", trim="rope and stone trim", dark="deep stone grey", green="sunrise orange"),
}
for k, s in SETS.items():
    d["shop_scene_subjects"]["shop_room_" + k] = (
        "the same tavern market counter room as the reference, same layout and same camera, but dressed as " + s["room"] + ": a long " + s["counter"] +
        " bar counter in the lower third with the counter top clear and empty, shelves of card boxes and jars, warm light, " + SAFE)
    keep = ("Marlo the friendly shopkeeper, redressed: same blocky Roblox figure, same size, same crop and same pose as the reference image, no hood, "
            "bare friendly face with a kind smile, wearing " + s["outfit"] + ", no bundle pack, exactly two hands, shown from the waist up, large, facing the viewer, "
            "portrait 3:4 composition, centered, ")
    d["shop_scene_subjects"]["shop_marlo_%s_behind" % k] = keep + "one arm extended palm up presenting goods toward the viewer's right" + STYLE + MAG
    d["shop_scene_subjects"]["shop_marlo_%s_wave" % k] = keep + "one hand raised in a small friendly wave, the other hand resting at his side" + STYLE + MAG
    d["pk_subjects"]["pk_%s_btn_dark" % k] = (KEEPFIT + "Redraw it as " + s["look"] + ": " + s["dark"] + " face with a soft sheen, " + s["trim"] +
        " and small corner flourishes, darker and calmer than the primary plate so ivory text reads on it" + NO + PMAG)
    d["pk_subjects"]["pk_%s_btn_green" % k] = (KEEPFIT + "Redraw it as a primary button plate: " + s["green"] + " face, " + s["trim"] +
        " and small corner flourishes, a slightly thicker bright border, text must read on it" + NO + PMAG)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

add = '''# ten more card sets identity: shop room, keeper pieces and two plates per set
for _s in ("dune", "marsh", "hearth", "harbor", "feast", "harvest", "wtable", "meadow", "river", "summit"):
    CATEGORY_OPTS["shop_scene"]["opaque"].append("shop_room_" + _s)
    CATEGORY_OPTS["shop_scene"].setdefault("sizes", {})["shop_room_" + _s] = "1536x1024"
    CATEGORY_OPTS["shop_scene"].setdefault("references", {})["shop_room_" + _s] = "art-wip/shop_scene/shop_room_a.png"
    for _p in ("behind", "wave"):
        CATEGORY_OPTS["shop_scene"]["sizes"]["shop_marlo_%s_%s" % (_s, _p)] = "1024x1536"
        CATEGORY_OPTS["shop_scene"]["references"]["shop_marlo_%s_%s" % (_s, _p)] = "art-wip/shop_scene/shop_marlo_%s.png" % _p
    for _p in ("dark", "green"):
        CATEGORY_OPTS["painted_kit"]["references"]["pk_%s_btn_%s" % (_s, _p)] = "art-wip/painted_kit/pk_w_btn_%s.png" % _p
'''
s = G.read_text(encoding="utf-8")
marker = "# deck tray and bottom rail:"
if '"dune", "marsh"' not in s:
    assert marker in s
    G.write_text(s.replace(marker, add + marker, 1), encoding="utf-8")
print("ok")
