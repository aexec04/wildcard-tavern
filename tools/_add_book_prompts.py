import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
new = {
    "book_patrons": "an avatar sitting at a long tavern table surrounded by dozens of friendly blocky guests all raising a toast with cocoa mugs",
    "book_recipes": "an avatar chef proudly holding a giant open recipe book with a glowing page, a pot steaming beside",
    "book_bosses": "an avatar gently petting a huge friendly shadowy boss figure with glowing eyes, both smiling, tavern background",
    "book_sets": "an avatar draping a golden tablecloth over a card table while cards of many colorful backs float around",
    "book_titles": "an avatar wearing a tall stack of different funny hats with little name tags, grinning",
    "book_badges": "an avatar wearing a sash covered in shiny round badges, standing proudly in a lantern lit tavern",
}
for k, v in new.items():
    d["title_subjects"].setdefault(k, v)
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["title_subjects"]))
