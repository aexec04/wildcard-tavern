--[[
	Engine/Gameplay2Preview.lua
	Gameplay v2: the hand preview line above the centre score while cards are selected, pure and tested. It only formats the numbers
	Engine/HandPreview.compute already returns (the same ones the hand pays), so it cannot disagree with the score.

	line(preview, level) -> "Flush Lv 2  |  50 Chips x 6 Mult"   ("No score" when a rule zeroes the hand), nil for no preview
	rect(stage, text)    -> { x, y, w, h }   a 26 px pill centred on the top of the stage rect, 220 px wide at least, never wider than the stage
	levelOf(handLevels, name) -> level, 1 when the hand has not been levelled
]]

local M = {}

M.H = 26
M.MIN_W = 220
M.CHAR_W = 9

local function floor(n) return math.floor(tonumber(n) or 0) end

function M.levelOf(handLevels, name)
	local lv = handLevels and handLevels[name]
	return math.max(1, floor(lv))
end

function M.line(preview, level)
	if not preview or not preview.name then return nil end
	local lv = math.max(1, floor(level))
	local chips, mult = floor(preview.chips), floor(preview.mult)
	if chips * mult <= 0 then return string.format("%s Lv %d  |  No score", preview.name, lv) end
	return string.format("%s Lv %d  |  %d Chips x %d Mult", preview.name, lv, chips, mult)
end

function M.rect(stage, text)
	local w = math.min(stage.w, math.max(M.MIN_W, #(text or "") * M.CHAR_W + 24))
	return { x = stage.x + math.floor((stage.w - w) / 2), y = stage.y, w = w, h = M.H }
end

return M
