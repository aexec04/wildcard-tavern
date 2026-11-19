--[[
	Engine/RoadSkin.lua
	Tested numbers for the Concept T look of the Choose your road cards: a dark wood card, one dark text plate
	(alpha 0.92 or more, gold 1 px stroke) behind every text block, cream serif title, one button style (the
	green plate). Pure math, no Roblox calls. Client/RoadChoice applies it.
]]
local RoadSkin = {}

RoadSkin.CARD = { 58, 40, 26 }
RoadSkin.PLATE = { 34, 24, 16 }
RoadSkin.PLATE_TRANSPARENCY = 0.08 -- alpha 0.92
RoadSkin.GOLD = { 222, 182, 104 }
RoadSkin.TEXT = { 250, 238, 212 }
RoadSkin.SUBTEXT = { 235, 218, 180 }
RoadSkin.REWARD = { 255, 214, 130 }
RoadSkin.MIN_TEXT = 15
RoadSkin.BUTTON_STYLES = 1 -- Take this road, Decide later and Use compass all wear the green plate
RoadSkin.LOCKED_TINT = { 200, 160, 110 }

-- Rects inside a card of w x h (offsets). Strip on top, one text plate under it, the button at the bottom.
function RoadSkin.cardLayout(w, h)
	local pad = 8
	local strip = { x = pad, y = pad, w = w - 2 * pad, h = 112 }
	local button = { x = pad, y = h - pad - 44, w = w - 2 * pad, h = 44 }
	local plateY = strip.y + strip.h + 6
	local plate = { x = pad, y = plateY, w = w - 2 * pad, h = button.y - 6 - plateY }
	local inner = 8
	local rows = {
		name = { x = plate.x + inner, y = plate.y + 4, w = plate.w - 2 * inner, h = 24 },
		region = { x = plate.x + inner, y = plate.y + 28, w = plate.w - 2 * inner, h = 20 },
		hint = { x = plate.x + inner, y = plate.y + 50, w = plate.w - 2 * inner, h = 40 },
	}
	rows.reward = { x = plate.x + inner, y = plate.y + 92, w = plate.w - 2 * inner, h = math.max(0, plate.y + plate.h - 4 - (plate.y + 92)) }
	return { strip = strip, plate = plate, button = button, rows = rows }
end

return RoadSkin
