--[[
	Engine/PatronVoiceLayout.lua
	Where a Patron's speech bubble stands on the Gameplay v2 table: below the Patron row (under the labels and pills), centred on its
	own Patron, at most 260 px wide, so it never covers another Patron's portrait. Pure numbers in root pixels.

	PatronVoiceLayout.rect(cardX, cardW, rowBottom, rootW) -> { x, y, w, h }   x, y = top left
]]

local M = {}

-- A speech bubble never shares the screen with the finale banner ("TARGET CLEARED!"): while the banner is up the voice is
-- silent. `untilT` is the clock time the banner is done; callers pass os.clock().
function M.suppressed(now, untilT)
	return type(untilT) == "number" and type(now) == "number" and now < untilT
end
M.BANNER_QUIET = 2.5 -- seconds the voice stays quiet after a finale banner starts

M.MAX_W = 260
M.H = 40
M.GAP = 6
M.EDGE = 8

function M.rect(cardX, cardW, rowBottom, rootW)
	local w = math.min(M.MAX_W, math.max(120, rootW - 2 * M.EDGE))
	local cx = cardX + cardW / 2
	local x = math.max(M.EDGE, math.min(cx - w / 2, rootW - M.EDGE - w))
	return { x = math.floor(x), y = math.floor(rowBottom + M.GAP), w = math.floor(w), h = M.H }
end

-- While a hand scores the quote stands BESIDE the Score plate on the stage's top row: left of the plate first, else right, else nil
-- (no room, no bubble). It never touches the plate, the hand name banner row under it or the played cards. { x, y, w, h } | nil
M.SIDE_GAP = 12
function M.beside(plate, stage, rootW)
	local gap, edge = M.SIDE_GAP, M.EDGE
	local leftW = math.min(M.MAX_W, plate.x - gap - edge)
	if leftW >= 120 then return { x = math.floor(plate.x - gap - leftW), y = math.floor(stage.y), w = math.floor(leftW), h = M.H } end
	local rightX = plate.x + plate.w + gap
	local rightW = math.min(M.MAX_W, rootW - edge - rightX)
	if rightW >= 120 then return { x = math.floor(rightX), y = math.floor(stage.y), w = math.floor(rightW), h = M.H } end
	return nil
end

-- The tail points up at the speaking seat: its x inside the bubble (0 = left edge), kept TAIL_PAD from either corner.
M.TAIL_PAD = 18
function M.tailX(bubble, seatCenterX)
	local x = seatCenterX - bubble.x
	return math.floor(math.max(M.TAIL_PAD, math.min(bubble.w - M.TAIL_PAD, x)))
end

return M
