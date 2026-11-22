import json, os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prompts.json")
d = json.load(open(p))
pre = ("portrait 2:3 playing card back design, a single centered ornate design with a border frame and a perfectly symmetrical pattern "
       "filling the whole card, flat front-on view, opaque background, no text, no letters, no numbers, no characters, no people, kid-friendly. ")
SETS = {
 "back_winter_evening": "icy blue and cream, a large frost crystal with small snowflakes",
 "back_festival_night": "deep orange and teal, a symmetrical string of festival bunting flags and paper stars",
 "back_closing_time": "deep violet and soft amber, a crescent moon above a single candle flame",
 "back_golden_gala": "rich purple and gold, a grand palace crown with gold filigree",
 "back_meadow_picnic": "soft green and sunny yellow, a ring of daisies and meadow flowers",
 "back_riverside_evening": "teal and violet, glowing fireflies drifting over reeds",
 "back_summit_camp": "stone grey and sunrise orange, three mountain peaks with a rising sun",
 "back_dune_market": "sandy gold and terracotta, a desert sun above rippled dunes",
 "back_marsh_lanterns": "moss green and lantern yellow, a hanging paper lantern with lily pads",
 "back_snowy_hearth": "cream and warm red, a cozy hearth fire with knit trim",
 "back_harbor_lights": "navy and brass, a ship anchor with rope and a small lighthouse glow",
 "back_tavern_feast": "deep red and gold, a grand feast platter with fruit and candles",
 "back_harvest_table": "orange and wheat gold, crossed wheat sheaves and autumn leaves",
 "back_winter_table": "ice blue and cream, one large snowflake with holly leaves",
}
s = d["card_back_subjects"]
for k, v in SETS.items():
    s[k] = pre + v
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
print(len(s))
