import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
d["title_subjects"].setdefault("welcoming_host", "an avatar holding a tavern door wide open with a warm welcoming smile, golden light and a small group of friends arriving")
d["title_subjects"].setdefault("tavern_ambassador", "an avatar in a fancy ribbon sash holding up a glowing lantern and waving a crowd of friends toward a tavern door")
d["menu_icon_subjects"].setdefault("invite", "a sealed parchment invitation envelope with a gold wax seal and a small glowing lantern, single centered subject with generous margin on a plain dark brown background, square composition, painterly, no text, no letters, no numbers, kid-friendly")
d["challenge_subjects"].setdefault("quick_run", "a small brass pocket watch with a golden lightning bolt and four tiny lanterns in a row, single centered subject with generous margin on a plain dark brown background, square composition, painterly, no text, no letters, no numbers, kid-friendly")
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["title_subjects"]))
