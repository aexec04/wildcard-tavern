--[[
	Engine/PayloadGuard.lua
	Shape checks for values a client sends over a remote. Pure, so the tests can throw every bad shape at them.
	A client can fire any remote with any value, so nothing here trusts the type, the length or the contents.

	PayloadGuard.wholeNumber(v) -> bool
	    a real number with no fraction (not NaN, not an infinity)
	PayloadGuard.indexList(list, handSize, maxCount) -> bool
	    true only for an array of 1 to maxCount whole numbers (default 5), each from 1 to handSize, with no repeats,
	    no holes and no extra keys. Fractions (1.5 used to pass and picked no card), NaN, infinities, strings,
	    dictionaries and nested tables are all refused.
]]

local M = {}

M.MAX_CARDS = 5

function M.wholeNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v == math.floor(v)
end

function M.indexList(list, handSize, maxCount)
	maxCount = maxCount or M.MAX_CARDS
	if type(list) ~= "table" or not M.wholeNumber(handSize) or not M.wholeNumber(maxCount) then
		return false
	end
	local keys = 0
	for _ in pairs(list) do
		keys = keys + 1
		if keys > maxCount then
			return false
		end
	end
	if keys < 1 then
		return false
	end
	local seen = {}
	for i = 1, keys do
		local v = rawget(list, i)
		if not M.wholeNumber(v) or v < 1 or v > handSize or seen[v] then
			return false -- a hole (nil), a non-number, out of range or a repeat
		end
		seen[v] = true
	end
	return true
end

return M
