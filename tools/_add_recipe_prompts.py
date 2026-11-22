import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
new = {
    "pair_platter": "an avatar baker proudly carrying a wide platter with two pairs of matching dumplings, steam rising",
    "suit_platter": "an avatar baker setting down a platter of five identical glowing red hearts shaped pastries",
    "row_platter": "an avatar baker lining up five pastries in a neat rising row on a long wooden board",
    "feast_platter": "an avatar baker serving a giant feast platter with a roast and a tall stack of four matching pies",
    "single_serving": "an avatar baker holding up one perfect small bowl of soup with a tiny gold star above it",
    "fresh_menu": "an avatar baker writing a new daily menu on a chalkboard with a green sprout drawn beside it",
    "cooks_choice": "an avatar chef pointing a ladle at two glowing sparkling dishes with a chef hat on",
    "stamp_collector": "an avatar clerk stamping two playing cards with a big wooden rubber stamp, colorful ink",
    "family_style": "an avatar cook passing a huge shared bowl around a table of three smiling friends",
    "silver_platter": "an avatar waiter carrying a shining silver tray with a glowing silver playing card on it",
    "gold_leaf": "an avatar baker brushing thin gold leaf onto two playing cards with a tiny brush",
    "patron_echo": "an avatar standing in front of a magic mirror that shows a second identical avatar waving back",
    "twin_card": "an avatar holding up two identical playing cards side by side with a surprised grin",
    "swap_out": "an avatar tossing an old crumpled playing card into a bin and catching a shiny new one",
    "suit_flip": "an avatar flipping a tray of playing cards in the air so the red and black suits swap places",
    "patron_shuffle": "an avatar spinning a little wooden wheel of tavern guests portraits, one guest waving goodbye",
}
for k, v in new.items():
    d["recipe_subjects"].setdefault(k, v)
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["recipe_subjects"]))
