--[[
	Engine/Gameplay2Tip.lua
	Gameplay v2: the Patron tooltip plate sizes and placement, pure and tested (Client/PatronTipFX draws it).

	  DELAY                      0.25 s after the pointer arrives (or a long press) before the plate shows; leaving hides it at once
	  width(screenW)             320 px on a roomy screen, scaling down to 220 on a small one
	  portrait(plateW)           { w, h } the large card picture on the left of the plate (the cut card's 0.712 aspect)
	  textWidth(plateW)          width left for the name, rarity pill, effect sentence and tags
	  height(plateW, textH)      plate height from the measured text height (the portrait column sets the minimum)
	  avoid(rects)               the rects a plate must stay clear of: top bar, hand, Play, Discard, Rank, Suit, deck and its count
	  place(rects, w, h, slot, tipW, tipH) -> x, y   above, below, right or left of the seat's card (PatronTips.place), inside the screen
	The same card tier frame as the row comes from the cut card picture itself, so the plate reads as the card grown larger.
]]

local PatronTips = require(script.Parent:WaitForChild("PatronTips"))

local M = {}

M.DELAY = 0.25
M.PAD = 12
M.CARD_ASPECT = 0.712

function M.width(screenW)
	return math.floor(math.max(220, math.min(320, (tonumber(screenW) or 1280) * 0.25)))
end

function M.portrait(plateW)
	local pw = math.floor(plateW * 0.3)
	return { w = pw, h = math.floor(pw / M.CARD_ASPECT) }
end

function M.textWidth(plateW)
	return plateW - M.PAD * 3 - M.portrait(plateW).w
end

function M.height(plateW, textH)
	local ph = M.portrait(plateW).h
	return math.floor(math.max(ph, textH) + M.PAD * 2)
end

function M.avoid(r)
	return { r.bar, r.hand, r.play, r.discard, r.sortRank, r.sortSuit, r.deck, r.deckCount }
end

function M.place(r, w, h, slot, tipW, tipH)
	local s = r.slots[slot]
	local card = { x = s.card.x, y = s.card.y, w = s.card.w, h = s.pill.y + s.pill.h - s.card.y } -- the card with its label and pill under it
	return PatronTips.place(card, { X = tipW, Y = tipH }, M.avoid(r), { X = w, Y = h })
end

return M
