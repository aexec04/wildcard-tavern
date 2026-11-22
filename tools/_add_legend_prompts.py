import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
tail = ", no text, no letters, no numbers, kid-friendly"
d.setdefault("legend_subjects", {})
legend = {
    "gold_cup": "a shining golden trophy cup with a small crown on a wooden table, glowing warm light, single centered subject on a plain dark brown background, square composition, painterly" + tail,
    "eternal_candle": "a tall white candle with a steady golden flame in a brass holder, glowing warm light, single centered subject on a plain dark brown background, square composition, painterly" + tail,
    "keepers_key": "a big ornate golden key with a crown shaped handle, glowing warm light, single centered subject on a plain dark brown background, square composition, painterly" + tail,
}
for k, v in legend.items():
    d["legend_subjects"].setdefault(k, v)
cardback = "A single card back design, portrait 2:3, symmetrical, ornate gold border frame, "
d["card_back_subjects"].setdefault("legend_gold", cardback + "deep brown with a big shining gold crown in the center and gold laurel leaves around it" + tail)
d["card_back_subjects"].setdefault("legend_crown", cardback + "royal purple with a tall golden crown and small gold stars in a ring" + tail)
d["card_back_subjects"].setdefault("legend_eternal", cardback + "midnight blue with a single glowing golden candle flame in the center and a ring of tiny gold stars" + tail)
d["title_subjects"].setdefault("legend_1", "an avatar standing tall under a glowing golden crown that floats above the head in a candlelit tavern, proud")
d["title_subjects"].setdefault("legend_5", "an avatar in a long golden cape holding a glowing trophy cup, a crowd of blocky guests cheering behind")
d["title_subjects"].setdefault("legend_9", "an avatar wearing a huge golden crown seated on a glowing throne made of playing cards, calm and kind")
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["legend_subjects"]))
