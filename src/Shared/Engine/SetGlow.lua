--[[
	Shared/Engine/SetGlow.lua
	The one-time glow on the Patron seats when a set bonus forms (Engine/SetBonuses): the two or more seats of the set wear a ring
	in the set's accent for a moment. Pure and tested; Client/SetGlowFX draws it. Static frames, no tween, so Calm is the same.

	SetGlow.DURATION            seconds the ring stays
	SetGlow.ACCENTS[setId]      { r, g, b } light accents, each 4.5:1 or better against the dark table
	SetGlow.accent(setId)       the accent (gold when the set is unknown)
	SetGlow.key(set)            "rare_court:1,2,3" identity of a formed set
	SetGlow.fresh(known, ownedIds) -> array of newly formed sets; `known` (a table kept by the caller) is updated so each set glows once,
	                              and a set that breaks is forgotten so re-forming it glows again
	SetGlow.rings(rects, set)   one { x, y, w, h } per member seat, outset 4 px around the seat card
	SetGlow.contrast(rgb)       contrast ratio against SetGlow.TABLE
]]

local SetBonuses = require(script.Parent.SetBonuses)

local M = {}

M.DURATION = 2.4
M.OUTSET = 4
M.TABLE = { 30, 20, 14 }
M.ACCENTS = {
	tavern_circle = { 246, 196, 70 },
	rare_court = { 206, 168, 255 },
	full_table = { 124, 232, 176 },
}

function M.accent(setId)
	return M.ACCENTS[setId] or M.ACCENTS.tavern_circle
end

local function lum(c)
	local function f(v)
		v = v / 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
end

function M.contrast(c)
	local a, b = lum(c), lum(M.TABLE)
	if a < b then a, b = b, a end
	return (a + 0.05) / (b + 0.05)
end

function M.key(set)
	local seats = {}
	for i, s in ipairs(set.members or {}) do seats[i] = tostring(s) end
	return tostring(set.id) .. ":" .. table.concat(seats, ",")
end

function M.fresh(known, ownedIds)
	local sets = SetBonuses.formed(ownedIds or {})
	local now, out = {}, {}
	for _, set in ipairs(sets) do
		local k = M.key(set)
		now[k] = true
		if not known[k] then
			known[k] = true
			out[#out + 1] = set
		end
	end
	for k in pairs(known) do
		if not now[k] then known[k] = nil end
	end
	return out
end

function M.rings(rects, set)
	local out = {}
	for _, seat in ipairs(set.members or {}) do
		local slot = rects and rects.slots and rects.slots[seat]
		local c = slot and slot.card
		if c then
			out[#out + 1] = { x = c.x - M.OUTSET, y = c.y - M.OUTSET, w = c.w + 2 * M.OUTSET, h = c.h + 2 * M.OUTSET }
		end
	end
	return out
end

return M
