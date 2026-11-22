--[[
	Shared/Engine/ThumbReach.lua
	Thumb reach audit for the play table on phones and small tablets (landscape, held in two hands). Pure and tested: it reads the live
	rectangles from Engine/ConceptTLayout (the same function the table draws from), so a layout change shows up here.

	ThumbReach.audit(w, h) -> list of finding strings, empty when everything critical is in reach
	    * every critical control (Play Hand, Discard, the Rank and Suit sort plates, the hand, the deck) has its centre in the lower
	      60 percent of the screen and is at least 44 px tall on touch sizes (the hand and the deck are big cards, exempt)
	    * nothing critical sits in the top centre (the middle third of the width, the top 20 percent of the height)
	    * every critical control stays fully on screen
	ThumbReach.CRITICAL    the rect names checked
	ThumbReach.INFO        top rects that are read only (round banner, coins, hands pills): allowed anywhere, never need a tap
]]

local L = require(script.Parent.ConceptTLayout)

local M = {}

M.CRITICAL = { "play", "discard", "sort", "hand", "deck" }
M.INFO = { "round", "coins", "hands", "stage", "deckCount" }
M.LOWER = 0.40 -- a critical centre must be at or below 40 percent of the height (the lower 60 percent)
M.TOP_H = 0.20 -- the top centre band
M.MIN_TOUCH = 44

function M.rects(w, h)
	local r = L.rectsIn(w, h)
	local sz = L.sortSize(w, h)
	r.sort = L.sortSpot(w, h, sz.w, sz.h, r)
	return r
end

-- Phones and tablets: anything shorter than 800 px or narrower than 1500 px. A 1920x957 desktop window keeps its 34 px mouse plates.
function M.isTouch(w, h) return w < 1500 or h < 800 end

function M.audit(w, h)
	local out = {}
	local touch = M.isTouch(w, h)
	local r = M.rects(w, h)
	for _, name in ipairs(M.CRITICAL) do
		local b = r[name]
		if not b then
			out[#out + 1] = name .. " has no rect"
		else
			local cy = b.y + b.h / 2
			if cy < M.LOWER * h then out[#out + 1] = name .. " centre is above the lower 60 percent" end
			if touch and name ~= "hand" and name ~= "deck" and b.h < M.MIN_TOUCH then out[#out + 1] = name .. " is under 44 px tall" end
			local cx = b.x + b.w / 2
			if cy < M.TOP_H * h and cx > w / 3 and cx < w * 2 / 3 then out[#out + 1] = name .. " sits in the top centre" end
			if b.x < 0 or b.y < 0 or b.x + b.w > w or b.y + b.h > h then out[#out + 1] = name .. " leaves the screen" end
		end
	end
	return out
end

return M
