import json
import re

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
tail = ", single centered subject with generous margin on a plain dark brown background, square composition, painterly, no text, no letters, no numbers, kid-friendly"
subjects = {
    "classic_numbers": "a row of plain cream colored glowing score digits floating over a wooden table",
    "ember_numbers": "score digits made of glowing orange embers with small sparks",
    "frost_numbers": "score digits made of pale blue ice crystals with tiny snowflakes",
    "gold_numbers": "score digits made of shiny gold coins with a warm glow",
    "leaf_numbers": "score digits made of green meadow leaves with tiny flowers",
    "rainbow_numbers": "score digits glowing in rainbow colors with sparkles",
    "plain_trail": "a single playing card sliding over a wooden table with a soft shadow",
    "sparkle_trail": "a playing card leaving a trail of golden sparkles behind it",
    "ember_trail": "a playing card leaving a trail of orange embers behind it",
    "star_trail": "a playing card leaving a trail of little yellow stars behind it",
    "petal_trail": "a playing card leaving a trail of pink flower petals behind it",
    "ribbon_trail": "a playing card leaving a trail of purple and pink ribbons behind it",
    "pop_finisher": "a small golden star burst popping over a playing card",
    "firework_finisher": "three colorful fireworks bursting above a card table",
    "confetti_finisher": "colorful confetti raining down over a stack of playing cards",
    "lantern_finisher": "glowing paper lanterns rising from a card table",
    "goldrain_finisher": "a shower of gold coins falling onto a card table",
    "crown_finisher": "a golden crown flashing with white light above a playing card",
    "no_aura": "a plain round wooden name badge with a thin gold rim",
    "warm_aura": "a round name badge glowing with warm candle light",
    "ember_aura": "a round name badge ringed with orange flames",
    "frost_aura": "a round name badge ringed with pale blue frost",
    "legend_aura": "a round name badge with a bright golden crown and gold glow",
    "star_aura": "a round name badge surrounded by glowing yellow stars",
}
d.setdefault("flair_subjects", {})
for k, v in subjects.items():
    d["flair_subjects"].setdefault(k, v + tail)
src = open("src/Shared/Engine/Flair.lua", encoding="utf-8").read()
ids = re.findall(r'\{ id = "([a-z_]+)", slot = ', src)
missing = [i for i in ids if i not in d["flair_subjects"]]
print("flair options:", len(ids), "missing prompts:", missing)
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
