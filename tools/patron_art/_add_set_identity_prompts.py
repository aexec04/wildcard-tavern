#!/usr/bin/env python3
"""One-off: Frosted Garden, Mountain Festival and Closing Time shop room, keeper (behind and wave) and two button plates each. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
G = pathlib.Path(__file__).resolve().parent / "generate_patron_art.py"
d = json.loads(P.read_text(encoding="utf-8"))
SAFE = "no text, no letters, no numbers, no logos, no people, no characters, no bottles, no glasses, no weapons, kid-friendly"
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, soft warm light, original art, "
         "no text, no letters, no numbers, no logos, no bottles, no alcohol, no weapons, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
PMAG = ", on a flat solid pure magenta #FF00FF background with no gradient, clean sharp edges, the single piece centred with generous margin all round"
KEEPFIT = "Keep exactly the same shape, proportions, border thickness and corner layout as the reference plate. "
NO = ", completely blank centre, no letters, no numbers, no people, no bottles, no weapons"
SETS = {
    "frost": dict(
        room="a snowy winter garden conservatory: pale blue and silver frosted glass walls with white trim, snow dusted potted evergreens, hanging warm lanterns, a soft silver and blue palette with warm lantern glow",
        counter="frosted pale wood and silver", outfit="a thick wool winter coat in soft blue with a cream scarf and a small silver snowflake pin on the chest",
        look="a pale blue and silver frosted plate", trim="white frost trim", dark="deep frosted blue", green="bright icy teal blue"),
    "fest": dict(
        room="a mountain village festival square at dusk: wooden stalls, strings of colourful painted bunting flags, hanging string lights, warm orange and teal colours, pine trees and mountains in the evening sky",
        counter="rustic warm wood with bunting", outfit="an embroidered festival vest in orange and teal over a white shirt and a feathered hat",
        look="a warm orange and teal plate", trim="painted bunting trim", dark="deep teal", green="warm festival orange"),
    "close": dict(
        room="a quiet lamp lit tavern after hours: deep navy and amber, chairs turned up on the tables, soft moonlight through the windows, a few glowing amber lamps",
        counter="dark navy wood with amber lamp glow", outfit="a nightcap and a cozy nightgown style robe in navy, holding a small lit candle in a holder",
        look="a midnight navy and amber plate", trim="soft gold trim", dark="midnight navy", green="warm amber"),
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

add = '''# Frosted Garden, Mountain Festival and Closing Time identity: shop room, keeper pieces and two plates per set (edits of the classic pieces)
for _s in ("frost", "fest", "close"):
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
if "pk_frost_btn_dark" not in s and '"frost", "fest"' not in s:
    assert marker in s
    s = s.replace(marker, add + marker, 1)
    G.write_text(s, encoding="utf-8")
print("ok")
