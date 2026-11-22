--[[
	Shared/Engine/BossOutfits.lua
	Pure data (no Roblox calls, so it is unit-tested): how each boss's live 3D rig is dressed so
	its silhouette and colors match the painted portrait (see boss_subjects in
	tools/patron_art/prompts.json). Client/BossRigs.lua turns these into parts.

	Colors are { r, g, b } triples. Every field is optional and falls back to Default.
	  skin, shirt, pants, hatColor, propColor, accent   color triples
	  hat    one of BossOutfits.Hats
	  prop   one of BossOutfits.Props
	  cape   bool (a dark cloak behind the body)
	  scale  body scale (the stage refits the height anyway, so keep near 1)

	To add a boss: add an entry keyed by its BossRounds id. A boss with no entry uses Default.
	The Night 8 boss (the Keeper, `opts.grand` in BossRigs.build) uses BossOutfits.Keeper.
]]

local BossOutfits = {}

BossOutfits.Hats = { "none", "tall", "cap", "crown", "chef", "party" }
BossOutfits.Props = {
	"none", "ladle", "ledger", "scroll", "pocketwatch", "receipt", "paddle", "broom", "sign",
	"coins", "tray", "lantern", "rollingpin", "loaf", "stick", "cards",
}

BossOutfits.Default = {
	skin = { 178, 152, 134 },
	shirt = { 46, 32, 38 },
	pants = { 28, 24, 30 },
	hat = "tall",
	hatColor = { 26, 22, 26 },
	prop = "ledger",
	propColor = { 86, 58, 40 },
	cape = true,
	scale = 1,
}

-- The Keeper: the Night 8 boss. Midnight robe, gold crown and a gold staff.
BossOutfits.Keeper = {
	shirt = { 34, 20, 52 },
	pants = { 20, 14, 30 },
	hat = "crown",
	prop = "stick",
	propColor = { 232, 184, 74 },
	cape = true,
	scale = 1,
}

local WHITE = { 232, 230, 222 }
local GRAY_CLOAK = { 96, 98, 106 }
local GOLD = { 232, 184, 74 }
local WOOD = { 120, 84, 52 }
local PAPER = { 236, 224, 190 }

