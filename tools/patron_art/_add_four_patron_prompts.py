import json, os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prompts.json")
d = json.load(open(p, encoding="utf-8"))
END = ' and nothing else is written anywhere'
def ctp(rar, tier, who, expr, pose, prop, outfit, sil, framing, name):
    return ("the same %s card, same frame and gem, with the character replaced by %s. Expression: %s. Pose: %s. Prop: %s. Outfit colour: %s. "
            "Silhouette: %s. Camera framing: %s. %s The wooden name plate at the bottom reads exactly \"%s\"%s") % (rar, who, expr, pose, prop, outfit, sil, framing, tier, name, END)
UNC = "Uncommon tier: a bit more distinctive, one bright coloured accent, soft light, plain background."
COM = "Common tier: an ordinary tavern folk in a relaxed pose with muted colours and a plain prop, soft even light, small and ordinary silhouette."
NEW = {
 "full_palette": ("uncommon", UNC, "a cheerful painter with curly black hair and a beret-free bare head, a paint-splashed smock", "proud", "holding up a big wooden palette",
                  "a wooden paint palette with red, yellow, blue and green dabs, held close and fully inside the frame", "rainbow splashes on warm cream", "medium and lively", "waist-up, the whole character and prop kept inside the frame on the tan parchment background", "Full Palette",
                  "a smiling avatar painter in a splattered smock holding a wooden palette of bright paint dabs beside an easel in a cozy tavern corner. Only candles, bowls, furniture and food in the scene"),
 "triple_scoop": ("uncommon", UNC, "a happy cook with short red hair and a white apron", "delighted", "presenting a treat",
                  "a cone with three round scoops of pastel ice cream, held up and fully inside the frame", "pink, mint and cream", "broad and friendly", "waist-up, the whole character and prop kept inside the frame on the tan parchment background", "Triple Scoop",
                  "a friendly avatar cook in a white apron holding a cone with three round pastel scoops in front of a tavern dessert counter. Only candles, bowls, furniture and food in the scene"),
 "spare_shuffle": ("common", COM, "a relaxed card dealer with messy brown hair and a green visor", "calm", "shuffling",
                  "a loose deck of playing cards fanned between both hands", "forest green and cream", "small and wiry", "waist-up", "Spare Shuffle",
                  "a calm avatar card dealer in a green visor shuffling a deck of cards at a small tavern table with a spare pile beside them. Only candles, bowls, furniture and food in the scene"),
 "final_bow": ("uncommon", UNC, "a graceful performer with a long dark ponytail and a velvet vest", "pleased", "taking a deep bow",
                  "a small golden bell held in one hand, fully inside the frame", "deep burgundy and gold", "tall and graceful", "waist-up, the whole character and prop kept inside the frame on the tan parchment background", "Final Bow",
                  "an avatar performer in a velvet vest taking a deep bow on a small tavern stage with curtains and a golden bell. Only candles, bowls, furniture and food in the scene"),
}
for pid, (rar, tier, who, expr, pose, prop, outfit, sil, framing, name, plain) in NEW.items():
    d["ctp_subjects"]["ctp_" + pid] = ctp(rar, tier, who, expr, pose, prop, outfit, sil, framing, name)
    d["ctp_rarity"][pid] = rar
    d["subjects"][pid] = plain
json.dump(d, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print("ok")
