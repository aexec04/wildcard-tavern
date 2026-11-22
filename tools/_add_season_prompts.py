import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
tail = ", no text, no letters, no numbers, kid-friendly"
d.setdefault("season_subjects", {})
d["season_subjects"].setdefault("season_harvest_moon", "a wide painted banner of a huge golden harvest moon over rolling fields dotted with glowing lanterns and haystacks, warm candlelit tavern style, wide landscape composition" + tail)
d["season_subjects"].setdefault("season_winter_welcome", "a wide painted banner of a snowy village street with warm glowing tavern windows, strings of lanterns and a starry blue sky, warm candlelit style, wide landscape composition" + tail)
d["season_subjects"].setdefault("menu_season", "a golden ticket with a ribbon and a tiny moon on it, single centered subject with generous margin on a plain dark brown background, square composition, painterly" + tail)
d["card_back_subjects"].setdefault("harvest_moon", "A single card back design, portrait 2:3, symmetrical, ornate gold border frame, deep amber and brown with a large golden harvest moon in the center, wheat sprigs and tiny lanterns around it" + tail)
d["card_back_subjects"].setdefault("winter_welcome", "A single card back design, portrait 2:3, symmetrical, ornate pale gold border frame, deep winter blue with a glowing lantern and a knitted scarf pattern, snowflakes and stars around it" + tail)
d["title_subjects"].setdefault("season_harvest_moon", "an avatar in a harvest scarf holding a basket of glowing pumpkins under a huge golden moon, happy")
d["title_subjects"].setdefault("season_winter_welcome", "an avatar in a cozy winter scarf and hat offering a steaming mug of cocoa at a snowy tavern door, happy")
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["season_subjects"]))
