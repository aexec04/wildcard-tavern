--[[
	Engine/PlayBudget.lua
	ONE vertical budget for the play table, so the Patron nook, the played lane, the hand and the buttons never fight.
	Numbers are GUI units at the 1506 x 751 reference root and scale with min(rootW / 1506, rootH / 751).

	  top strip (dock icons)  y   0 to  56
	  Patron nook             y  56 to 250   (slim: cards about 100 tall, name plaques inside the alcove)
	  played lane             y 254 to 344   (played cards at 70 percent, readout above them in the lane gap)
	  hand                    y 348 to 500   (cards about 100 x 145)
	  buttons                 y 508 to 578   (Play Hand and Discard about 70 percent of the old plate, chip 28 tall)

	PlayBudget.rects(rootW, rootH) -> { k, top, nook, lane, hand, buttons } each { y, h }
	PlayBudget.nookMax(rootW, rootH) -> tallest the Patron strip may be, y it starts at
	PlayBudget.overlaps(rects) -> names of the first two neighbouring rows that overlap, or nil
]]

local M = {}

M.REF_W, M.REF_H = 1506, 751
M.ROWS = {
	{ "top", 0, 56 },
	{ "nook", 56, 250 },
	{ "lane", 254, 344 },
	{ "hand", 348, 500 },
	{ "buttons", 508, 578 },
}
M.LANE_SCALE = 0.7 -- played cards, relative to the hand cards
M.MIN_TEXT = 15

function M.scale(rootW, rootH)
	return math.max(0.5, math.min(rootW / M.REF_W, rootH / M.REF_H, 1.3))
end

function M.rects(rootW, rootH)
	local k = M.scale(rootW, rootH)
	local out = { k = k }
	for _, r in ipairs(M.ROWS) do
		out[r[1]] = { y = r[2] * k, h = (r[3] - r[2]) * k }
	end
	return out
end

function M.nookMax(rootW, rootH)
	local r = M.rects(rootW, rootH).nook
	return r.h, r.y
end

function M.overlaps(rects)
	for i = 1, #M.ROWS - 1 do
		local an, bn = M.ROWS[i][1], M.ROWS[i + 1][1]
		local a, b = rects[an], rects[bn]
		if a.y + a.h > b.y + 0.001 then return an, bn end
	end
	return nil
end

return M
