--[[
	BossRuleGlyphs.lua
	Drawn icons (shapes, no emoji, no picture) for the boss rule chip, as data so a test can hold every shape inside the icon square
	and every colour to 7:1 on the dark icon plate. Pure Lua, no Roblox APIs. Static, so Calm mode and Reduce motion need nothing.
	Keyed by boss id (the three Nights 7 to 12 rules); any other boss keeps its letter icon from Gameplay2Moments.ICONS.

	BossRuleGlyphs.get(bossId) -> { shapes = { { kind = "rect"|"round", x, y, w, h (0..1 of the icon square), rot (degrees), color } } } or nil
	BossRuleGlyphs.PLATE   the dark plate colour behind every glyph
	BossRuleGlyphs.MIN_CONTRAST   7
]]

local G = {}

G.PLATE = { 36, 24, 16 }
G.MIN_CONTRAST = 7

local CREAM = { 255, 244, 222 }
local ICE = { 190, 232, 255 }
local CORAL = { 255, 150, 130 }

local DATA = {
	-- Frozen Hand: a snowflake (three crossing bars and a centre dot)
	frozen_hand = { shapes = {
		{ kind = "rect", x = 0.43, y = 0.08, w = 0.14, h = 0.84, rot = 0, color = ICE },
		{ kind = "rect", x = 0.43, y = 0.08, w = 0.14, h = 0.84, rot = 60, color = ICE },
		{ kind = "rect", x = 0.43, y = 0.08, w = 0.14, h = 0.84, rot = -60, color = ICE },
		{ kind = "round", x = 0.36, y = 0.36, w = 0.28, h = 0.28, rot = 0, color = CREAM },
	} },
	-- Quiet Tavern: a bell with a slash through it
	quiet_tavern = { shapes = {
		{ kind = "round", x = 0.24, y = 0.12, w = 0.52, h = 0.5, rot = 0, color = CREAM },
		{ kind = "rect", x = 0.14, y = 0.5, w = 0.72, h = 0.16, rot = 0, color = CREAM },
		{ kind = "round", x = 0.42, y = 0.7, w = 0.16, h = 0.16, rot = 0, color = CREAM },
		{ kind = "rect", x = 0.44, y = 0.04, w = 0.12, h = 0.92, rot = 45, color = CORAL },
	} },
	-- Short Table: a wide tabletop on two short legs, plus a small coral stool with a slash (the seat that sits out)
	short_table = { shapes = {
		{ kind = "rect", x = 0.05, y = 0.34, w = 0.58, h = 0.13, rot = 0, color = CREAM },
		{ kind = "rect", x = 0.10, y = 0.47, w = 0.09, h = 0.30, rot = 0, color = CREAM },
		{ kind = "rect", x = 0.49, y = 0.47, w = 0.09, h = 0.30, rot = 0, color = CREAM },
		{ kind = "round", x = 0.73, y = 0.46, w = 0.22, h = 0.12, rot = 0, color = CORAL },
		{ kind = "rect", x = 0.80, y = 0.58, w = 0.08, h = 0.20, rot = 0, color = CORAL },
		{ kind = "rect", x = 0.80, y = 0.34, w = 0.08, h = 0.36, rot = 45, color = CREAM },
	} },
}

function G.get(bossId)
	return type(bossId) == "string" and DATA[bossId] or nil
end

function G.ids()
	local out = {}
	for id in pairs(DATA) do out[#out + 1] = id end
	table.sort(out)
	return out
end

return G
