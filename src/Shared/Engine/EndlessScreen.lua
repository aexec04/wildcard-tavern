--[[
	EndlessScreen.lua
	The text of the Endless part of the Run Over screen: this run's Endless Night, the best Endless Night on this stake and a
	short kind share line. A run is in Endless once its Night passes the Night cap. Pure Lua, no Roblox APIs.

	lines(state, bests, stake)   { headline = "Endless Night 14", best = "Best Endless Night 16", isBest = bool } or nil
	shareLine(night, best)       "I reached Endless Night 14 in <game>. Can you beat me?" (one of three variants, 80 characters or less)

	Every line is short (under MAX_LINE characters) so it fits one row at the smallest screen, and none carries a number
	that is not floored first.
]]

local GameName = require(script.Parent.GameName)

local EndlessScreen = {}

EndlessScreen.MAX_LINE = 44
EndlessScreen.MAX_SHARE = 200

local function whole(n)
	return math.max(0, math.floor(tonumber(n) or 0))
end

-- True once the run is past its last Night.
function EndlessScreen.isEndless(state)
	local cap = state and state.config and state.config.nightCap
	return type(state) == "table" and cap ~= nil and whole(state.night) > whole(cap)
end

-- Players read the real Night number, so the headline shows it as is (Night 14 is "Endless Night 14").
function EndlessScreen.lines(state, bests, stake)
	if not EndlessScreen.isEndless(state) then return nil end
	local night = whole(state.night)
	local saved = type(bests) == "table" and bests[tostring(stake or state.stake or 1)] or nil
	local best = math.max(night, whole(saved))
	return {
		headline = string.format("Endless Night %d", night),
		best = string.format("Best Endless Night %d", best),
		isBest = night >= best,
	}
end

function EndlessScreen.shareLine(night, best)
	night = math.max(1, whole(night))
	return require(script.Parent.ShareVariants).line("endless", { night = night }, night + whole(best)) -- one of three variants, 80 characters or less
end

return EndlessScreen
