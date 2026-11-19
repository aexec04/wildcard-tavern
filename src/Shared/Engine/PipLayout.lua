--[[
	Shared/Engine/PipLayout.lua
	Pure pip positions for number cards on the Concept T parchment face (the reference hand shows real pip layouts, not one
	symbol). pips(rankText) -> list of { x, y, big } as card fractions (centre anchored), nil for a card that is not a number
	card (court cards use their painted figure, the Ace is one big pip). Pips stay clear of the corner index (x 0.34 to 0.66).
]]
local PipLayout = {}

PipLayout.SIZE = { w = 0.26, h = 0.19 } -- one pip, card fractions
PipLayout.BIG = { w = 0.50, h = 0.36 } -- the Ace

local L, C, R = 0.34, 0.5, 0.66
local T, B = 0.20, 0.80
local function row(f) return T + (B - T) * f end

local LAYOUTS = {
	["2"] = { { C, T }, { C, B } },
	["3"] = { { C, T }, { C, row(0.5) }, { C, B } },
	["4"] = { { L, T }, { R, T }, { L, B }, { R, B } },
	["5"] = { { L, T }, { R, T }, { C, row(0.5) }, { L, B }, { R, B } },
	["6"] = { { L, T }, { R, T }, { L, row(0.5) }, { R, row(0.5) }, { L, B }, { R, B } },
	["7"] = { { L, T }, { R, T }, { C, row(0.25) }, { L, row(0.5) }, { R, row(0.5) }, { L, B }, { R, B } },
	["8"] = { { L, T }, { R, T }, { C, row(0.25) }, { L, row(0.5) }, { R, row(0.5) }, { C, row(0.75) }, { L, B }, { R, B } },
	["9"] = { { L, T }, { R, T }, { L, row(1 / 3) }, { R, row(1 / 3) }, { C, row(0.5) }, { L, row(2 / 3) }, { R, row(2 / 3) }, { L, B }, { R, B } },
	["10"] = { { L, T }, { R, T }, { C, row(1 / 6) }, { L, row(1 / 3) }, { R, row(1 / 3) }, { L, row(2 / 3) }, { R, row(2 / 3) }, { C, row(5 / 6) }, { L, B }, { R, B } },
}

function PipLayout.pips(rankText)
	if rankText == "A" then return { { x = 0.5, y = 0.58, big = true } } end
	local src = LAYOUTS[tostring(rankText)]
	if not src then return nil end
	local out = {}
	for i, p in ipairs(src) do out[i] = { x = p[1], y = p[2], big = false } end
	return out
end

return PipLayout
