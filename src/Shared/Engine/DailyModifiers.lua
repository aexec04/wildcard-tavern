--[[
	DailyModifiers.lua
	One kid safe twist per day for the Daily Run, the same for every player (picked from the UTC date key, no
	randomness). Twelve data entries, none of them a pure penalty, so the board stays fair: every twist is a trade
	or a gift that changes how you plan the run. Pure Lua, no Roblox APIs.

	Fields per entry:
	  id, name, icon, text   text is the one short line shown on the Menu plate and the table scroll
	  config                 { key = delta }   added to state.config before the first round
	  setConfig              { key = value }   set on state.config
	  startTips              Tips the run starts with on top of the deck's own
	  rules                  { patronPower, tipsPercent }   copied to state.dailyRules (same meaning as Challenges rules)

	Never applied to normal, Weekly, Seed, Boss Rush, Quick or challenge runs.
]]

local DailyModifiers = {}

DailyModifiers.Definitions = {
	{ id = "short_hands", name = "Short Hands", icon = "✋", text = "Draw 1 fewer card but play 1 extra Hand.", config = { handSize = -1, handsPerRound = 1 } },
	{ id = "golden_start", name = "Golden Start", icon = "🌟", text = "Start the run with 8 extra Tips.", startTips = 8 },
	{ id = "extra_seat", name = "Extra Seat", icon = "🪑", text = "One more Patron seat at your table.", config = { patronSlotLimit = 1 } },
	{ id = "big_box", name = "Big Recipe Box", icon = "📦", text = "The recipe box holds 2 more.", config = { recipeSlotLimit = 2 } },
	{ id = "loud_crowd", name = "Loud Crowd", icon = "📣", text = "Every Patron effect counts 25% more.", rules = { patronPower = 1.25 } },
	{ id = "spare_cards", name = "Spare Cards", icon = "🗑️", text = "2 extra Discards every round.", config = { discardsPerRound = 2 } },
	{ id = "quick_deal", name = "Quick Deal", icon = "⚡", text = "1 extra Hand, 1 fewer Discard.", config = { handsPerRound = 1, discardsPerRound = -1 } },
	{ id = "wide_table", name = "Wide Table", icon = "🍽️", text = "Draw 2 extra cards but play 1 fewer Hand.", config = { handSize = 2, handsPerRound = -1 } },
	{ id = "penny_pincher", name = "Penny Pincher", icon = "🪙", text = "Tips pay 75%, Patron effects count 50% more.", rules = { tipsPercent = 75, patronPower = 1.5 } },
	{ id = "solo_star", name = "Solo Star", icon = "⭐", text = "One seat, effect counts 4x, +3 Hands, +4 Discards, +8 Tips.", setConfig = { patronSlotLimit = 1 }, startTips = 8, config = { handsPerRound = 3, discardsPerRound = 4, handSize = 1 }, rules = { patronPower = 4 } },
	{ id = "thrifty_table", name = "Thrifty Table", icon = "🥣", text = "Start with 4 extra Tips and 1 extra Discard.", startTips = 4, config = { discardsPerRound = 1 } },
	{ id = "steady_hands", name = "Steady Hands", icon = "🤝", text = "1 extra Hand every round.", config = { handsPerRound = 1 } },
}

function DailyModifiers.getById(id)
	for _, def in ipairs(DailyModifiers.Definitions) do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Whole days since 1970-01-01 for a "YYYY-MM-DD" key (pure arithmetic, no os.time, so it agrees everywhere).
-- Returns nil for anything that is not a real-looking date key.
function DailyModifiers.dayNumber(dateKey)
	if type(dateKey) ~= "string" then
		return nil
	end
	local y, m, d = dateKey:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y or m < 1 or m > 12 or d < 1 or d > 31 then
		return nil
	end
	-- days from civil (Howard Hinnant), integer math only
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- The day's twist. Stepping by 5 through 12 entries visits every entry once per 12 days and never repeats on
-- two days in a row. A bad key falls back to the first entry so a run never starts without one.
function DailyModifiers.forDate(dateKey)
	local day = DailyModifiers.dayNumber(dateKey)
	local count = #DailyModifiers.Definitions
	if not day then
		return DailyModifiers.Definitions[1]
	end
	return DailyModifiers.Definitions[(day * 5) % count + 1]
end

-- Sets a fresh run up for the twist, before its first round is dealt. Returns true on success.
function DailyModifiers.configure(state, id)
	local def = DailyModifiers.getById(id)
	if not def then
		return false
	end
	local config = state.config
	for key, delta in pairs(def.config or {}) do
		config[key] = (config[key] or 0) + delta
	end
	for key, value in pairs(def.setConfig or {}) do
		config[key] = value
	end
	config.handSize = math.max(1, config.handSize)
	config.handsPerRound = math.max(1, config.handsPerRound)
	config.discardsPerRound = math.max(0, config.discardsPerRound)
	config.patronSlotLimit = math.max(1, config.patronSlotLimit)
	config.recipeSlotLimit = math.max(0, config.recipeSlotLimit)
	state.tips = (state.tips or 0) + (def.startTips or 0)
	local rules = { id = def.id, name = def.name }
	for key, value in pairs(def.rules or {}) do
		rules[key] = value
	end
	state.dailyModifier = rules
	return true
end

return DailyModifiers
