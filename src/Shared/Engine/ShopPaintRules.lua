--[[
	Engine/ShopPaintRules.lua
	Which painted frame each Counter control wears, and where the three tabs stand once the tab bar's list layout is off
	(a painted frame is a sibling picture, and a UIListLayout would lay it out as a fourth tab).
	  pieceFor(kind, active)  kind "tab" | "tag" | "chip" | "next" -> a key of TavernStyle.PAINTED
	  tabSlot(i, n, gap)      Position and Size numbers for tab i of n: { xs, xo, ws, wo } (scale and offset, full height)
]]

local M = {}

function M.pieceFor(kind, active)
	if kind == "tab" then return active and "wh_btn_green" or "wh_btn_dark" end -- the whole-picture ornate family the table wears (trim and corner scrolls stay readable at 50 px)
	if kind == "next" then return "orn_btn_green" end
	if kind == "chip" then return "orn_wide" end
	if kind == "summary" then return "orn_score" end
	return "wh_btn_dark" -- Reroll and Haggle name tags
end

function M.tabSlot(i, n, gap)
	n = math.max(1, n)
	gap = gap or 6
	return { xs = (i - 1) / n, xo = gap / 2, ws = 1 / n, wo = -gap }
end

return M
