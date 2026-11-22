import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
new = {
    "lone_wolf": ("common", "a quiet avatar traveller in a gray scarf sitting alone at a small corner table with a bowl of stew and a friendly grey wolf pup at their feet",
                  "a young man with messy grey hair and a long gray scarf", "calm", "sitting", "a small bowl of stew", "slate gray and cream", "medium and relaxed", "waist-up", "Lone Wolf"),
    "even_keel": ("common", "a cheerful avatar in a blue striped shirt perfectly balancing a wooden plank on one finger with two matching red apples on each end",
                  "a cheerful woman with a short brown bob and a blue striped shirt", "calm and proud", "standing very straight", "a balanced plank with two apples", "sky blue and white", "medium and steady", "waist-up", "Even Keel"),
    "odd_duck": ("common", "a goofy smiling avatar wearing a yellow duck hat and holding a rubber duck, waddling happily through the tavern",
                 "a goofy boy in a big yellow duck hat", "laughing", "waddling", "a yellow rubber duck", "bright yellow and orange", "small and round", "waist-up", "Odd Duck"),
    "good_company": ("uncommon", "a friendly avatar host in a green vest waving warmly with three little friends seated at a long table behind",
                     "a warm host with a big grin and a green vest", "delighted", "waving with both arms", "a plate of rolls for the table", "forest green and gold", "broad and welcoming", "three-quarter", "Good Company"),
}
for pid, (rar, subj, who, expr, pose, prop, col, sil, frame, name) in new.items():
    d["subjects"][pid] = subj
    d["ctp_rarity"][pid] = rar
    tier = d["ctp_ladder"][rar]
    d["ctp_subjects"]["ctp_" + pid] = (
        "the same %s card, same frame and gem, with the character replaced by %s. Expression: %s. Pose: %s. Prop: %s. "
        "Outfit colour: %s. Silhouette: %s. Camera framing: %s. %s. The wooden name plate at the bottom reads exactly \"%s\" "
        "and nothing else is written anywhere" % (rar, who, expr, pose, prop, col, sil, frame, tier, name))
indent = 2 if raw.startswith("{\n  ") else 4
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=indent, ensure_ascii=False) + "\n")
