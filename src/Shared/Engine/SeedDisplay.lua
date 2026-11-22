--[[
	Shared/Engine/SeedDisplay.lua
	What to show for "which run am I on" (pure, tested): the seed code of a Seed Run, the date of a Daily, the
	week of a Weekly. Ordinary runs have no seed to show.

	label(state) -> { kind = "seed"|"daily"|"weekly", title = "Seed", value = "ABC234", text = "Seed: ABC234",
	                  shareable = bool } | nil
	shareText(state) -> "Play my The Gilded Knave seed: ABC234" | nil     (only Seed Runs can be shared)
]]

local GameName = require(script.Parent.GameName)

local SeedDisplay = {}

function SeedDisplay.label(state)
	if type(state) ~= "table" then return nil end
	if state.isSeeded and state.seedCode then
		local value = tostring(state.seedCode)
		return { kind = "seed", title = "Seed", value = value, text = "Seed: " .. value, shareable = true }
	elseif state.isDaily then
		local value = tostring(state.dailyDateKey or "today")
		-- a live event may theme the label (text only; the seed, rules and board are untouched)
		local theme = type(state.dailyTheme) == "string" and state.dailyTheme ~= "" and (" (" .. state.dailyTheme .. ")") or ""
		local twist = type(state.dailyModifierInfo) == "table" and type(state.dailyModifierInfo.name) == "string" and state.dailyModifierInfo.name or nil
		local text = twist and ("Daily: " .. twist) or ("Daily: " .. value .. theme) -- the twist of the day replaces the date on the table scroll
		return { kind = "daily", title = "Daily", value = value, text = text, twist = twist, shareable = false }
	elseif state.isWeekly then
		local value = tostring(state.weeklyDateKey or "this week")
		return { kind = "weekly", title = "Weekly", value = value, text = "Weekly: " .. value, shareable = false }
	end
	return nil
end

function SeedDisplay.shareText(state)
	local l = SeedDisplay.label(state)
	if l and l.shareable then
		return "Play my " .. GameName.NAME .. " seed: " .. l.value
	end
	return nil
end

return SeedDisplay
