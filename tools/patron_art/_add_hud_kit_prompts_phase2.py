#!/usr/bin/env python3
"""One-off: add the hud_kit prompts for the remaining 13 sets (phases 2a and 2b). No API calls. Re-run safe (never touches phase 1 keys)."""
import json, pathlib

HERE = pathlib.Path(__file__).resolve().parent
src = (HERE / "_add_hud_kit_prompts.py").read_text(encoding="utf-8")
ns = {"__file__": str(HERE / "_add_hud_kit_prompts.py")}
exec(src.split("out = {}")[0], ns)  # reuse pieces() and MAG without running the phase 1 writer
pieces, MAG = ns["pieces"], ns["MAG"]
P = HERE / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
SETS = {
    "classic_tavern": dict(theme="a cozy everyday wooden tavern with warm lanterns", pal="dark walnut wood, warm brass, aged cream parchment and soft amber",
        mat="dark wooden beams, brass studs, parchment paper and a small hanging lantern",
        btn="a round dark-walnut wooden medallion with a thin brass rim and tiny brass studs"),
    "festival_night": dict(theme="a mountain festival night with lanterns and ribbons", pal="warm orange, cream and glowing amber",
        mat="paper lanterns, ribbons and tiny bunting flags",
        btn="a round paper-lantern disc with a ribbon bow at the top"),
    "golden_gala": dict(theme="a tavern dressed in gold for a grand evening", pal="rich gold, champagne cream and deep amber",
        mat="gold filigree, small stars and ribbon bows",
        btn="a round gold filigree medallion with a tiny star at the top"),
    "closing_time": dict(theme="a quiet tavern as the night winds down, dim lamps", pal="muted brown, dusty tan and low amber",
        mat="a small oil lamp, a sleeping candle and wood grain",
        btn="a round worn-wood coaster ring with a tiny dim lamp flame at the top"),
    "summit_camp": dict(theme="a mountain summit camp at dusk with a small campfire", pal="slate grey, pale snow white and ember orange",
        mat="pine branches, snowy peaks and a tiny flame",
        btn="a round slate stone disc ringed with pine needles and a tiny ember at the top"),
    "riverside_evening": dict(theme="a quiet riverbank at evening with a footbridge and lanterns", pal="cool teal, twilight blue and pale mint",
        mat="willow leaves, ripples and small hanging lanterns",
        btn="a round smooth river-stone disc with a ring of willow leaves and a tiny lantern at the top"),
    "dune_market": dict(theme="a golden desert dune market at sunset", pal="sandy gold, warm terracotta and cream",
        mat="woven cloth patterns, tassels and small crescent shapes",
        btn="a round woven terracotta disc with a small tassel and a tiny crescent at the top"),
    "marsh_lanterns": dict(theme="a misty marsh with glowing lanterns", pal="soft moss green, grey-green mist and warm lantern yellow",
        mat="reeds, cattails and tiny floating lanterns",
        btn="a round mossy lily-pad disc with a tiny glowing lantern at the top"),
    "snowy_hearth": dict(theme="a cozy hearth in the snowy hills", pal="pale blue-white, warm firelight orange and wood brown",
        mat="snow-capped logs, a small flame and knitted trim",
        btn="a round snow-capped log slice with knitted trim and a tiny flame at the top"),
    "harbor_lights": dict(theme="a harbor at night with glowing lighthouse lights", pal="deep sea teal, navy blue and warm lamp yellow",
        mat="rope knots, small anchors and tiny shells",
        btn="a round ship-wheel style disc wrapped in rope with a tiny shell at the top"),
    "tavern_feast": dict(theme="a big tavern feast table", pal="warm cream, roasted gold and rosy red",
        mat="wheat sheaves, bread and fruit leaves",
        btn="a round golden bread-crust disc with a small wheat sprig at the top"),
    "harvest_table": dict(theme="a table dressed for the Harvest Moon", pal="harvest orange, cream and deep amber",
        mat="pumpkin vines, autumn leaves and a small moon",
        btn="a round small pumpkin-skin disc with a curled vine and a tiny moon at the top"),
    "winter_table": dict(theme="a cozy winter welcome table", pal="cool periwinkle blue, snow white and soft silver",
        mat="pine sprigs, snowflakes and knitted scarf stitches",
        btn="a round knitted-wool disc with a tiny snowflake at the top"),
}
subj = d["hud_kit_subjects"]
added = 0
for sid, s in SETS.items():
    for piece, text in pieces(s).items():
        k = sid + "__" + piece
        if k not in subj:
            subj[k] = text + MAG
            added += 1
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("added", added, "total", len(subj))
