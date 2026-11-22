import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
tail = ", single centered subject with generous margin on a plain dark brown background, square composition, painterly, no text, no letters, no numbers, kid-friendly"
d["menu_icon_subjects"].setdefault("boss_scout", "a golden spyglass pointing at a small crowned mask with a lantern glowing behind it" + tail)
d["menu_icon_subjects"].setdefault("rule_ban", "a round wooden token with a golden shield and a crossed out scroll on it, glowing warm light" + tail)
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print("ok")
