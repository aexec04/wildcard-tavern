--[[
	Engine/PatronValueText.lua
	The short effect value shown under a Patron's portrait ("+4 Mult", "+15 Chips", "x1.5 Mult", "+4 Tips"),
	read from the Patron's real description text, never invented. Nil when the description has no leading figure.

	PatronValueText.of(description) -> string | nil
	PatronValueText.visible(cardW)  -> bool   (a 15 px value needs a card at least MIN_W wide)
]]

local M = {}

M.MIN_W = 84 -- same floor as the name plaque: narrower cards show no value

local UNITS = {
	mult = "Mult", chips = "Chips", chip = "Chips", tips = "Tips", tip = "Tips",
	discard = "Discard", discards = "Discards", hand = "Hand", hands = "Hands", -- Second Helpings, Overtime
}

function M.of(description)
	if type(description) ~= "string" then return nil end
	-- "+4 Mult", "+15 Chips"
	local sign, num, unit = description:match("([%+%-])(%d+%.?%d*)%s+(%a+)")
	if sign and UNITS[unit:lower()] then return sign .. num .. " " .. UNITS[unit:lower()] end
	-- "x1.5 Mult", "Mult x1.5"
	local x = description:match("[xX](%d+%.?%d*)%s+Mult") or description:match("Mult%s+[xX](%d+%.?%d*)")
	if x then return "x" .. x .. " Mult" end
	-- "Earn 4 Tips ...", "Earn 1 Tip for each ...", "... earn 1 Tip per 4 held"
	local earn = description:match("[Ee]arn%s+(%d+)%s+Tips?")
	if earn then return "+" .. earn .. (earn == "1" and " Tip" or " Tips") end
	-- "Draw 1 more card ..."
	local draw = description:match("Draw%s+(%d+)%s+more%s+cards?")
	if draw then return "+" .. draw .. (draw == "1" and " Card" or " Cards") end
	return nil
end

function M.visible(cardW)
	return (tonumber(cardW) or 0) >= M.MIN_W
end

return M
