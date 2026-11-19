"""One-off: add Concept T Patron portrait prompts for batches 2 and 3 (Rare, Epic, Legendary)."""
import json, pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

RAR = {  # id -> (rarity, name, character)
    "early_bird": ("rare", "Early Bird", "a cheerful young man with messy sandy hair and light skin in a sunrise yellow jacket, holding a small blue songbird on his finger, a golden sunrise glow behind him"),
    "night_owl": ("rare", "Night Owl", "a calm woman with short silver hair and brown skin in a deep indigo cloak with star patterns, a friendly owl on her shoulder, a crescent moon glow behind her"),
    "full_suit_feast": ("rare", "Full Suit Feast", "a plump happy cook with a black bun and tan skin in a bright red apron, proudly presenting a big golden platter of food, four small card suit symbols floating around"),
    "foursome_table": ("rare", "Foursome Table", "a cheerful pair of two friends standing close together, one with green hair and one with pink hair, both in matching blue vests, each holding up two fingers for four fingers in all"),
    "royal_road": ("rare", "Royal Road", "a noble traveller with wavy brown hair and olive skin in a royal blue cape with gold trim, walking forward along a golden brick road with one hand raised"),
    "bread_starter": ("rare", "Bread Starter", "a smiling baker with curly white hair and a flour smudge on her dark brown cheek in a cream apron, holding a big glass jar of bubbly dough beside a fresh loaf"),
    "overtime": ("rare", "Overtime", "a tired but cheerful clerk with round glasses and neat black hair and light skin in a green vest, holding a big brass pocket clock, with a steaming mug of cocoa on the desk behind"),
    "house_special": ("epic", "House Special", "a flamboyant chef with a tall purple hat and a waxed moustache and dark skin in a purple and gold jacket, lifting the lid off a glowing silver dish, sparkles rising"),
    "full_house_crowd": ("epic", "Full House Crowd", "a happy crowd of five different blocky friends squeezed together in the frame, waving and laughing, different hair colours and hats, the tallest in the middle with a purple scarf"),
    "house_tab": ("epic", "House Tab", "a careful bookkeeper with a long white beard and gold spectacles and pale skin in a purple robe, holding a huge open ledger book with a quill, little gold coins floating up from the page"),
    "veterans_table": ("epic", "Veteran's Table", "a proud old soldier with a grey braided beard and tan skin in a polished purple coat with medals, sitting at a round table with one hand resting on a stack of cards, kind eyes"),
    "house_favorite": ("legendary", "House Favorite", "a radiant champion with golden hair and a gold crown and warm brown skin in a white and gold royal coat with a flowing cape, both arms raised in victory, golden light rays behind the character"),
}

d["ctp_rarity"].update({k: v[0] for k, v in RAR.items()})
subj = d["ctp_subjects"]
for k, (rar, name, ch) in RAR.items():
    rays = " with golden light rays behind the character" if rar == "legendary" else ""
    subj["ctp_" + k] = (
        f"the same {rar} card, same frame and gem, with the character replaced by {ch}{rays}. "
        f"The wooden name plate at the bottom reads exactly \"{name}\" and nothing else is written anywhere"
    )
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(len(subj), "ctp subjects")
