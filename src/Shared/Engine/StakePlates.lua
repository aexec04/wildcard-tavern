--[[
	Shared/Engine/StakePlates.lua
	The look of the Stakes picker in Run Setup (TavernStyle colours): one dark wood plate per tier with a tier colour edge,
	cream text, and locked tiers dimmed with their "Win a run on X." hint still at 4.5:1. Pure data and helpers, tested.

	StakePlates.style(n, locked, selected) -> { fill, text, sub, edge, height }   (colours are {r, g, b})
]]

local Style = require(script.Parent.TavernStyle)

local M = {}

M.HEIGHT = 66 -- plate height in px, over the 44 px touch minimum
-- Tier colours, calm to hot: 1 sage, 2 amber, 3 orange, 4 ember, 5 crimson, 6 plum, 7 indigo, 8 gold
M.TIER_EDGE = {
	{ 120, 170, 110 }, { 214, 170, 80 }, { 226, 140, 60 }, { 224, 104, 60 },
	{ 214, 76, 76 }, { 170, 100, 200 }, { 110, 130, 220 }, { 240, 200, 80 },
}

function M.edgeOf(n)
	return M.TIER_EDGE[math.max(1, math.min(#M.TIER_EDGE, math.floor(tonumber(n) or 1)))]
end

function M.style(n, locked, selected)
	local c = Style.COLORS
	local fill = selected and c.plateFillLight or c.plateFill
	local text, sub = c.cream, c.creamSoft
	if locked then
		fill = c.plateDark
		text, sub = { 205, 192, 172 }, { 205, 192, 172 }
	end
	return { fill = fill, text = text, sub = sub, edge = M.edgeOf(n), height = M.HEIGHT }
end

return M
