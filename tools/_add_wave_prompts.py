"""One-off: add title_subjects prompts for the 30 second-wave achievements and endless_rule_subjects for 10 Crowd Rules.
Safe to rerun (only adds missing keys)."""
import json
import re

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)

titles = {
    "hand_hundred": "an avatar proudly fanning a hundred playing cards in a wide arc, happy",
    "hand_five_hundred": "an avatar in a tiny shark-fin hat dealing cards at lightning speed on a tavern table",
    "hand_two_thousand": "an avatar in a gold top hat dealing a glowing river of cards between both hands",
    "ten_runs": "an avatar waving hello beside a tavern door with a friendly smile, a name tag on the apron",
    "fifty_runs": "an avatar sitting comfortably on a worn wooden stool with a brass nameplate, relaxed",
    "stake_two": "an avatar bowing to a cheering crowd of small blocky guests, a gold star above",
    "stake_four": "an avatar carrying a tray through a busy tavern with a big wall clock behind",
    "stake_six": "an avatar squeezing happily between a packed crowd of blocky guests at a crowded tavern",
    "stake_eight": "an avatar holding the very last glowing lantern in an empty tavern at closing time, heroic pose",
    "endless_twelve": "an avatar walking a winding lantern-lit road that goes past a tavern sign into the stars",
    "endless_fifteen": "an avatar with a travel pack and walking stick far along a long moonlit road",
    "endless_thirty": "an avatar holding a glowing infinity symbol made of lantern light over a night road",
    "streak_three": "an avatar waving from a window with three lit candles in a row",
    "streak_seven": "an avatar beside a calendar page with seven gold stars, cheerful",
    "streak_fourteen": "an avatar warming hands at a roaring hearth with fourteen tiny flames above it",
    "streak_thirty": "an avatar looking up at a huge full moon over the tavern roof, peaceful",
    "quests_five": "an avatar running with a rolled scroll and a happy grin through a tavern door",
    "quests_twentyfive": "an avatar pinning a stack of finished notes to a wooden quest board",
    "quests_hundred": "an avatar standing before a huge quest board covered in gold stamps, proud",
    "rank_five": "an avatar polishing a small bronze tavern star badge, smiling",
    "rank_ten": "an avatar in a nice apron holding a silver tavern star badge with a warm smile",
    "rank_fifteen": "an avatar holding a golden heart-shaped badge while guests cheer nearby",
    "rush_three": "an avatar ducking and grinning past three big shadowy guests with oversize hats",
    "rush_six": "an avatar holding a golden lasso beside six huge friendly shadow guests",
    "challenge_first": "an avatar balancing happily on one leg with a spinning swirl symbol overhead",
    "challenge_many": "an avatar wearing four different funny masks stacked up, performing a bow",
    "hat_trick": "an avatar tossing a top hat into the air with three gold stars trailing it",
    "hand_thousand": "an avatar surrounded by a tall swirl of a thousand floating playing cards, amazed",
    "map_spots": "an avatar peeking behind a wooden barrel with a magnifying glass, curious",
    "nights_cleared": "an avatar walking a glowing path with four lanterns lit along it, content",
}
for k, v in titles.items():
    d["title_subjects"].setdefault(k, v)

tail = ", single centered subject with generous margin on a plain dark brown background, square composition, painterly, no text, no letters, no numbers, kid-friendly"
rules = {
    "rowdy_bosses": "a small wooden drum with crossed drumsticks and a cracked dark mask behind it",
    "pricey_patrons": "a wooden price tag with a gold coin on a string and a tiny upward arrow",
    "costly_rerolls": "two circling arrows around a gold coin on a wooden plaque",
    "thin_interest": "a leather coin purse with a few gold coins and a small downward arrow",
    "second_sting": "a small friendly scorpion made of dark wood holding a playing card",
    "tight_seats": "a tiny wooden chair squeezed between two stacked chairs",
    "lean_tips": "a small wooden bowl with only one gold coin in it",
    "packed_shelf": "a crowded wooden shelf of jars and recipe cards packed tight",
    "short_rations": "a small plate with a single crumb and a tiny bread loaf next to a playing card",
    "short_shift": "a brass hourglass nearly out of sand on a wooden table",
}
d.setdefault("endless_rule_subjects", {})
for k, v in rules.items():
    d["endless_rule_subjects"].setdefault(k, v + tail)
# the registry must match the prompts
src = open("src/Shared/Engine/EndlessRules.lua", encoding="utf-8").read()
ids = re.findall(r'\{ id = "([a-z_]+)", name', src)
missing = [i for i in ids if i not in d["endless_rule_subjects"]]
print("endless rule ids:", len(ids), "missing prompts:", missing)

out = json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else "")
open(p, "w", encoding="utf-8").write(out)
print("titles prompts:", len(d["title_subjects"]))
