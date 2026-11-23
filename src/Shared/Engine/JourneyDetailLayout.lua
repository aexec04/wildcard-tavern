--[[
	Engine/JourneyDetailLayout.lua
	The rewards card of a Tavern Map stop (Client/JourneyMapView "NodeDetail"): one card per stop. Every text row gets its own band and
	the Equip button and the reward picture each get a row or column of their own, so no text sits under a button or a picture.
	Pure and tested.

	size()                  -> w, h of the card
	rects(w)                -> { icon, name, boss, desc, reward, how, swatch, equip, close }  { x, y, w, h } in card pixels
	showBossLine(ntype)     -> true only on a real boss stop
]]

local M = {}

M.W = 400
M.H = 208
M.PAD = 10
M.SWATCH_W, M.SWATCH_H = 46, 64

function M.size() return M.W, M.H end

function M.showBossLine(ntype) return ntype == "boss" end

function M.rects(w)
	w = w or M.W
	local p = M.PAD
	local right = w - (M.SWATCH_W + 24) -- text beside the picture stops left of it, full width where there is no picture
	return {
		icon = { x = p, y = 8, w = 40, h = 40 },
		name = { x = 54, y = 8, w = w - 54 - 44, h = 22 }, -- clear of the close button
		boss = { x = 54, y = 28, w = w - 54 - 44, h = 18 },
		desc = { x = p, y = 50, w = w - 2 * p, h = 36 },
		reward = { x = p, y = 88, w = right - p, h = 40 },
		how = { x = p, y = 130, w = right - p, h = 36 },
		swatch = { x = w - 12 - M.SWATCH_W, y = 90, w = M.SWATCH_W, h = M.SWATCH_H },
		equip = { x = p, y = M.H - 10 - 30, w = 110, h = 30 }, -- its own row under every text
		close = { x = w - 8 - 28, y = 8, w = 28, h = 28 },
	}
end

return M
