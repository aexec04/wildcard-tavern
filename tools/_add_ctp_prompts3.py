"""One-off: add Concept T Patron portrait prompts for batches 4 and 5 (the 55 Common and Uncommon Patrons without a ctp_ key)."""
import json, pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

RAR = {  # id -> (rarity, name, character)
    "ace_of_the_house": ("common", "Ace of the House", "a proud young innkeeper with slicked black hair and tan skin in a red waistcoat, holding up a giant golden ace card"),
    "all_matching": ("common", "All Matching", "a tidy woman with a neat grey bob and light skin, dressed head to toe in matching teal, standing beside a row of five identical teal teacups"),
    "cobweb_shelf": ("common", "Cobweb Shelf", "a gentle old shopkeeper with wispy white hair and brown skin in a grey apron, dusting a shelf of jars with a feather duster, a friendly little spider hanging beside"),
    "color_matcher": ("common", "Color Matcher", "a cheerful painter with a pink beanie and freckles and light skin in a paint splattered smock, holding a red paint pot in one hand and a black one in the other"),
    "discard_special": ("common", "Discard Special", "a laughing waiter with curly brown hair and olive skin in a white shirt and bow tie, tossing a card over his shoulder toward a bin"),
    "double_down": ("common", "Double Down", "a bold twin brother pair standing back to back, both with red spiky hair and light skin in matching yellow jackets, each flashing a thumbs up"),
    "efficient_service": ("common", "Efficient Service", "a speedy young server with a ponytail and dark skin in a mint green uniform, balancing three plates on one arm and a stopwatch in the other hand"),
    "estate_sale": ("common", "Estate Sale", "a cheery auctioneer with a handlebar moustache and pale skin in a checkered coat, holding up a little wooden gavel beside a stack of old boxes"),
    "fair_share": ("common", "Fair Share", "a kind baker with a round face and warm brown skin in a lilac apron, cutting a big pie into equal slices"),
    "flush_fan": ("common", "Flush Fan", "an excited fan with a face painted with little hearts and light skin in a team scarf, waving a foam finger with five cards fanned in the other hand"),
    "jack_of_all_trades": ("common", "Jack of All Trades", "a handy young man with messy blond hair and tan skin in a tool belt vest, holding a hammer, a paintbrush and a ladle all at once"),
    "kitchen_duo": ("common", "Kitchen Duo", "two smiling cooks side by side, one tall with a black topknot and one short with green braids, both in white aprons holding a pan and a pot"),
    "ladder_builder": ("common", "Ladder Builder", "a sturdy carpenter with a bushy orange beard and pale skin in overalls and a yellow hard hat, carrying a wooden ladder on one shoulder"),
    "long_road": ("common", "Long Road", "a happy traveller with a wide straw hat and dark skin in a patched green cloak, holding a walking stick, a winding sunny road behind"),
    "lucky_penny_jar": ("common", "Lucky Penny Jar", "a delighted girl with two pigtails and freckles and light skin in a yellow dress, hugging a big glass jar full of shiny copper pennies"),
    "pair_bonds": ("common", "Pair Bonds", "two best friends side by side, one with curly black hair and one with a blue beanie, both with brown skin tones, linking pinky fingers and grinning"),
    "pair_parade": ("common", "Pair Parade", "a bandleader with a tall feathered hat and tan skin in a red marching coat, leading a tiny parade of paired ducklings, waving a baton"),
    "perfect_ten": ("common", "Perfect Ten", "a smiling judge with silver curls and dark skin in a purple blazer, holding up a big scorecard with ten stars and a thumbs up"),
    "quick_service": ("common", "Quick Service", "a dashing young courier with short green hair and light skin in an orange vest, sliding a steaming dish along a counter in a blur of speed lines"),
    "rainy_day_fund": ("common", "Rainy Day Fund", "a careful saver with a yellow raincoat and a blue umbrella and olive skin, smiling while dropping a coin into a little piggy bank"),
    "regulars_chair": ("common", "Regular's Chair", "a relaxed old man with a grey ponytail and tan skin in a cosy brown cardigan, sitting in a big comfy armchair with a mug of cocoa"),
    "regulars_round": ("common", "Regulars' Round", "a jolly host with a bald head and a ginger beard and pale skin in a green vest, carrying a tray of mugs of cocoa to a table"),
    "rising_dough": ("common", "Rising Dough", "a floury young baker with a tall white hat and dark brown skin, proudly watching a huge round loaf of dough rise from a bowl"),
    "rowdy_bunch": ("common", "Rowdy Bunch", "a loud cheerful trio of friends crowded together, one with a mohawk, one with a bandana, one with big glasses, all laughing with raised fists, three little clover symbols floating"),
    "second_opinion": ("common", "Second Opinion", "a thoughtful adviser with round spectacles and a short afro and brown skin in a mustard sweater, holding up a small mirror that shows a second smiling face"),
    "sharp_dressed": ("common", "Sharp Dressed", "a dapper gentleman with slicked silver hair and light skin in a crisp black suit with a bright red bow tie, adjusting his cuffs with a wink"),
    "small_plate": ("common", "Small Plate", "a tiny cheerful chef with a huge white hat and tan skin in a spotless apron, carefully presenting one very small plate with a single cherry"),
    "spare_change": ("common", "Spare Change", "a friendly busker with a bandana and a scruffy goatee and olive skin in a patched coat, holding out a hat with a few shiny coins"),
    "sparkling_service": ("common", "Sparkling Service", "a glittering waitress with short pink hair and dark skin in a silver vest, polishing a sparkling glass until it shines, tiny stars around"),
    "stack_of_plates": ("common", "Stack of Plates", "a determined dishwasher with a messy red bun and freckles and light skin in a blue apron, balancing a tall wobbling stack of plates"),
    "stair_climber": ("common", "Stair Climber", "an energetic hiker with a backpack and a red headband and tan skin, bounding up a short flight of stone steps with a big grin"),
    "suit_sampler": ("common", "Suit Sampler", "a curious tailor with a measuring tape around the neck and curly grey hair and brown skin, holding four small cloth swatches in four different colors"),
    "suit_yourself": ("common", "Suit Yourself", "a relaxed stylish woman with a long black braid and warm tan skin in a heart patterned scarf and a pink coat, shrugging with a smile"),
    "tab_regulars": ("common", "Tab Regulars", "a friendly tavern host with a curly moustache and light skin in a striped apron, holding up a long paper receipt scroll and a pencil behind the ear"),
    "the_understudy": ("common", "The Understudy", "a hopeful young actor with wavy brown hair and olive skin in a half finished costume, practising a bow beside a tiny theater curtain"),
    "threes_company": ("common", "Three's Company", "three cheerful friends of different heights standing shoulder to shoulder, one with a hat, one with glasses, one with a scarf, all waving"),
    "triple_treat": ("common", "Triple Treat", "a happy ice cream seller with a paper hat and dark skin in a striped shirt, holding a cone with three scoops, pink, mint and vanilla"),
    "twin_spoons": ("common", "Twin Spoons", "a playful drummer-cook with a red bandana and pale skin in a yellow shirt, tapping two big wooden spoons like drumsticks on a pot"),
    "vip_table": ("common", "VIP Table", "an important looking host with a tall top hat and a gold monocle and tan skin in a plum velvet coat, holding up a velvet rope with a proud smile"),
    "all_hands_in": ("uncommon", "All Hands In", "a team captain with a short blond cut and light skin in a green team jacket, stretching one hand into the middle, four other hands piled on top, a bright grin"),
    "big_portions": ("uncommon", "Big Portions", "a hearty cook with a round belly and a white hat and warm brown skin in a green apron, carrying a giant steaming plate of food on both arms"),
    "extra_chair": ("uncommon", "Extra Chair", "a welcoming host with long auburn hair and freckles and light skin in a leaf green dress, pulling out an extra wooden chair with a warm smile"),
    "ferry_captain": ("uncommon", "Ferry Captain", "a cheerful ferry captain with a navy cap and a white beard and tan skin in a blue coat, steering a tiny wooden boat wheel, a little boat behind"),
    "lantern_lighter": ("uncommon", "Lantern Lighter", "a gentle lamplighter with a tall pointed hat and dark skin in a dusky green coat, lifting a long pole to light a glowing paper lantern"),
    "lighthouse_keeper": ("uncommon", "Lighthouse Keeper", "a kindly lighthouse keeper with a woolly cap and a grey beard and pale skin in a yellow oilskin coat, holding a bright lantern, a small striped lighthouse behind"),
    "marsh_gardener": ("uncommon", "Marsh Gardener", "a calm gardener with a wide leaf hat and long dark braids and brown skin in green waders, holding a watering can beside tall cattails and a lily pad"),
    "meadow_bee": ("uncommon", "Meadow Bee", "a playful child with golden curls and light skin in a yellow and black striped sweater and little felt wings, holding a jar of honey, tiny flowers around"),
    "nest_egg": ("uncommon", "Nest Egg", "a cosy farmer with a straw hat and rosy cheeks and tan skin in a blue overall, cradling a big golden egg in a straw nest"),
    "repeat_customer": ("uncommon", "Repeat Customer", "a smiling regular with a big knitted hat and olive skin in a teal scarf, holding a loyalty card with many stamps and giving a friendly wave"),
    "sand_merchant": ("uncommon", "Sand Merchant", "a sunny desert trader with a loose white turban and dark skin in a sandy robe, holding up a little glass bottle of golden sand beside a smiling camel"),
    "savings_club": ("uncommon", "Savings Club", "a tidy treasurer with a bowl cut and round glasses and pale skin in a green vest, holding a small brass coin box with a key and a happy smile"),
    "second_helpings": ("uncommon", "Second Helpings", "a hungry happy guest with a big laugh and short black hair and brown skin, holding up an empty bowl with both hands and a spoon in his teeth"),
    "slow_cooker": ("uncommon", "Slow Cooker", "a patient cook with a long grey plait and warm tan skin in a floral apron, stirring a big bubbling pot slowly while steam curls into little hearts"),
    "steady_hand": ("uncommon", "Steady Hand", "a calm craftsman with a bald head and a short beard and light skin in a leather apron, carefully balancing five little cards on his open palm"),
    "summit_guide": ("uncommon", "Summit Guide", "a rugged but friendly mountain guide with a red bobble hat and a dark beard and tan skin in a thick blue parka, pointing up with an ice axe, snowy peak behind"),
}

d["ctp_rarity"].update({k: v[0] for k, v in RAR.items()})
subj = d["ctp_subjects"]
for k, (rar, name, ch) in RAR.items():
    subj["ctp_" + k] = (
        f"the same {rar} card, same frame and gem, with the character replaced by {ch}. "
        f"The wooden name plate at the bottom reads exactly \"{name}\" and nothing else is written anywhere"
    )
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(len(RAR), "added;", len(subj), "ctp subjects")
