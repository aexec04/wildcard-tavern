"""One-off: add Concept T Patron portrait prompts to prompts.json (batch 1: Common and Uncommon)."""
import json, pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

d["ctp_style"] = (
    "Edit the reference image, which is a finished trading card. Keep EXACTLY the same card: same frame, same gem, same wooden name plate, same "
    "proportions, same hand-painted blocky Roblox tavern style, palette and lighting, on a plain light gray background. Change ONLY the character "
    "inside the frame and the name on the wooden plate. The new character is a blocky Roblox avatar with chunky proportions and hand-painted "
    "textures, bright, friendly and colourful, a different face, hair, skin tone, age and outfit from the reference. Not dark, no skulls, no "
    "hooded figures, no weapons. The only text on the whole card is the name on the wooden plate, spelled exactly as given, no other letters or "
    "numbers anywhere. Kid-friendly original art"
)

RAR = {  # id -> (rarity, name, character)
    "the_regular": ("common", "The Regular", "a cheerful middle aged man with a round face and a brown beard in a green waistcoat, sitting happily on his usual stool and raising a wooden cup of juice"),
    "lucky_dice": ("common", "Lucky Dice", "a grinning young woman with curly orange hair and freckles in a red jacket, holding up two big white dice"),
    "straight_shooter": ("common", "Straight Shooter", "a tall confident teenager with short black hair and dark skin in a blue vest and a feathered cap, pointing straight ahead with one finger"),
    "tip_jar": ("common", "Tip Jar", "a smiling older woman with white hair in a bun and glasses in a lilac apron, holding a big glass jar full of gold coins"),
    "queens_gambit": ("common", "Queen's Gambit", "a proud young woman with long dark braids and tan skin in a purple dress with a small gold tiara, holding a playing card"),
    "the_apprentice": ("common", "The Apprentice", "a small eager boy with messy blond hair in an oversized brown apron and goggles pushed up on his head, carrying a stack of books"),
    "bargain_hunter": ("common", "Bargain Hunter", "a sharp eyed woman with short red hair and pale skin in a teal coat and a big shopping basket, holding up a coin and smiling"),
    "warm_hearth": ("common", "Warm Hearth", "a gentle large man with a bald head and a grey moustache in a knitted orange sweater, standing by a small glowing fireplace with a warm smile"),
    "curtain_call": ("uncommon", "Curtain Call", "a dramatic performer with slicked back dark hair and olive skin in a gold and red stage coat, taking a deep bow with one arm out"),
    "the_bard": ("uncommon", "The Bard", "a cheerful young man with long chestnut hair and a green feathered hat in a patchwork cloak, playing a small round lute"),
    "penny_pincher": ("uncommon", "Penny Pincher", "a thin careful man with a pointed grey beard and round spectacles in a brown coat, counting a few small coins in his palm"),
    "big_spender": ("uncommon", "Big Spender", "a jolly broad shouldered woman with a bright yellow hat and dark brown skin in a fancy teal coat, tossing a handful of gold coins in the air"),
    "boss_bane": ("uncommon", "Boss's Bane", "a brave young hero with spiky silver hair and light brown skin in a bright blue tunic and a short cape, striking a bold pose with a fist raised"),
    "tasting_menu": ("uncommon", "Tasting Menu", "a friendly chef with a tall white hat and a curly black moustache in a clean white apron, holding a small silver tray with tiny tarts"),
}

d["ctp_rarity"] = {k: v[0] for k, v in RAR.items()}
subj = d.setdefault("ctp_subjects", {})
for k, (rar, name, ch) in RAR.items():
    subj["ctp_" + k] = (
        f"the same {rar} card, same frame and gem, with the character replaced by {ch}. "
        f"The wooden name plate at the bottom reads exactly \"{name}\" and nothing else is written anywhere"
    )
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(len(subj), "ctp subjects")
