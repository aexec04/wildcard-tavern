--[[
	Shared/Engine/BoonPickLook.lua
	Pure numbers for the Night boon pick cards (Client/ChoicePanel.lua, choice kind "boon"): the Choose plate stays 44 px on screen at
	every window size, the picked card reads "Chosen" with a thick set accent edge while the others dim, and Escape can never skip the pick.
	  BoonPickLook.scale(w, h)         the ChoicePanel fit scale (same formula as ChoicePanel.fit)
	  BoonPickLook.buttonHeight(scale) design px so the Choose plate is at least 44 px on screen (capped so it fits under the rule text)
	  BoonPickLook.rowFits(w, h)       three cards and their gaps fit the window
	  BoonPickLook.chosen(pickedId, optionId)  -> "none" | "chosen" | "dimmed"
]]

local BoonPickLook = {}

BoonPickLook.CARD_W, BoonPickLook.CARD_H = 230, 300
BoonPickLook.TAP_MIN = 44
BoonPickLook.BUTTON_MAX = 56 -- short windows scale the panel to about 0.84: 56 design px is still 44 on screen
BoonPickLook.CHOSEN_TEXT = "Chosen"
BoonPickLook.CHOSEN_EDGE = 4
BoonPickLook.DIM_TRANSPARENCY = 0.45

function BoonPickLook.scale(w, h)
	local s = math.min(w / (BoonPickLook.CARD_W * 3 + 100), h / (BoonPickLook.CARD_H + 190))
	return math.max(0.5, math.min(1.2, s))
end

function BoonPickLook.buttonHeight(scale)
	local need = math.ceil(BoonPickLook.TAP_MIN / math.max(scale, 0.01))
	return math.max(BoonPickLook.TAP_MIN, math.min(BoonPickLook.BUTTON_MAX, need))
end

function BoonPickLook.rowFits(w, h)
	local s = BoonPickLook.scale(w, h)
	return (BoonPickLook.CARD_W * 3 + 44) * s <= w and (BoonPickLook.CARD_H + 164) * s <= h
end

function BoonPickLook.chosen(pickedId, optionId)
	if pickedId == nil then return "none" end
	return pickedId == optionId and "chosen" or "dimmed"
end

return BoonPickLook
