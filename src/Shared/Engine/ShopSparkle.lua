--[[
	Shared/Engine/ShopSparkle.lua
	Pure rules (tested) for the little sparkle a Rare or better shop offer gives when it appears on the shelf.

	  ShopSparkle.spec(rarity, calm) -> nil | { count, color = {r,g,b}, spread, duration }
	      nil for Common, Uncommon, unknown tiers and in calm mode; more pieces for higher tiers
	  ShopSparkle.shouldPlay(last, key, now) -> bool   one sparkle per offer per 30 s, so a shelf redraw does not repeat it;
	      records `now` in `last[key]` when it returns true
]]

local M = {}

M.WINDOW = 30
M.TIERS = {
	rare = { count = 10, color = { 90, 170, 255 } },
	epic = { count = 14, color = { 190, 120, 255 } },
	legendary = { count = 20, color = { 255, 205, 70 } },
	mythical = { count = 20, color = { 255, 120, 200 } },
}

function M.spec(rarity, calm)
	if calm then return nil end
	local t = M.TIERS[tostring(rarity or ""):lower()]
	if not t then return nil end
	return { count = t.count, color = { t.color[1], t.color[2], t.color[3] }, spread = 70, duration = 0.6 }
end

function M.shouldPlay(last, key, now)
	if key == nil then return false end
	local prev = last[key]
	if prev ~= nil and now - prev < M.WINDOW then return false end
	last[key] = now
	return true
end

return M
