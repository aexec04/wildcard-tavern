--[[
	Shared/Engine/MapNodeRules.lua
	Pure rules for the Tavern Map node visual (Client/MapNodeKit draws it). No Roblox types.

	typeOf(kind, side, final)  -> "encounter" | "shop" | "event" | "boss"   (a Night stop is an encounter, the Finish and milestone Nights
	                              are the boss, side shops are shop, every other side stop and the Endless portal are events)
	stateOf{locked, current, completed} -> "completed" | "current" | "locked" | "available"   (selected and hover are overlays, see look())
	tagFor(type)               -> { text, color } the type tag under the name (SHOP gold, EVENT purple, BOSS red, Encounter green)
	badgeFor(type, state)      -> "check" | "coin" | "question" | "lock" | nil   the small badge top right
	look(state, selected, hover) -> { ring = {r,g,b}, thickness, glow, dim, scale }
	parts(size, labelW)        -> rects (x, y, w, h, relative to the node centre) of the ring, badge, name plate and type tag
]]

local M = {}

M.TYPES = { "encounter", "shop", "event", "boss" }

M.TAGS = {
	encounter = { text = "Encounter", color = { 120, 214, 110 } },
	shop = { text = "SHOP", color = { 255, 205, 80 } },
	event = { text = "EVENT", color = { 190, 130, 255 } },
	boss = { text = "BOSS", color = { 255, 90, 80 } },
}

function M.typeOf(kind, side, final)
	if kind == "side" then
		return side == "shop" and "shop" or "event"
	end
	if kind == "endless" then return "event" end
	if kind == "milestone" or final == true then return "boss" end
	return "encounter"
end

function M.stateOf(f)
	f = f or {}
	if f.completed then return "completed" end
	if f.locked then return "locked" end
	if f.current then return "current" end
	return "available"
end

function M.tagFor(typeId)
	return M.TAGS[typeId] or M.TAGS.encounter
end

function M.badgeFor(typeId, state)
	if state == "completed" then return "check" end
	if state == "locked" then return "lock" end
	if typeId == "shop" then return "coin" end
	if typeId == "event" then return "question" end
	return nil
end

local GOLD, BOSS_RED = { 255, 205, 90 }, { 200, 60, 50 }
local RING = {
	locked = { 110, 92, 72 }, available = { 176, 138, 66 }, current = { 255, 205, 90 }, completed = { 120, 200, 110 },
}

function M.look(state, selected, hover)
	local l = { ring = RING[state] or RING.available, thickness = 3, glow = false, dim = state == "locked", scale = 1 }
	if state == "current" then l.thickness, l.glow = 5, true end
	if state == "completed" then l.thickness = 4 end
	if selected then l.ring, l.thickness, l.glow = GOLD, 5, true end
	if hover and state ~= "locked" then l.scale = 1.06 end
	return l
end

function M.bossRing() return BOSS_RED end

-- Rects relative to the node centre. size = the circle's diameter, labelW = the name plate width.
M.NAME_H, M.TAG_H, M.GAP = 24, 20, 4
M.TAG_CLEAR = 10 -- name plate bottom to type chip top: the 2 px gap plus 8 px clearance, so a tall plate never touches the chip

function M.parts(size, labelW)
	local r = size / 2
	local badge = math.max(18, math.floor(size * 0.3))
	local bx = math.floor(r * 0.707 + badge * 0.1) -- on the ring at 45 degrees, up and right
	local name = { x = -labelW / 2, y = r + M.GAP, w = labelW, h = M.NAME_H }
	return {
		ring = { x = -r, y = -r, w = size, h = size },
		badge = { x = bx - badge / 2, y = -bx - badge / 2, w = badge, h = badge },
		name = name,
		tag = { x = -labelW / 2, y = name.y + name.h + M.TAG_CLEAR, w = labelW, h = M.TAG_H },
	}
end

return M
