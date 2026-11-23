--[[
	Engine/ChoiceRuleFit.lua
	The rule text block on a Reward / pick card (Client/ChoicePanel) must end above the Choose plate.
	boxHeight(cardH, btnH, top)  -> height of the text box: from `top` down to 8 px above the Choose plate
	textSize(boxH, boxW, lines, gap) -> largest size from 16 down to 12 whose wrapped lines fit boxH (estimate, 0.56 em per glyph)
]]
local M = {}

M.BOTTOM_MARGIN = 10 -- the Choose plate's gap to the card bottom (ChoicePanel)
M.PLATE_GAP = 8
M.SIZES = { 16, 15, 14, 13, 12 }

function M.boxHeight(cardH, btnH, top)
	return math.max(20, cardH - (btnH + M.BOTTOM_MARGIN) - M.PLATE_GAP - top)
end

function M.neededHeight(size, boxW, lines, gap)
	local total, n = 0, 0
	for _, text in ipairs(lines) do
		if type(text) == "string" and text ~= "" then
			local rows = math.max(1, math.ceil(#text * size * 0.56 / math.max(1, boxW)))
			total = total + rows * math.ceil(size * 1.2)
			n = n + 1
		end
	end
	if n > 1 then total = total + (n - 1) * (gap or 4) end
	return total
end

function M.textSize(boxH, boxW, lines, gap)
	for _, size in ipairs(M.SIZES) do
		if M.neededHeight(size, boxW, lines, gap) <= boxH then return size end
	end
	return M.SIZES[#M.SIZES]
end

return M
