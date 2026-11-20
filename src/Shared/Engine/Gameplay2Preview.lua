--[[
	Engine/Gameplay2Preview.lua
	Gameplay v2: the hand preview line above the centre score while cards are selected, pure and tested. It only formats the numbers
	Engine/HandPreview.compute already returns (the same ones the hand pays), so it cannot disagree with the score.

	line(preview, level) -> "Flush Lv 2  |  50 Chips x 6 Mult"   ("No score" when a rule zeroes the hand), nil for no preview
	rect(stage, text)    -> { x, y, w, h }   a 32 px strip centred on the top of the stage rect, 220 px wide at least, never wider than the stage
	plateStage(stage, minH) -> stage, shifted   the stage the Score plate uses while the strip shows: pushed down H + GAP so the caption stays visible;
	                                            unchanged (shifted false) when the plate would drop under minH
	rich(preview, level) -> the same line as line() with gold name, blue Chips and red Mult (RichText)
	levelOf(handLevels, name) -> level, 1 when the hand has not been levelled
]]

local M = {}

M.H = 32
M.GAP = 8 -- px between the strip and the Score plate under it
M.MIN_W = 260
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

function M.plateStage(stage, minH)
	local d = M.H + M.GAP
	if stage.h - d < (minH or 0) then return stage, false end
	return { x = stage.x, y = stage.y + d, w = stage.w, h = stage.h - d }, true
end

M.INK = { name = "#F2CF72", chips = "#7DB7FF", mult = "#FF8A7A", plain = "#F4E8CF" } -- on the dark wood plate, each at least 4.5:1

function M.rich(preview, level)
	if not preview or not preview.name then return nil end
	local lv = math.max(1, floor(level))
	local chips, mult = floor(preview.chips), floor(preview.mult)
	local I = M.INK
	local head = string.format('<font color="%s">%s Lv %d</font>', I.name, preview.name, lv)
	if chips * mult <= 0 then return head .. string.format('  <font color="%s">|  No score</font>', I.plain) end
	return head .. string.format('  <font color="%s">|</font>  <font color="%s">%d Chips</font> <font color="%s">x</font> <font color="%s">%d Mult</font>', I.plain, I.chips, chips, I.plain, I.mult, mult)
end

function M.rect(stage, text)
	local w = math.min(stage.w, math.max(M.MIN_W, #(text or "") * M.CHAR_W + 64))
	return { x = stage.x + math.floor((stage.w - w) / 2), y = stage.y, w = w, h = math.min(M.H, stage.h) }
end

return M
