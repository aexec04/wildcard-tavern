import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
tail = ", single centered subject with generous margin on a plain dark brown background, square composition, painterly, no text, no letters, no numbers, kid-friendly"
store = {
    "flair_rainbow_numbers": "glowing rainbow colored score digits floating over a wooden table",
    "flair_ribbon_trail": "a playing card trailing purple and pink ribbons",
    "flair_crown_finisher": "a golden crown flashing with white light above a playing card",
    "flair_star_aura": "a round name badge surrounded by glowing yellow stars",
    "flair_bundle": "four small glowing gift boxes tied with ribbons: one rainbow, one ribbon, one crown, one star",
    "premium_harvest_moon": "a golden ticket with a harvest moon, wheat and a tiny lantern on it",
    "premium_winter_welcome": "a silver ticket with a snowflake, a knitted scarf and a tiny lantern on it",
}
for k, v in store.items():
    d["store_subjects"].setdefault(k, v + tail)
d.setdefault("season_subjects", {})
card = "A single card back design, portrait 2:3, symmetrical, ornate gold border frame, "
d["card_back_subjects"].setdefault("harvest_premium", card + "rich amber with a gold harvest moon, wheat sprigs and a ring of tiny lanterns" + ", no text, no letters, no numbers, kid-friendly")
d["card_back_subjects"].setdefault("winter_premium", card + "deep winter blue with silver snowflakes, a glowing lantern and a knitted scarf pattern" + ", no text, no letters, no numbers, kid-friendly")
d["title_subjects"].setdefault("season_premium_harvest", "an avatar in a golden harvest cape holding up a glowing gold pumpkin lantern, proud")
d["title_subjects"].setdefault("season_premium_winter", "an avatar in a silver winter cloak holding a glowing lantern in falling snow, proud")
d["set_backdrop_subjects"].setdefault("harvest_table", "a warm tavern table at harvest time with gold lanterns, pumpkins and wheat under a big harvest moon, wide painterly background" + ", no text, no letters, no numbers, kid-friendly")
d["set_backdrop_subjects"].setdefault("winter_table", "a cozy tavern table in winter with silver lanterns, knitted scarves and snow outside the window, wide painterly background" + ", no text, no letters, no numbers, kid-friendly")
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["store_subjects"]))
