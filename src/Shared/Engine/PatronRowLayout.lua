--[[
	Shared/Engine/PatronRowLayout.lua
	Pure layout (tested) for the Patron Row: big Patron cards standing on the table above the hand.

	  PatronRowLayout.compute(rootW, rootH, hand, count, opts) -> layout | nil
	    rootW, rootH  size of the play area in px
	    hand          { x, y, w, h } the live hand frame (the row is centred over it and ends above the cards)
	    count         cards to draw (owned Patrons plus free seats), 0 gives nil
	    opts.topLimit lowest y the row may start at (the dock icons end there), default 92

	  layout = { cards = { {x, y, w, h} per card, left to right }, cardW, cardH, plaqueH, step, overlap (bool),
	             rect = {x, y, w, h} bounding box of cards and plaques }

	Card size is 96 x 132 at 1506 px wide and scales with the screen (never under 72 x 100 unless the free height
	forces it). Up to five cards sit side by side with a 10 px gap; when more do not fit they overlap evenly, each
	card keeping at least 60 percent of its width visible. The row ends 8 px above the top of the hand cards, so it
	never covers the hand, and the plaque (name, 15 px text) hangs under each card inside the row's box.
]]

local M = {}

M.BASE_W, M.BASE_H, M.BASE_SCREEN = 96, 132, 1506
M.MIN_W, M.MIN_H = 72, 100
M.GAP = 10
M.PLAQUE_H = 22
M.MIN_VISIBLE = 0.6
M.TOP_LIMIT = 92
M.HAND_TOP_PAD = 19 -- cards in a 200 px hand frame stand at most 165 px tall with 16 px under them
M.AIR = 8 -- clear space between the plaques and the hand cards

local function floor(n) return math.floor(n + 0.5) end

function M.scale(rootW)
	return math.max(0.75, math.min(1.3, rootW / M.BASE_SCREEN))
end

function M.compute(rootW, rootH, hand, count, opts)
	if not count or count <= 0 or not hand then return nil end
	local topLimit = opts and opts.topLimit or M.TOP_LIMIT
	local k = M.scale(rootW)
	local handTop = hand.y + (hand.h >= 200 and M.HAND_TOP_PAD or 0)
	local bottom = handTop - M.AIR
	local availH = bottom - topLimit - M.PLAQUE_H
	local cardH = math.min(M.BASE_H * k, availH)
	if cardH < M.MIN_H and availH >= M.MIN_H then cardH = M.MIN_H end
	if cardH < 24 then return nil end -- no room at all: the row hides rather than covering something
	local cardW = cardH * M.BASE_W / M.BASE_H
	-- width: centred over the hand, which never reaches the left board or the draw pile
	local availW = math.min(hand.w, rootW)
	local gap = M.GAP
	local step = cardW + gap
	local overlap = false
	if count * cardW + (count - 1) * gap > availW and count > 1 then
		overlap = true
		step = (availW - cardW) / (count - 1)
		local minStep = cardW * M.MIN_VISIBLE
		if step < minStep then
			-- too many for the width: shrink the cards so 60 percent of each still shows
			step = minStep
			cardW = availW / (1 + M.MIN_VISIBLE * (count - 1))
			cardH = cardW * M.BASE_H / M.BASE_W
			step = cardW * M.MIN_VISIBLE
		end
	end
	local totalW = cardW + step * (count - 1)
	local x0 = hand.x + (hand.w - totalW) / 2
	x0 = math.max(0, math.min(x0, rootW - totalW))
	local y = bottom - M.PLAQUE_H - cardH
	local out = { cards = {}, cardW = floor(cardW), cardH = floor(cardH), plaqueH = M.PLAQUE_H, step = step, overlap = overlap }
	for i = 1, count do
		out.cards[i] = { x = floor(x0 + (i - 1) * step), y = floor(y), w = floor(cardW), h = floor(cardH) }
	end
	local last = out.cards[count]
	out.rect = { x = out.cards[1].x, y = floor(y), w = last.x + last.w - out.cards[1].x, h = floor(cardH) + M.PLAQUE_H }
	return out
end

return M
