"""One shot: adds the four mark and boon Legendary Patrons (cut card prompts and rarity) to tools/patron_art/prompts.json."""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(ROOT, "tools", "patron_art", "prompts.json")
d = json.load(open(path, encoding="utf-8"))

tail = ("Legendary tier: a commanding hero pose with a glowing prop, the strongest light and golden rays behind, "
        "the biggest silhouette of all. The wooden name plate at the bottom reads exactly \"%s\" and nothing else is written anywhere")
new = {
    "duke_goldleaf": ("a proud duke with a neat silver beard and a long golden coat. Expression: proud. Pose: standing tall holding one gleaming gold coin up high. Prop: a tall glowing stack of gold coins. Outfit colour: radiant gold and cream. Silhouette: wide shoulders and a tall collar. Camera framing: full body low angle.", "Duke Goldleaf"),
    "clover_queen": ("a cheerful queen with long brown hair and a crown of four leaf clovers in a flowing green gown. Expression: joyful. Pose: standing tall with one arm raised. Prop: a giant glowing four leaf clover. Outfit colour: emerald green and gold. Silhouette: wide gown. Camera framing: full body low angle.", "Clover Queen"),
    "jolly_jester": ("a laughing jester in a red and yellow checkered outfit with a bell hat. Expression: laughing. Pose: mid leap. Prop: a spinning ring of playing cards in the air. Outfit colour: ruby red and sunny yellow. Silhouette: pointed hat and curled shoes. Camera framing: full body low angle.", "Jolly Jester"),
    "boon_keeper": ("a gentle keeper with a long white beard in a deep blue robe covered in tiny stars. Expression: kind. Pose: standing tall holding a jar up high. Prop: a glowing jar full of little sparkles. Outfit colour: midnight blue and silver. Silhouette: long robe and a pointed hat. Camera framing: full body low angle.", "Boon Keeper"),
}
for key, (body, name) in new.items():
    d["ctp_subjects"]["ctp_" + key] = "the same legendary card, same frame and gem, with the character replaced by " + body + " " + (tail % name)
    d["ctp_rarity"][key] = "legendary"
    assert key in d["subjects"], key

with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("ok", len(d["ctp_subjects"]), len(d["ctp_rarity"]))
