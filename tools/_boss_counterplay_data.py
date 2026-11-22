"""One-off: adds `rules` tags to every Boss Round and `counters` tags to Patrons, Recipes and House Passes.
Data lives in the registries themselves as small tables next to their definitions (like PATRON_TAGS)."""

BOSS_TAGS = {
    "bouncer": ["lowHandSize"], "short_notice": ["fewerDiscards"], "house_rules": ["targetBoost"], "the_tab": ["tipsDrain"],
    "thin_soup": ["weakenChips"], "slow_simmer": ["weakenMult"], "rowdy_crowd": ["cardToss"], "no_repeats": ["noRepeat"],
    "hearts_are_out": ["suitDebuff"], "spades_are_out": ["suitDebuff"], "no_vips": ["faceDebuff"], "empty_pockets": ["tipsDrain"],
    "full_table": ["cardCount"], "last_chance": ["fewerDiscards"], "short_staffed": ["lowHandSize", "fewerDiscards"],
    "diamonds_are_out": ["suitDebuff"], "clubs_are_out": ["suitDebuff"], "steep_tab": ["tipsDrain"], "thin_chips": ["weakenChips"],
    "flat_mult": ["weakenMult"], "double_tab": ["tipsDrain", "targetBoost"], "lights_out": ["fewerHands"], "quick_service": ["fewerHands"],
    "stale_bread": ["weakenChips", "weakenMult"], "one_at_a_time": ["cardCount"], "big_tab": ["targetBoost"], "wild_crowd": ["cardToss"],
    "empty_handed": ["fewerDiscards", "fewerHands"], "everythings_out": ["weakenChips", "weakenMult"], "four_top": ["cardCount"],
    "slow_night": ["cardToss"], "house_minimum": ["targetBoost"], "picked_over": ["suitDebuff", "lowHandSize"], "rushed_order": ["fewerHands"],
    "bare_bones": ["weakenChips", "weakenMult"], "sleepy_cook": ["slowStart"], "cold_start": ["tipsDrain"], "pair_patrol": ["handBan"],
    "heavy_hands": ["cardCount"], "quiet_corner": ["oddRank"], "picky_eater": ["handBan"], "crowded_counter": ["patronLimit"], "penny_wise": ["tipsDrain"],
}

PATRON_COUNTERS = {
    "overtime": ["fewerHands", "slowStart", "cardToss"], "foursome_table": ["fewerHands", "targetBoost"], "curtain_call": ["fewerHands", "slowStart"],
    "extra_chair": ["lowHandSize", "cardToss"], "second_helpings": ["lowHandSize", "fewerDiscards"],
    "suit_sampler": ["suitDebuff"], "color_matcher": ["suitDebuff"], "marsh_gardener": ["suitDebuff"],
    "meadow_bee": ["faceDebuff"], "perfect_ten": ["faceDebuff", "oddRank"], "ace_of_the_house": ["faceDebuff"],
    "full_suit_feast": ["targetBoost"], "royal_road": ["targetBoost"], "house_special": ["targetBoost"],
    "the_regular": ["weakenChips", "patronLimit"], "regulars_round": ["weakenChips", "handBan", "patronLimit"], "threes_company": ["weakenChips"],
    "lucky_dice": ["weakenMult", "handBan"], "big_portions": ["weakenMult", "handBan"], "fair_share": ["weakenMult"], "flush_fan": ["weakenMult"], "kitchen_duo": ["weakenMult"],
    "tip_jar": ["tipsDrain"], "savings_club": ["tipsDrain"], "tab_regulars": ["tipsDrain"], "quick_service": ["tipsDrain"],
    "lantern_lighter": ["cardToss"], "steady_hand": ["cardCount"], "ferry_captain": ["cardCount"], "small_plate": ["cardCount"], "ladder_builder": ["cardCount"],
    "tasting_menu": ["noRepeat"], "pair_parade": ["handBan"], "twin_spoons": ["handBan"],
    "second_opinion": ["patronLimit"], "the_understudy": ["patronLimit"], "early_bird": ["slowStart"],
}
RECIPE_COUNTERS = {
    "compd_discard": ["fewerDiscards", "slowStart", "lowHandSize"], "well_stocked": ["lowHandSize", "cardToss"], "fresh_delivery": ["cardToss", "lowHandSize"],
    "suit_swap": ["suitDebuff"], "house_blend_order": ["suitDebuff"], "suit_flip": ["suitDebuff"],
    "upsell": ["faceDebuff", "oddRank"], "downsize": ["oddRank"], "wildcard_swap": ["oddRank", "noRepeat"],
    "whole_menu_upgrade": ["targetBoost", "noRepeat"], "gold_standard": ["targetBoost"],
    "tip_doubler": ["tipsDrain"], "tabs_on_the_house": ["tipsDrain"],
    "fresh_menu": ["noRepeat"], "twin_card": ["cardToss"],
}
HOUSEPASS_COUNTERS = {
    "double_shift": ["fewerHands", "slowStart"], "card_cart": ["lowHandSize", "cardToss"], "late_kitchen": ["fewerDiscards", "lowHandSize"],
    "boss_prep": ["fewerDiscards"], "warm_welcome": ["targetBoost"], "tip_stand": ["tipsDrain"], "savings_account": ["tipsDrain"],
}


