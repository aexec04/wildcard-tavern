--[[
	Flair.lua
	Equippable cosmetic Flair in 4 slots. Visual only: it never touches scoring, targets or timing, and every effect
	respects Reduce Flashing, Reduce Motion and the Fast speed (Client/FlairFX.lua). Pure Lua, no Roblox APIs.

	Slots: scoreNumbers (color and glow of the score popup), playTrail (particles as cards are played),
	finisher (a short flourish on big hands: Flush or better, Legendary), nameAura (glow and crest beside the name).
	Each slot has a default (always owned) and 4 to 5 more options. An option's `unlock` says how it is earned:
	  { kind = "rank", n }  Tavern Rank        { kind = "stake", n }  stake n cleared      { kind = "quests", n }  daily quests done
	  { kind = "achievement", id }  an Achievements id is unlocked      { kind = "legend", n }  Legend level n
	  { kind = "store" }  for sale (granted by Engine/Store into profile.flairOwned)
	Free unlocks are computed from the profile (never saved), store ones are saved in flairOwned.

	Profile: flairOwned = { [flair id] = true } (store grants), flairEquipped = { [slot] = flair id } (defaults when absent).
]]

local Achievements = require(script.Parent.Achievements)
local Legend = require(script.Parent.Legend)

local Flair = {}

Flair.Slots = {
	{ id = "scoreNumbers", name = "Score Numbers", icon = "🔢" },
	{ id = "playTrail", name = "Play Trail", icon = "✨" },
	{ id = "finisher", name = "Finisher", icon = "🎆" },
	{ id = "nameAura", name = "Name Aura", icon = "👑" },
}

local function rank(n) return { kind = "rank", n = n, hint = "Reach Tavern Rank " .. n .. "." } end
local function stake(n) return { kind = "stake", n = n, hint = "Clear stake " .. n .. "." } end
local function quests(n) return { kind = "quests", n = n, hint = "Finish " .. n .. " daily quests." } end
local function achievement(id, hint) return { kind = "achievement", id = id, hint = hint } end
local function legend(n) return { kind = "legend", n = n, hint = "Reach Legend level " .. n .. "." } end
local STORE = { kind = "store", hint = "Sold in the Tavern Store." }

