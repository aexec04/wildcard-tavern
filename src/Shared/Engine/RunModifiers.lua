--[[
	RunModifiers.lua
	Start-of-run blessings with a matching curse. After Begin Run the player drafts one of three of these (see
	Engine/RunChoice.lua). Each is data: a blessing and a curse, both small numbers, so no pick is a trap and no
	pick is free. Pure Lua, no Roblox APIs.

	Fields per modifier:
		id, name, icon, blessing (text), curse (text)
		config = { key = delta }      added to state.config (applies to every round from now on)
		rules  = { key = delta|true } added to state.stakeRules (see Engine/Stakes.lua for the keys)
		tips   = n                    Tips added now
	The live first round is adjusted too (hands, discards), so the pick works at once, not from round 2.
]]

local RunModifiers = {}

RunModifiers.Definitions = {
	{
		id = "open_hands", name = "Open Hands", icon = "🙌",
		blessing = "+1 Hand every round", curse = "1 fewer Patron seat",
		config = { handsPerRound = 1, patronSlotLimit = -1 },
	},
	{
		id = "fat_purse", name = "Fat Purse", icon = "👛",
		blessing = "+6 Tips now", curse = "Boss targets are 10% higher",
		tips = 6, rules = { bossTargetPct = 10 },
	},
	{
		id = "sharp_eyes", name = "Sharp Eyes", icon = "👁️",
		blessing = "+1 Discard every round", curse = "Shop rerolls cost 1 more",
		config = { discardsPerRound = 1 }, rules = { rerollExtra = 1 },
	},
	{
		id = "big_book", name = "Big Recipe Book", icon = "📚",
		blessing = "Recipe box holds 1 more", curse = "No interest on your Tips",
		config = { recipeSlotLimit = 1 }, rules = { noInterest = true },
	},
	{
		id = "generous_house", name = "Generous House", icon = "🏮",
		blessing = "Rounds pay +2 Tips", curse = "1 fewer Discard every round",
		config = { tipsPerRoundWin = 2, discardsPerRound = -1 },
	},
	{
		id = "wide_table", name = "Wide Table", icon = "🪑",
		blessing = "1 more Patron seat", curse = "Rounds pay 1 less Tip",
		config = { patronSlotLimit = 1, tipsPerRoundWin = -1 },
	},
	{
		id = "spare_chair", name = "Spare Chair", icon = "💺",
		blessing = "1 more Patron seat", curse = "Boss targets are 8% higher",
		config = { patronSlotLimit = 1 }, rules = { bossTargetPct = 8 },
	},
	{
		id = "extra_hand", name = "Extra Hand", icon = "✋",
		blessing = "+1 Hand every round", curse = "Rounds pay 2 less Tips",
		config = { handsPerRound = 1, tipsPerRoundWin = -2 },
	},
	{
		id = "lucky_penny", name = "Lucky Penny", icon = "🍀",
		blessing = "+1 Discard and +3 Tips now", curse = "1 fewer Hand every round",
		tips = 3, config = { discardsPerRound = 1, handsPerRound = -1 },
	},
}

function RunModifiers.getById(id)
	for _, def in ipairs(RunModifiers.Definitions) do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- One line of a blessing ("+") or of a curse ("-") as it is written on the choice card and on the board: the sign, a
-- space, the words. A text that opens with its own sign ("+1 Hand every round") keeps one sign: both places used to
-- add theirs in front and read "+ +1 Hand every round".
function RunModifiers.line(sign, text)
	text = tostring(text or "")
	if text:sub(1, 1) == sign then text = text:sub(2) end
	text = text:gsub("^%s+", "")
	return sign .. " " .. text
end

-- Display data for the blessing a run picked (nil when none): { id, name, icon, blessing, curse, line }.
function RunModifiers.view(id)
	local def = id and RunModifiers.getById(id)
	if not def then
		return nil
	end
	return {
		id = def.id, name = def.name, icon = def.icon, blessing = def.blessing, curse = def.curse,
		line = def.name .. ": " .. def.blessing .. " / " .. def.curse,
	}
end

-- Applies a modifier to a run that is at the start of its first round. Returns true, message.
function RunModifiers.apply(state, id)
	local def = RunModifiers.getById(id)
	if not def then
		return false, "Unknown modifier"
	end
	local config = state.config
	for key, delta in pairs(def.config or {}) do
		config[key] = (config[key] or 0) + delta
	end
	config.handsPerRound = math.max(1, config.handsPerRound)
	config.discardsPerRound = math.max(0, config.discardsPerRound)
	config.patronSlotLimit = math.max(1, config.patronSlotLimit)
	config.recipeSlotLimit = math.max(0, config.recipeSlotLimit)
	config.tipsPerRoundWin = math.max(1, config.tipsPerRoundWin)

	state.stakeRules = state.stakeRules or {}
	for key, delta in pairs(def.rules or {}) do
		if type(delta) == "boolean" then
			state.stakeRules[key] = state.stakeRules[key] or delta
		else
			state.stakeRules[key] = (state.stakeRules[key] or 0) + delta
		end
	end

	if def.tips then
		state.tips = state.tips + def.tips
	end

	-- the round that is already dealt
	local handsDelta = (def.config and def.config.handsPerRound) or 0
	local discardsDelta = (def.config and def.config.discardsPerRound) or 0
	if handsDelta ~= 0 then
		state.handsRemaining = math.max(1, state.handsRemaining + handsDelta)
		state.roundStartHands = math.max(1, (state.roundStartHands or state.handsRemaining) + handsDelta)
	end
	if discardsDelta ~= 0 then
		state.discardsRemaining = math.max(0, state.discardsRemaining + discardsDelta)
		state.roundStartDiscards = math.max(0, (state.roundStartDiscards or state.discardsRemaining) + discardsDelta)
	end
	state.runModifierId = id
	return true, def.name .. ": " .. def.blessing .. ", but " .. string.lower(string.sub(def.curse, 1, 1)) .. string.sub(def.curse, 2) .. "."
end

return RunModifiers