BossOutfits.Bosses = {
	-- Night 1 (tier 1)
	bouncer = { shirt = { 24, 24, 32 }, hat = "none", prop = "sign", propColor = { 190, 50, 44 }, accent = { 205, 52, 46 }, cape = false },
	short_notice = { shirt = { 120, 84, 60 }, pants = { 50, 40, 34 }, hat = "none", prop = "pocketwatch", propColor = GOLD, accent = { 232, 150, 42 }, cape = false },
	house_rules = { shirt = { 40, 34, 70 }, hat = "tall", hatColor = { 30, 26, 48 }, prop = "scroll", propColor = PAPER, accent = GOLD },
	the_tab = { shirt = { 80, 86, 70 }, hat = "cap", hatColor = { 56, 86, 58 }, prop = "receipt", propColor = PAPER, accent = { 44, 168, 164 }, cape = false },
	thin_soup = { shirt = { 70, 74, 82 }, hat = "chef", hatColor = WHITE, prop = "ladle", propColor = { 150, 150, 156 }, accent = { 232, 140, 50 }, cape = false },
	slow_simmer = { shirt = { 78, 70, 66 }, hat = "chef", hatColor = WHITE, prop = "ladle", propColor = WOOD, accent = { 232, 150, 42 }, cape = false },
	slow_night = { shirt = { 60, 50, 90 }, pants = { 40, 34, 66 }, hat = "cap", hatColor = { 90, 76, 140 }, prop = "lantern", propColor = { 255, 200, 110 }, accent = { 150, 84, 210 }, cape = false },
	sleepy_cook = { shirt = { 150, 160, 190 }, hat = "chef", hatColor = WHITE, prop = "ladle", propColor = WOOD, accent = { 120, 130, 210 }, cape = false },
	cold_start = { shirt = { 80, 120, 170 }, hat = "cap", hatColor = { 60, 90, 140 }, prop = "lantern", propColor = { 160, 210, 255 }, accent = { 120, 190, 240 }, cape = false },
	-- Night 3 and up (tier 2)
	rowdy_crowd = { shirt = { 180, 70, 60 }, hat = "party", hatColor = { 90, 160, 220 }, prop = "cards", propColor = WHITE, accent = { 210, 72, 146 }, cape = false },
	no_repeats = { shirt = { 24, 22, 28 }, hat = "none", prop = "paddle", propColor = WOOD, accent = { 205, 52, 46 } },
	hearts_are_out = { shirt = GRAY_CLOAK, hat = "cap", hatColor = { 74, 76, 84 }, prop = "broom", propColor = WOOD, accent = { 215, 50, 60 } },
	spades_are_out = { shirt = GRAY_CLOAK, hat = "cap", hatColor = { 74, 76, 84 }, prop = "broom", propColor = WOOD, accent = { 110, 110, 160 } },
	diamonds_are_out = { shirt = GRAY_CLOAK, hat = "cap", hatColor = { 74, 76, 84 }, prop = "broom", propColor = WOOD, accent = { 236, 140, 40 } },
	clubs_are_out = { shirt = GRAY_CLOAK, hat = "cap", hatColor = { 74, 76, 84 }, prop = "broom", propColor = WOOD, accent = { 70, 170, 76 } },
	no_vips = { shirt = { 70, 28, 36 }, hat = "cap", hatColor = { 40, 22, 26 }, prop = "sign", propColor = GOLD, accent = GOLD, cape = false },
	empty_pockets = { shirt = { 96, 80, 60 }, hat = "cap", hatColor = { 70, 56, 42 }, prop = "coins", propColor = GOLD, accent = { 232, 150, 42 }, cape = false },
	full_table = { shirt = { 226, 222, 210 }, pants = { 28, 28, 34 }, hat = "none", prop = "tray", propColor = { 200, 190, 170 }, accent = { 44, 168, 164 }, cape = false },
	last_chance = { shirt = { 40, 46, 70 }, hat = "none", prop = "lantern", propColor = { 255, 200, 110 }, accent = { 232, 150, 42 } },
	pair_patrol = { shirt = { 40, 70, 120 }, hat = "cap", hatColor = { 30, 50, 90 }, prop = "sign", propColor = GOLD, accent = GOLD, cape = false },
	heavy_hands = { shirt = { 120, 70, 50 }, hat = "none", prop = "rollingpin", propColor = WOOD, accent = { 210, 120, 60 }, cape = false },
	quiet_corner = { shirt = { 90, 80, 110 }, hat = "tall", hatColor = { 70, 60, 96 }, prop = "scroll", propColor = WHITE, accent = { 170, 150, 220 } },
	short_staffed = { shirt = { 150, 140, 126 }, hat = "none", prop = "tray", propColor = { 190, 170, 140 }, accent = { 210, 72, 146 }, cape = false },
	steep_tab = { shirt = { 70, 80, 100 }, hat = "cap", hatColor = { 46, 56, 76 }, prop = "receipt", propColor = PAPER, accent = { 44, 168, 164 }, cape = false },
	thin_chips = { shirt = { 232, 224, 204 }, pants = { 90, 74, 60 }, hat = "chef", hatColor = WHITE, prop = "tray", propColor = { 214, 190, 140 }, accent = { 232, 150, 42 }, cape = false },
	flat_mult = { shirt = { 200, 190, 170 }, pants = { 90, 74, 60 }, hat = "chef", hatColor = WHITE, prop = "rollingpin", propColor = WOOD, accent = { 232, 150, 42 }, cape = false },
	double_tab = { shirt = { 110, 70, 60 }, hat = "cap", hatColor = { 70, 44, 38 }, prop = "receipt", propColor = PAPER, accent = { 205, 52, 46 }, cape = false },
	-- Tier 3
	lights_out = { shirt = { 24, 24, 40 }, hat = "none", prop = "lantern", propColor = { 255, 190, 90 }, accent = { 255, 200, 90 } },
	quick_service = { shirt = { 190, 60, 70 }, pants = { 40, 40, 50 }, hat = "cap", hatColor = { 150, 36, 46 }, prop = "tray", propColor = { 200, 190, 170 }, accent = { 205, 52, 46 }, cape = false },
	stale_bread = { shirt = { 150, 110, 70 }, hat = "chef", hatColor = WHITE, prop = "loaf", propColor = { 150, 104, 60 }, accent = { 232, 150, 42 }, cape = false },
	one_at_a_time = { shirt = { 70, 76, 84 }, hat = "cap", hatColor = { 90, 92, 100 }, prop = "paddle", propColor = WOOD, accent = { 140, 140, 150 }, cape = false },
	big_tab = { shirt = { 90, 74, 60 }, hat = "cap", hatColor = { 60, 46, 36 }, prop = "receipt", propColor = PAPER, accent = { 44, 168, 164 }, cape = false },
	wild_crowd = { shirt = { 200, 80, 170 }, hat = "party", hatColor = { 240, 200, 60 }, prop = "cards", propColor = WHITE, accent = { 210, 72, 146 }, cape = false },
	empty_handed = { shirt = { 110, 100, 90 }, hat = "none", prop = "none", accent = { 190, 170, 130 }, cape = false },
	everythings_out = { shirt = { 90, 80, 70 }, hat = "cap", hatColor = { 66, 58, 50 }, prop = "none", accent = { 160, 150, 130 }, cape = false },
	four_top = { shirt = { 30, 60, 50 }, hat = "none", prop = "tray", propColor = { 200, 190, 170 }, accent = { 86, 176, 72 }, cape = false },
	house_minimum = { shirt = { 40, 34, 70 }, hat = "tall", hatColor = { 30, 26, 48 }, prop = "stick", propColor = WOOD, accent = GOLD },
	picked_over = { shirt = { 90, 60, 60 }, hat = "none", prop = "tray", propColor = { 190, 170, 140 }, accent = { 205, 52, 46 }, cape = false },
	rushed_order = { shirt = { 190, 90, 60 }, pants = { 50, 40, 36 }, hat = "chef", hatColor = WHITE, prop = "receipt", propColor = PAPER, accent = { 205, 52, 46 }, cape = false },
	picky_eater = { shirt = { 200, 190, 170 }, hat = "chef", hatColor = WHITE, prop = "tray", propColor = { 200, 190, 170 }, accent = { 90, 160, 90 }, cape = false },
	crowded_counter = { shirt = { 110, 80, 60 }, hat = "cap", hatColor = { 90, 64, 46 }, prop = "ledger", propColor = { 150, 110, 70 }, accent = { 232, 150, 42 }, cape = false },
	frozen_hand = { shirt = { 120, 170, 205 }, hat = "cap", hatColor = { 90, 140, 180 }, prop = "lantern", propColor = WHITE, accent = { 190, 225, 250 } },
	quiet_tavern = { shirt = { 96, 84, 120 }, hat = "tall", hatColor = { 64, 54, 90 }, prop = "scroll", propColor = WHITE, accent = { 160, 140, 210 } },
	short_table = { shirt = { 130, 92, 56 }, hat = "chef", hatColor = WHITE, prop = "tray", propColor = GOLD, accent = { 210, 160, 90 } },
	penny_wise = { shirt = { 70, 90, 60 }, hat = "cap", hatColor = { 50, 70, 46 }, prop = "coins", propColor = GOLD, accent = GOLD, cape = false },
	bare_bones = { shirt = { 226, 224, 216 }, pants = { 226, 224, 216 }, hat = "cap", hatColor = { 226, 224, 216 }, prop = "none", accent = { 190, 186, 170 }, cape = false },
}

-- Merged outfit for a boss: Default < Bosses[id] (or Keeper when grand).
function BossOutfits.resolve(bossId, grand)
	local out = {}
	for k, v in pairs(BossOutfits.Default) do out[k] = v end
	local extra = grand and BossOutfits.Keeper or BossOutfits.Bosses[bossId]
	for k, v in pairs(extra or {}) do out[k] = v end
	return out
end

return BossOutfits