-- `colors` / `style` are display data the client reads (a color triple, a particle kind). EDIT ME to add options.
Flair.Options = {
	{ id = "classic_numbers", slot = "scoreNumbers", name = "Classic Numbers", icon = "🔢", rarity = "common", default = true, color = { 250, 235, 200 }, glow = 0 },
	{ id = "ember_numbers", slot = "scoreNumbers", name = "Ember Numbers", icon = "🔥", rarity = "uncommon", unlock = rank(5), color = { 255, 170, 90 }, glow = 1 },
	{ id = "frost_numbers", slot = "scoreNumbers", name = "Frost Numbers", icon = "❄️", rarity = "rare", unlock = rank(10), color = { 180, 225, 255 }, glow = 1 },
	{ id = "gold_numbers", slot = "scoreNumbers", name = "Gold Numbers", icon = "🪙", rarity = "rare", unlock = stake(3), color = { 255, 214, 100 }, glow = 2 },
	{ id = "leaf_numbers", slot = "scoreNumbers", name = "Meadow Numbers", icon = "🍃", rarity = "uncommon", unlock = achievement("streak_seven", "Visit seven days in a row."), color = { 170, 230, 140 }, glow = 1 },
	{ id = "rainbow_numbers", slot = "scoreNumbers", name = "Rainbow Numbers", icon = "🌈", rarity = "epic", unlock = STORE, color = { 255, 200, 230 }, glow = 3 },

	{ id = "plain_trail", slot = "playTrail", name = "Plain Play", icon = "🃏", rarity = "common", default = true, style = "none" },
	{ id = "sparkle_trail", slot = "playTrail", name = "Sparkle Trail", icon = "✨", rarity = "uncommon", unlock = quests(10), style = "sparkle" },
	{ id = "ember_trail", slot = "playTrail", name = "Ember Trail", icon = "🔥", rarity = "uncommon", unlock = rank(8), style = "ember" },
	{ id = "star_trail", slot = "playTrail", name = "Star Trail", icon = "⭐", rarity = "rare", unlock = stake(5), style = "star" },
	{ id = "petal_trail", slot = "playTrail", name = "Petal Trail", icon = "🌸", rarity = "rare", unlock = achievement("season_harvest_moon", "Reach tier 25 of the Harvest Moon season."), style = "petal" },
	{ id = "ribbon_trail", slot = "playTrail", name = "Ribbon Trail", icon = "🎀", rarity = "epic", unlock = STORE, style = "ribbon" },

	{ id = "pop_finisher", slot = "finisher", name = "Little Pop", icon = "💥", rarity = "common", default = true, style = "pop" },
	{ id = "firework_finisher", slot = "finisher", name = "Firework", icon = "🎆", rarity = "rare", unlock = rank(12), style = "firework" },
	{ id = "confetti_finisher", slot = "finisher", name = "Confetti", icon = "🎊", rarity = "uncommon", unlock = quests(25), style = "confetti" },
	{ id = "lantern_finisher", slot = "finisher", name = "Lantern Burst", icon = "🏮", rarity = "rare", unlock = achievement("hand_five_hundred", "Play 500 hands."), style = "lantern" },
	{ id = "goldrain_finisher", slot = "finisher", name = "Gold Rain", icon = "🪙", rarity = "epic", unlock = stake(7), style = "goldrain" },
	{ id = "crown_finisher", slot = "finisher", name = "Crown Flash", icon = "👑", rarity = "epic", unlock = STORE, style = "crown" },

	{ id = "no_aura", slot = "nameAura", name = "No Aura", icon = "◻️", rarity = "common", default = true, color = { 222, 182, 104 }, crest = "" },
	{ id = "warm_aura", slot = "nameAura", name = "Warm Glow", icon = "🕯️", rarity = "uncommon", unlock = rank(4), color = { 255, 200, 120 }, crest = "🕯️" },
	{ id = "ember_aura", slot = "nameAura", name = "Ember Aura", icon = "🔥", rarity = "rare", unlock = stake(4), color = { 255, 150, 80 }, crest = "🔥" },
	{ id = "frost_aura", slot = "nameAura", name = "Frost Aura", icon = "❄️", rarity = "rare", unlock = rank(15), color = { 170, 220, 255 }, crest = "❄️" },
	{ id = "legend_aura", slot = "nameAura", name = "Legend Aura", icon = "👑", rarity = "legendary", unlock = legend(2), color = { 255, 226, 140 }, crest = "👑" },
	{ id = "star_aura", slot = "nameAura", name = "Star Aura", icon = "🌟", rarity = "epic", unlock = STORE, color = { 255, 240, 160 }, crest = "🌟" },
}

local BY_ID, BY_SLOT, DEFAULT = {}, {}, {}
for _, slot in ipairs(Flair.Slots) do BY_SLOT[slot.id] = {} end
for _, option in ipairs(Flair.Options) do
	BY_ID[option.id] = option
	table.insert(BY_SLOT[option.slot], option)
	if option.default then DEFAULT[option.slot] = option.id end
end

function Flair.getById(id) return BY_ID[id] end
function Flair.optionsFor(slot) return BY_SLOT[slot] or {} end
function Flair.defaultFor(slot) return DEFAULT[slot] end
function Flair.isSlot(slot) return BY_SLOT[slot] ~= nil end

-- Does a free unlock rule pass right now? (store options are never "free")
local function ruleMet(profile, rule)
	if rule.kind == "rank" then
		return (profile.tavernRank or 1) >= rule.n
	elseif rule.kind == "stake" then
		return (profile.highestStakeUnlocked or 1) >= rule.n + 1
	elseif rule.kind == "quests" then
		return (profile.questsDone or 0) >= rule.n
	elseif rule.kind == "achievement" then
		return Achievements.isUnlocked(profile, rule.id)
	elseif rule.kind == "legend" then
		return Legend.level(profile) >= rule.n
	end
	return false
end

function Flair.isOwned(profile, id)
	local option = BY_ID[id]
	if not option then
		return false
	end
	if option.default then
		return true
	end
	if type(profile.flairOwned) == "table" and profile.flairOwned[id] == true then
		return true
	end
	return option.unlock ~= nil and option.unlock.kind ~= "store" and ruleMet(profile, option.unlock)