def lua_table(name, data, indent="\t"):
    lines = [f"local {name} = {{"]
    items = sorted(data.items())
    row = []
    for key, tags in items:
        row.append(f"{key} = {{ " + ", ".join(f'"{t}"' for t in tags) + " }")
        if len(row) == 3:
            lines.append(indent + ", ".join(row) + ",")
            row = []
    if row:
        lines.append(indent + ", ".join(row) + ",")
    lines.append("}")
    return "\n".join(lines)


def patch(path, anchor, block, after=False):
    s = open(path, encoding="utf-8").read()
    assert anchor in s, (path, anchor)
    if "Boss counterplay" in s and block.split("\n")[0] in s:
        print("already patched", path)
        return
    s = s.replace(anchor, (anchor + "\n" + block) if after else (block + "\n" + anchor), 1)
    open(path, "w", encoding="utf-8").write(s)
    print("patched", path)


# BossRounds: rules tags
boss_block = (
    "-- BOSS COUNTERPLAY (Engine/BossCounters.lua): 1 to 2 `rules` tags per Boss Round. EDIT ME. Items that help against a tag\n"
    "-- carry the same tag in their `counters` list (Patrons, Recipes and House Passes), so the Counter can show a shield.\n"
    + lua_table("BOSS_RULE_TAGS", BOSS_TAGS) + "\n"
    "BossRounds.RuleTagIds = { \"fewerHands\", \"fewerDiscards\", \"lowHandSize\", \"cardToss\", \"cardCount\", \"suitDebuff\", \"faceDebuff\", \"oddRank\", \"noRepeat\",\n"
    "\t\"handBan\", \"targetBoost\", \"weakenChips\", \"weakenMult\", \"tipsDrain\", \"patronLimit\", \"slowStart\" }\n"
    "for _, boss in ipairs(BossRounds.Definitions) do\n\tboss.rules = BOSS_RULE_TAGS[boss.id]\nend\n"
)
s = open("src/Shared/Engine/BossRounds.lua", encoding="utf-8").read()
if "BOSS_RULE_TAGS" not in s:
    marker = "function BossRounds.getById"
    assert marker in s
    s = s.replace(marker, boss_block + "\n" + marker, 1)
    open("src/Shared/Engine/BossRounds.lua", "w", encoding="utf-8").write(s)
    print("patched BossRounds")

# Patrons
s = open("src/Shared/Engine/Patrons.lua", encoding="utf-8").read()
if "PATRON_COUNTERS" not in s:
    marker = "Patrons.TagIds = "
    assert marker in s
    block = ("-- BOSS COUNTERPLAY: which boss rule tags this Patron truly helps against (Engine/BossCounters.lua). EDIT ME.\n"
             + lua_table("PATRON_COUNTERS", PATRON_COUNTERS) + "\n"
             "for _, patron in ipairs(Patrons.Definitions) do\n\tpatron.counters = PATRON_COUNTERS[patron.id]\nend\n")
    s = s.replace(marker, block + marker, 1)
    open("src/Shared/Engine/Patrons.lua", "w", encoding="utf-8").write(s)
    print("patched Patrons")

# Recipes (all three catalogs, after the second batch)
s = open("src/Shared/Engine/Recipes.lua", encoding="utf-8").read()
if "RECIPE_COUNTERS" not in s:
    marker = "function Recipes.getHouseRecipeById(id)"
    assert marker in s
    block = ("-- BOSS COUNTERPLAY: which boss rule tags a Recipe truly helps against (Engine/BossCounters.lua). EDIT ME.\n"
             + lua_table("RECIPE_COUNTERS", RECIPE_COUNTERS) + "\n"
             "for _, catalog in ipairs({ Recipes.HouseRecipes, Recipes.MenuRecipes, Recipes.SecretRecipes }) do\n"
             "\tfor _, recipe in ipairs(catalog) do\n\t\trecipe.counters = RECIPE_COUNTERS[recipe.id]\n\tend\nend\n")
    s = s.replace(marker, block + "\n" + marker, 1)
    open("src/Shared/Engine/Recipes.lua", "w", encoding="utf-8").write(s)
    print("patched Recipes")

# House Passes
s = open("src/Shared/Engine/HousePasses.lua", encoding="utf-8").read()
if "HOUSEPASS_COUNTERS" not in s:
    marker = "function HousePasses.getById"
    assert marker in s
    block = ("-- BOSS COUNTERPLAY: which boss rule tags a House Pass truly helps against (Engine/BossCounters.lua). EDIT ME.\n"
             + lua_table("HOUSEPASS_COUNTERS", HOUSEPASS_COUNTERS) + "\n"
             "for _, pass in ipairs(HousePasses.Definitions) do\n\tpass.counters = HOUSEPASS_COUNTERS[pass.id]\nend\n")
    s = s.replace(marker, block + "\n" + marker, 1)
    open("src/Shared/Engine/HousePasses.lua", "w", encoding="utf-8").write(s)
    print("patched HousePasses")
