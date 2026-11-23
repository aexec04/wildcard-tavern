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

-- The hand name plate: a small plate right under the Round/boss plate (standing in for its Night line while cards are picked), the Target plate's width. nil when the Patron row is too close.
M.NAME_H = 30
M.NAME_MIN_H = 18
M.CHIP_DROP = 36 -- the Patron value chips hang this far below a seat card
M.NAME_AIR = 6 -- clear space to the first Patron seat
M.NIGHT_ROOM = 2 -- the plate takes the Night line's place while a hand is picked (the gap to the Patron row is under 30 px)
function M.namePlate(r)
	local R = r and r.round
	if not R then return nil end
	local seatTop = math.huge
	for _, s in ipairs(r.slots or {}) do
		if s.card then seatTop = math.min(seatTop, s.card.y) end
	end
	local y = R.y + R.h + M.NIGHT_ROOM
	local h = math.min(M.NAME_H, (seatTop < math.huge and seatTop - M.NAME_AIR or y + M.NAME_H) - y)
	if h >= M.NAME_MIN_H then return { x = R.x, y = y, w = R.w, h = h } end
	-- no room under the Round plate (a short screen): hang the plate on the empty felt below the Patron seats and their chips, clear of the hand
	local seatBottom, hand = 0, r.hand
	for _, s in ipairs(r.slots or {}) do
		if s.card then seatBottom = math.max(seatBottom, s.card.y + (s.card.h or 0)) end
	end
	if seatBottom <= 0 or not hand then return nil end
	local fy = seatBottom + M.CHIP_DROP
	local fh = M.NAME_H
	if fy + fh > hand.y - 28 then return nil end -- a picked card lifts 24 px: never reach the hand
	return { x = R.x, y = fy, w = R.w, h = fh }
end

-- the plain hand name for the plate ("Flush"), nil for no preview
function M.nameText(preview)
	if not preview or not preview.name then return nil end
	return tostring(preview.name)
end

function M.rect(stage, text)
	local w = math.min(stage.w, math.max(M.MIN_W, #(text or "") * M.CHAR_W + 64))
	return { x = stage.x + math.floor((stage.w - w) / 2), y = stage.y, w = w, h = math.min(M.H, stage.h) }
end

return M
