#!/usr/bin/env python3
"""One-off: write patron_variety.json (expression, pose, prop, outfit colour, silhouette, framing, who per Patron)
and rebuild prompts.json ctp_subjects from it. No API calls. Run: python3 tools/patron_art/_add_variety.py"""
import json, pathlib, re
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
P = HERE / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
reg = (ROOT / "src/Shared/Engine/Patrons.lua").read_text(encoding="utf-8")
names = {m.group(1): m.group(2) for m in re.finditer(r'id = "(\w+)",\s*name = "([^"]+)"', reg)}

# id: (expression, pose, prop, outfit colour, silhouette, framing, who)
V = {
# ---- Common: ordinary tavern folk, relaxed, muted colours, plain props
"the_regular": ("sleepy", "leaning", "a steaming cocoa mug", "muted brown", "hunched", "waist-up", "a stout older man with a gray beard and a flat cap"),
"lucky_dice": ("delighted", "mid laugh", "two big white dice", "faded tan", "small and wiry", "bust", "a young woman with curly orange hair and freckles"),
"suit_yourself": ("smug", "arms crossed", "a heart-shaped hand mirror", "dusty rose", "broad shoulders", "waist-up", "a tall man with slicked black hair and a thin moustache"),
"regulars_round": ("bored", "leaning", "an empty wooden mug", "slate gray", "slumped", "waist-up", "a middle aged woman with a gray braid"),
"threes_company": ("worried", "hiding behind a prop", "a tower of three wooden mugs", "olive green", "tall and thin", "waist-up", "a nervous teen with messy blond hair and glasses"),
"straight_shooter": ("deadpan", "pointing", "a long wooden ruler", "faded blue", "long scarf", "waist-up", "a dark skinned woman with short black hair"),
"all_matching": ("grumpy", "standing tall", "a neat folded napkin", "cream and brown", "broad shoulders", "waist-up", "a bald man with a round face and a tidy apron"),
"small_plate": ("shy", "turning away", "a tiny dinner plate", "muted lavender", "tiny", "bust", "a small young girl with two pigtails"),
"tab_regulars": ("grumpy", "leaning", "a long paper tab receipt", "dull green", "hunched", "waist-up", "a lanky man with a bushy red beard"),
"the_understudy": ("startled", "holding up an item", "a paper theatre mask on a stick", "faded plum", "tall and thin", "waist-up", "a young man with parted brown hair and freckles"),
"second_opinion": ("deadpan", "arms crossed", "a pair of round spectacles", "gray tweed", "broad shoulders", "waist-up", "an elderly woman with a white bun"),
"tip_jar": ("delighted", "holding up an item", "a glass jar of coins", "warm tan", "short and round", "waist-up", "a cheerful round man with rosy cheeks and a bald head"),
"sparkling_service": ("proud", "standing tall", "a shiny silver tray", "pale blue", "tall and thin", "waist-up", "a young woman with a neat black bob and a white apron"),
"rowdy_bunch": ("laughing", "mid laugh", "a wooden rolling pin", "dull green", "broad shoulders", "waist-up", "a loud big man with a curly brown beard"),
"sharp_dressed": ("smug", "standing tall", "a pocket watch on a chain", "charcoal", "tall hat", "waist-up", "a slim man with a trimmed goatee and a tall black hat"),
"double_down": ("scheming", "leaning", "two stacked copper coins", "muted maroon", "hunched", "bust", "a thin man with sharp eyebrows and slicked hair"),
"ace_of_the_house": ("grumpy", "pointing", "a single oversized playing card", "navy and gray", "broad shoulders", "waist-up", "a serious young man with short red hair"),
"vip_table": ("smug", "turning away", "a velvet rope on brass posts", "wine red", "wide cloak", "waist-up", "a woman with long white hair and a fur collar"),
"discard_special": ("bored", "slumped", "a crumpled paper ball", "faded orange", "slumped", "waist-up", "a freckled boy with a floppy hat"),
"the_apprentice": ("worried", "holding up an item", "a wobbling tray of mugs", "light brown", "small and wiry", "waist-up", "a young teen with a shaved head and big ears"),
"jack_of_all_trades": ("mischievous", "crouching", "a bag of mismatched tools", "patched green", "big instrument", "waist-up", "a wiry man with a patchy beard and a patched cap"),
"queens_gambit": ("scheming", "arms crossed", "a small wooden chess piece", "dusty purple", "tall hat", "waist-up", "a woman with a tall braided crown of black hair"),
"spare_change": ("sly grin", "holding up an item", "a few loose coins", "mossy green", "short and round", "bust", "a short man with a button nose and a green cap"),
"fair_share": ("stern", "pointing", "a balance scale", "plain gray", "broad shoulders", "waist-up", "a broad woman with a gray bun and strong arms"),
"efficient_service": ("grieving", "slumped", "a clipboard with a pencil", "pale tan", "hunched", "waist-up", "a tired looking man with dark circles and thin hair"),
"perfect_ten": ("startled", "mid laugh", "ten tiny wooden pegs", "pale gold", "tiny", "bust", "an excited child with wild curly hair"),
"rainy_day_fund": ("worried", "hiding behind a prop", "an old black umbrella", "rain blue", "wide cloak", "waist-up", "a woman with short silver hair and a raincoat"),
"regulars_chair": ("sleepy", "slumped", "a comfy wooden chair", "worn brown", "slumped", "waist-up", "an elderly man with white sideburns and a knitted cardigan"),
"cobweb_shelf": ("grieving", "turning away", "a dusty old bottle of syrup", "dusty gray", "hunched", "waist-up", "a pale thin woman with long gray hair"),
"estate_sale": ("sly grin", "pointing", "a price tag on a string", "faded yellow", "broad shoulders", "waist-up", "a gray haired man with round glasses and a bow tie"),
"pair_bonds": ("shy", "leaning", "two linked paper chains", "soft pink", "long scarf", "waist-up", "a young man with curly dark hair and a red scarf"),
"flush_fan": ("delighted", "holding up an item", "a hand held paper fan", "muted teal", "big instrument", "waist-up", "a woman with a long black ponytail and a teal robe"),
"suit_sampler": ("mischievous", "crouching", "four small coloured tasting spoons", "stripe gray", "short and round", "waist-up", "a plump man with ginger side whiskers"),
"warm_hearth": ("sleepy", "leaning", "a small iron poker", "warm clay", "wide cloak", "waist-up", "a heavy set woman with soft brown hair and a shawl"),
"color_matcher": ("deadpan", "standing tall", "two paint brushes, one red and one black", "red and black", "tall and thin", "waist-up", "a tall person with a square jaw and short hair"),
"twin_spoons": ("laughing", "mid laugh", "two wooden spoons", "pale green", "small and wiry", "waist-up", "a woman with curly blonde hair and flour on her cheek"),
"triple_treat": ("delighted", "holding up an item", "three small cakes on a plate", "pastel pink", "short and round", "waist-up", "a short baker with a pink cap and rosy cheeks"),
"kitchen_duo": ("laughing", "mid laugh", "a big black soup pot", "plain white", "broad shoulders", "waist-up", "a big cook with a gold tooth and a white hat"),
"pair_parade": ("proud", "standing tall", "a pair of small brass trumpets", "faded red", "big instrument", "waist-up", "a marching boy with a stiff straight back and a feathered hat"),
"stair_climber": ("fierce", "leaning", "a short wooden step stool", "dull blue", "broad shoulders", "waist-up", "a sweaty man with a headband and strong legs"),
"long_road": ("bored", "turning away", "a walking stick and a small satchel", "dusty tan", "hunched", "waist-up", "a weary traveller with a straw hat and sun-browned skin"),
"ladder_builder": ("grumpy", "crouching", "a small wooden ladder", "work brown", "heavy armour", "waist-up", "a stern carpenter with a big black moustache"),
"bargain_hunter": ("suspicious", "hiding behind a prop", "a magnifying glass", "muted mustard", "wide cloak", "waist-up", "a woman with a big bag and sharp narrow eyes"),
"quick_service": ("startled", "mid laugh", "a bell on a string", "bright white", "small and wiry", "waist-up", "a speedy boy with spiky hair and flushed cheeks"),
"lucky_penny_jar": ("sly grin", "leaning", "a jar with a single shiny penny", "copper brown", "short and round", "waist-up", "a short woman with dark curls and a copper necklace"),
"rising_dough": ("delighted", "standing tall", "a puffy loaf of dough", "flour white", "short and round", "waist-up", "a round baker with flour on his nose and arms"),
"stack_of_plates": ("worried", "holding up an item", "a wobbly tall stack of plates", "plain blue", "tall and thin", "waist-up", "a thin waiter with wide eyes and a tray"),
# ---- Uncommon: a bit more distinctive, one coloured accent
"curtain_call": ("proud", "standing tall", "a small red stage curtain", "dark gray with a red sash", "wide cloak", "waist-up", "a stage performer with a waxed moustache"),
"the_bard": ("laughing", "mid laugh", "a small wooden lute", "brown with a blue sash", "big instrument", "waist-up", "a young bard with curly red hair and a feathered hat"),
"all_hands_in": ("fierce", "pointing", "four raised fists", "gray with a green scarf", "broad shoulders", "waist-up", "a strong woman with a short dark crop and big arms"),
"big_portions": ("delighted", "holding up an item", "an enormous plate of stew", "tan with an orange apron", "short and round", "waist-up", "a giant cheerful cook with a huge round belly"),
"repeat_customer": ("smug", "leaning", "a stamped loyalty card", "gray with a purple vest", "tall hat", "waist-up", "a gentleman with white gloves and a silver monocle"),
"penny_pincher": ("suspicious", "hiding behind a prop", "a tiny leather coin purse", "brown with a yellow scarf", "hunched", "waist-up", "a thin old man with a pointed nose and tiny spectacles"),
"big_spender": ("sly grin", "standing tall", "a heavy sack of gold coins", "dark with a gold vest", "broad shoulders", "waist-up", "a wide man with a fancy curly wig and rings"),
"boss_bane": ("fierce", "pointing", "a small wooden practice shield", "gray with a red cape", "heavy armour", "waist-up", "a bold young knight with a scarred chin"),
"tasting_menu": ("shy", "holding up an item", "a small silver tasting spoon", "cream with a green apron", "tall hat", "waist-up", "a quiet chef with a tall white hat and kind eyes"),
"steady_hand": ("stern", "standing tall", "a steady candle on a plate", "gray with a teal sash", "tall and thin", "waist-up", "a calm old man with a long white beard"),
"meadow_bee": ("mischievous", "crouching", "a small striped beehive", "tan with a yellow striped vest", "tiny", "waist-up", "a small beekeeper with a net hat and freckles"),
"ferry_captain": ("deadpan", "arms crossed", "a wooden ship wheel", "navy with a white cap", "broad shoulders", "waist-up", "a weathered sea captain with a thick gray beard"),
"summit_guide": ("proud", "pointing", "a rope and an ice axe", "gray with an orange scarf", "long scarf", "waist-up", "a strong mountain guide with braided black hair"),
"sand_merchant": ("scheming", "leaning", "an hourglass full of golden sand", "sandy tan with a purple turban", "wide cloak", "waist-up", "a merchant with a long robe and a short curly beard"),
"marsh_gardener": ("sleepy", "crouching", "a watering can with a green plant", "olive with a pink flower hat", "wide cloak", "waist-up", "a gentle gardener with muddy boots and a big straw hat"),
"lantern_lighter": ("delighted", "holding up an item", "a long pole with a glowing lantern", "dark blue with a gold hat", "tall and thin", "waist-up", "a young lamp lighter with wavy red hair"),
"lighthouse_keeper": ("startled", "standing tall", "a small signal lamp", "gray with a white sweater", "tall hat", "waist-up", "an old keeper with thick bushy eyebrows and a woolen cap"),
"nest_egg": ("shy", "hiding behind a prop", "a golden egg in a straw nest", "brown with a yellow scarf", "small and wiry", "bust", "a small child with a round face and a cozy hat"),
"savings_club": ("grieving", "arms crossed", "a little piggy bank", "gray with a pink bow", "short and round", "waist-up", "a woman with her hair in a tight bun and a notebook"),
"extra_chair": ("worried", "leaning", "a spare wooden chair held up high", "tan with a green apron", "broad shoulders", "waist-up", "a polite host with a tidy part and kind eyebrows"),
"second_helpings": ("sly grin", "holding up an item", "a big ladle and a bowl", "brown with a red apron", "short and round", "waist-up", "a hungry big man with a gap tooth"),
"slow_cooker": ("sleepy", "slumped", "a simmering clay pot", "tan with a teal scarf", "hunched", "waist-up", "an old cook asleep on his feet with a nightcap"),
# ---- Rare: confident pose, rich colour, a notable prop
"early_bird": ("fierce", "standing tall", "a golden rooster feather on a staff", "rich teal and gold", "tall hat", "three-quarter", "an energetic woman with bright red hair and a feathered cap"),
"night_owl": ("suspicious", "turning away", "a perched brown owl on a lantern", "deep indigo and silver", "wide cloak", "three-quarter", "a pale tall man with round glasses and long dark hair"),
"full_suit_feast": ("laughing", "mid laugh", "a feast tray with four suit-shaped pies", "royal red and gold", "broad shoulders", "three-quarter", "a jolly feast master with a huge golden beard"),
"foursome_table": ("smug", "arms crossed", "four carved wooden chairs", "emerald and gold", "heavy armour", "three-quarter", "a proud man with a square jaw and a gold crown tattoo"),
"royal_road": ("proud", "pointing", "a rolled scroll map with a crown", "royal purple and gold", "long scarf", "three-quarter", "a royal courier with a braided black beard and a purple cape"),
"bread_starter": ("delighted", "holding up an item", "a bubbling jar of sourdough starter", "warm gold and brown", "short and round", "three-quarter", "a warm baker with silver hair and a bright orange apron"),
"overtime": ("fierce", "leaning", "a glowing hourglass and a clock", "deep orange and black", "tall and thin", "three-quarter", "a restless keeper with spiky white hair and bright eyes"),
# ---- Epic: dramatic pose, rim light, imposing silhouette
"house_special": ("proud", "standing tall", "a huge steaming silver cloche", "crimson and gold", "wide cloak", "low angle", "a towering head chef with a pointed black moustache and a tall hat"),
"full_house_crowd": ("laughing", "mid laugh", "a golden banner raised over a cheering crowd", "royal blue and silver", "broad shoulders", "low angle", "a booming host with a long red cape and a silver belt"),
"house_tab": ("scheming", "leaning", "an endless glowing ledger scroll", "midnight purple and gold", "long scarf", "low angle", "a tall accountant with white hair and a dramatic dark coat"),
"veterans_table": ("stern", "arms crossed", "a battered iron helmet on a table", "iron gray and bronze", "heavy armour", "low angle", "a scarred old veteran with a bald head and a braided gray beard"),
# ---- Legendary: commanding hero pose, glowing prop, strongest light, biggest silhouette
"house_favorite": ("fierce", "standing tall with one arm raised", "a glowing golden crown held high", "radiant gold and white", "wide cloak", "full body low angle", "a majestic king with a flowing white cape and a short golden beard"),
}

