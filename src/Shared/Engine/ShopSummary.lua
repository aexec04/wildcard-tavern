--[[
	Engine/ShopSummary.lua
	The round summary plate that stays on the Counter after a won round: "Target cleared", "Score N of T", "Tips +N".
	Pure numbers so Client/ShopSummaryPlate and the tests read one place.

	ShopSummary.rect(w, h)      { x, y, w, h } top right, under the corner buttons, 12 px from the edge, at most 300 wide
	ShopSummary.keepOut(w, h)   the same rect, for CornerToastRules.below so the quest toast column starts 8 px under it
	ShopSummary.lines(clear)    { title, score, tips } from Gameplay2Moments.clearLines, or nil
]]

local M = {}

M.EDGE = 12
M.TOP = 74 -- the corner buttons end at y 66 (CornerToastRules.TOP)
M.WIDTH_MAX = 300
M.HEIGHT = 92
M.TOAST_GAP = 8

function M.rect(w, h)
	local W = math.max(1, tonumber(w) or 1920)
	local width = math.min(M.WIDTH_MAX, math.floor(W * 0.30))
	return { x = W - M.EDGE - width, y = M.TOP, w = width, h = M.HEIGHT }
end

function M.keepOut(w, h)
	return M.rect(w, h)
end

function M.lines(clear)
	if type(clear) ~= "table" then return nil end
	return { title = clear.title or "Target cleared", score = clear.score or "", tips = clear.tips or "" }
end

return M
