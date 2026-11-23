--[[
	Engine/CollectionTextFit.lua
	Pure sizes for the words on the Collection screen, built on Engine/TextFit, so no tab label, rarity word, page word or count line
	touches the edge of its plate (TextFit.SIDE = 12 px of clear space each side). Client/Collection and Client/CollectionSection apply
	these numbers; the tests check the same functions at four screen sizes.

	M.tabWidth(text, size)              plate width for a tab label: text width plus a 12 px side each way, never under MIN_TAB_W
	M.plateSize(text, plateW, plateH)   largest size in 12..16 that fits one plate (page word, count pill), or 12
	M.linesSize(lines, w)               one size (12..16) at which every line fits one row of width w, or 12
	M.chipSize(words, rowW)             one size (12..15) at which all rarity words and their swatches fit rowW in one row, or 12
]]
local TextFit = require(script.Parent:WaitForChild("TextFit"))

local M = {}

M.MIN_TAB_W = 96
M.MIN_SIZE, M.MAX_SIZE = 12, 16
M.SWATCH = 22 -- the 16 px swatch plus 6 px before the word
M.CHIP_GAP = 14

function M.tabWidth(text, size)
	return math.max(M.MIN_TAB_W, math.ceil(TextFit.width(text, size or 14)) + 2 * TextFit.SIDE)
end

function M.plateSize(text, plateW, plateH)
	return TextFit.bestSize(text, plateW - 2 * TextFit.SIDE, plateH, M.MIN_SIZE, M.MAX_SIZE) or M.MIN_SIZE
end

function M.linesSize(lines, w)
	for s = M.MAX_SIZE, M.MIN_SIZE, -1 do
		local ok = true
		for _, l in ipairs(lines) do
			if TextFit.width(l, s) > w then ok = false; break end
		end
		if ok then return s end
	end
	return M.MIN_SIZE
end

function M.chipSize(words, rowW)
	for s = 15, M.MIN_SIZE, -1 do
		local total = 0
		for _, w in ipairs(words) do total = total + M.SWATCH + TextFit.width(w, s) end
		total = total + M.CHIP_GAP * math.max(0, #words - 1)
		if total <= rowW then return s end
	end
	return M.MIN_SIZE
end

return M