ladder = {
    "common": "Common tier: an ordinary tavern folk in a relaxed pose with muted colours and a plain prop, soft even light, small and ordinary silhouette",
    "uncommon": "Uncommon tier: a bit more distinctive, one bright coloured accent, soft light, plain background",
    "rare": "Rare tier: a confident pose in rich saturated colours with a notable prop, a touch of rim light",
    "epic": "Epic tier: a dramatic pose with strong rim light, an imposing silhouette that fills more of the card",
    "legendary": "Legendary tier: a commanding hero pose with a glowing prop, the strongest light and golden rays behind, the biggest silhouette of all",
}
rar = d["ctp_rarity"]
missing = [i for i in rar if i not in V]
extra = [i for i in V if i not in rar]
assert not missing and not extra, (missing, extra)
out = {}
for pid, (ex, po, pr, co, si, fr, who) in V.items():
    out[pid] = {"name": names[pid], "rarity": rar[pid], "expression": ex, "pose": po, "prop": pr,
                "outfit_colour": co, "silhouette": si, "framing": fr, "who": who}
(HERE / "patron_variety.json").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

d["ctp_ladder"] = ladder
d["ctp_style"] = ("Edit the reference image, which is a finished trading card. Keep EXACTLY the same card: same frame, same gem, same wooden name plate, same proportions, "
    "same hand-painted blocky Roblox tavern style, palette and lighting, on a plain light gray background. Change ONLY the character inside the frame and the name on the wooden plate. "
    "The new character is a blocky Roblox avatar with chunky proportions and hand-painted textures: a cylinder head, a blocky body, no LEGO look, no studs on the head. "
    "The face is a simple blocky face showing the expression given in the subject, not a default smile. "
    "Follow the subject's expression, pose, prop, outfit colour, silhouette and framing exactly. Not dark, no skulls, no hooded figures, no weapons. "
    "The only text on the whole card is the name on the wooden plate, spelled exactly as given, no other letters or numbers anywhere. Kid-friendly original art")
subs = {}
for pid, e in out.items():
    r = e["rarity"]
    subs["ctp_" + pid] = ("the same %s card, same frame and gem, with the character replaced by %s. " % (r, e["who"])
        + "Expression: %s. Pose: %s. Prop: %s. Outfit colour: %s. " % (e["expression"], e["pose"], e["prop"], e["outfit_colour"])
        + "Silhouette: %s. Camera framing: %s. %s. " % (e["silhouette"], e["framing"], ladder[r])
        + 'The wooden name plate at the bottom reads exactly "%s" and nothing else is written anywhere' % e["name"])
d["ctp_subjects"] = subs
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(subs))
