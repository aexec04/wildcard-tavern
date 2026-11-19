--[[
	Shared/Engine/RarityCues.lua
	Rarity is never colour alone: every tier has its word (in the label pill art) and its own small SHAPE drawn beside the word,
	so a colourblind player can tell a Rare from an Epic by outline. Pure data, no Roblox calls, tested. Client/RarityShape draws it.

	RarityCues.shape(tier) -> { name, parts = { {rot, round, size} ... } }   parts are squares (size is a fraction of the marker);
	                                                                         round = true draws a circle
	RarityCues.WORD[tier]  -> "Common" ...
	RarityCues.order       -> the five tiers, lowest first
	RarityCues.contrast(a, b) -> WCAG ratio of two {r,g,b} colours
	RarityCues.MIN_BODY, MIN_LARGE, MIN_PHONE_FONT, MIN_TOUCH
]]

local M = {}

M.order = { "common", "uncommon", "rare", "epic", "legendary" }
M.WORD = { common = "Common", uncommon = "Uncommon", rare = "Rare", epic = "Epic", legendary = "Legendary" }
M.MIN_BODY, M.MIN_LARGE = 4.5, 3
M.MIN_PHONE_FONT, M.MIN_TOUCH = 14, 44

local SHAPES = {
	common = { name = "circle", parts = { { rot = 0, round = true, size = 0.8 } } },
	uncommon = { name = "square", parts = { { rot = 0, round = false, size = 0.75 } } },
	rare = { name = "diamond", parts = { { rot = 45, round = false, size = 0.75 } } },
	epic = { name = "ringed diamond", parts = { { rot = 45, round = false, size = 0.78 }, { rot = 0, round = true, size = 0.3 } } },
	legendary = { name = "star", parts = { { rot = 0, round = false, size = 0.62 }, { rot = 45, round = false, size = 0.62 } } },
}

function M.shape(tier)
	return SHAPES[type(tier) == "string" and tier:lower() or "common"] or SHAPES.common
end

local function lum(c)
	local function f(v)
		v = v / 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
end

function M.contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

return M