end

-- The equipped option of a slot (the default when nothing valid is equipped or the equipped one is not owned).
function Flair.equippedId(profile, slot)
	local id = type(profile.flairEquipped) == "table" and profile.flairEquipped[slot] or nil
	local option = id and BY_ID[id]
	if option and option.slot == slot and Flair.isOwned(profile, id) then
		return id
	end
	return DEFAULT[slot]
end

-- Equips an option into its slot. Validates the slot, the option and ownership. Returns ok, reason.
function Flair.equip(profile, slot, id)
	if type(slot) ~= "string" or type(id) ~= "string" or not BY_SLOT[slot] then
		return false, "Unknown slot."
	end
	local option = BY_ID[id]
	if not option or option.slot ~= slot then
		return false, "That Flair does not fit this slot."
	end
	if not Flair.isOwned(profile, id) then
		return false, "Not unlocked yet."
	end
	profile.flairEquipped = type(profile.flairEquipped) == "table" and profile.flairEquipped or {}
	profile.flairEquipped[slot] = id
	return true
end

-- Grants a store Flair (called by the Store on purchase). Idempotent. Returns true when newly granted.
function Flair.grantOwned(profile, id)
	local option = BY_ID[id]
	if not option or not option.unlock or option.unlock.kind ~= "store" then
		return false
	end
	profile.flairOwned = type(profile.flairOwned) == "table" and profile.flairOwned or {}
	if profile.flairOwned[id] then
		return false
	end
	profile.flairOwned[id] = true
	return true
end

-- The ids of the equipped Flair of every slot (what boards, Friend Presence and spectators carry): { slot = id }.
function Flair.equippedSet(profile)
	local out = {}
	for _, slot in ipairs(Flair.Slots) do
		out[slot.id] = Flair.equippedId(profile, slot.id)
	end
	return out
end

-- A compact public tag for boards and presence rows: the Name Aura id only ("none" values are dropped).
function Flair.publicTag(profile)
	local id = Flair.equippedId(profile, "nameAura")
	return id ~= DEFAULT.nameAura and id or nil
end

-- A tag from the wire (a board row) cleaned to a known Name Aura id, or nil.
function Flair.cleanPublicTag(raw)
	local option = type(raw) == "string" and BY_ID[raw] or nil
	if option and option.slot == "nameAura" and not option.default then
		return raw
	end
	return nil
end

-- What the client draws: per slot the options with owned/equipped flags and the unlock hint.
function Flair.view(profile)
	local slots = {}
	for _, slot in ipairs(Flair.Slots) do
		local equipped = Flair.equippedId(profile, slot.id)
		local options = {}
		for _, option in ipairs(BY_SLOT[slot.id]) do
			options[#options + 1] = {
				id = option.id, name = option.name, icon = option.icon, rarity = option.rarity,
				owned = Flair.isOwned(profile, option.id), equipped = option.id == equipped,
				hint = option.unlock and option.unlock.hint or "", store = option.unlock ~= nil and option.unlock.kind == "store",
				color = option.color, glow = option.glow, style = option.style, crest = option.crest,
			}
		end
		slots[#slots + 1] = { id = slot.id, name = slot.name, icon = slot.icon, equipped = equipped, options = options }
	end
	return { slots = slots }
end

function Flair.cleanSaved(rawOwned, rawEquipped)
	local owned, equipped = {}, {}
	if type(rawOwned) == "table" then
		for id, flag in pairs(rawOwned) do
			local o = type(id) == "string" and BY_ID[id] or nil
			if flag == true and o and o.unlock and o.unlock.kind == "store" then
				owned[id] = true
			end
		end
	end
	if type(rawEquipped) == "table" then
		for slot, id in pairs(rawEquipped) do
			local o = type(slot) == "string" and type(id) == "string" and BY_ID[id] or nil
			if o and o.slot == slot then
				equipped[slot] = id -- ownership is checked when it is read (Flair.equippedId)
			end
		end
	end
	return owned, equipped
end

return Flair
