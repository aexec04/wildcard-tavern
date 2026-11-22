--[[
	Engine/HandReadout.lua
	The short line above the Play Hand button while cards are selected: best hand name and its base Chips x Mult at the run's
	level for that hand, for example "Pair, 10 x 2". Pure, no Roblox APIs. The card and Patron bonuses stay in the live preview
	over the Score plate; this line is the quick "what hand is this" read.

	line(name, handLevels) -> string or nil    nil when there is no hand name (nothing selected)
]]

local Scoring = require(script.Parent.Scoring)

local HandReadout = {}

HandReadout.TEXT_SIZE = 16

function HandReadout.values(name, handLevels)
	local base = Scoring.HandBase[name]
	if not base then return nil end
	local growth = Scoring.HandLevelGrowth[name] or { chips = 0, mult = 0 }
	local level = math.max(0, math.floor(tonumber(handLevels and handLevels[name]) or 0))
	return math.floor(base.chips + growth.chips * level), math.floor(base.mult + growth.mult * level)
end

function HandReadout.line(name, handLevels)
	if type(name) ~= "string" then return nil end
	local chips, mult = HandReadout.values(name, handLevels)
	if not chips then return nil end
	return string.format("%s, %d x %d", name, chips, mult)
end

return HandReadout
