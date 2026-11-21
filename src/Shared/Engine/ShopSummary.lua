--[[
	Engine/ShopSummary.lua
	The round summary plate that stays on the Counter after a won round: "Target cleared", "Score N of T", "Tips +N".
	Pure numbers so Client/ShopSummaryPlate and the tests read one place.

	ShopSummary.rect(w, h)      { x, y, w, h } in the footer, 12 px left of the Next Round button, 260 wide and 64 tall
	ShopSummary.keepOut(w, h)   nil (nothing in the top right any more)
	ShopSummary.lines(clear)    { title, score, tips } from Gameplay2Moments.clearLines, or nil
]]

local SceneLayout = require(script.Parent.ShopSceneLayout)

local M = {}

M.EDGE = 12
M.WIDTH_MAX = 260 -- half the old plate
M.HEIGHT = 64 -- the same height as the Next Round button it stands beside
M.BORDER = 11 -- the carved border of the ornate plate at this size (the picture scales with its height)
M.PAD = 4
M.GAP = 12 -- clear of the Next Round button
M.TOAST_GAP = 8
M.SHOW_SECONDS = 6 -- fades out by itself this long after the Counter opens (at once in Calm mode)
M.ROW_SIZE = 15

-- The plate lives in the Counter footer, left of Next Round, below the tab lists (they end TAB_BOTTOM_RESERVE px above the bottom):
-- never over the tabs, the Next boss strip, the Patron seats, the House Passes or the speech strip.
function M.rect(w, h)
	local W = math.max(1, tonumber(w) or 1920)
	local H = math.max(1, tonumber(h) or 1080)
	local leave = SceneLayout.rects(W, H).leave
	local width = math.min(M.WIDTH_MAX, math.floor(W * 0.30))
	local right = (leave and leave.x or (W - M.EDGE)) - M.GAP
	return { x = math.max(M.EDGE, right - width), y = leave and leave.y or (H - 76), w = width, h = M.HEIGHT }
end

-- The two text rows inside a plate of width pw, relative to the plate, clear of the carved border: the title, then Score and Tips on one line.
function M.rows(pw)
	local inset = M.BORDER + M.PAD
	local rw = math.max(1, (tonumber(pw) or M.WIDTH_MAX) - 2 * inset)
	local inner = M.HEIGHT - 2 * inset
	local th = math.floor(inner / 2)
	return {
		title = { x = inset, y = inset, w = rw, h = th, size = M.ROW_SIZE },
		score = { x = inset, y = inset + th, w = rw, h = inner - th, size = M.ROW_SIZE },
	}
end

-- The one line under the title: "Score 180 of 65   Tips +4"
function M.detail(lines)
	if type(lines) ~= "table" then return "" end
	local a, b = lines.score or "", lines.tips or ""
	if a ~= "" and b ~= "" then return a .. "   " .. b end
	return a .. b
end

-- The toast column no longer has to dodge the plate (it is in the footer).
function M.keepOut(w, h)
	return nil
end

function M.lines(clear)
	if type(clear) ~= "table" then return nil end
	return { title = clear.title or "Target cleared", score = clear.score or "", tips = clear.tips or "" }
end

return M
