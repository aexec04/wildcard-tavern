--[[
	Shared/Engine/MapSelectRules.lua
	Pure rules for the Tavern Map's selected-location panel (lower left, Client/MapSelectPanel draws it) and for the dashed routes. No Roblox types.

	canSelect(state)                    -> false for a locked node (locked nodes cannot be selected)
	describe(node)                      -> { name, typeId, typeText, typeIcon, line, target (nil when it does not apply), button = { text, enabled, visible }, status }
	                                       node = { name, description, typeId, state, target, final }
	rects(zone, mode)                   -> { art, name, type, line, target, button, w, h } inside zone = { x, y, w, h } (relative to the zone's top left)
	                                       mode "full" | "compact" | "tab"; rects never overlap each other
	pickMode(zone, boxes)               -> the first mode ("full", "compact", "tab") whose panel does not overlap any box (screen rects)
	panelRect(zone, mode)               -> the screen rect the panel takes in that mode (a bottom aligned part of the zone)
	targetFor(night, currentNight, round, roundTargets, calc) -> the Target the panel shows for a Night node
	dashOn(k, on, off)                  -> true when piece k (1 based) of a dashed route is drawn
	routeLook(selectedInto, filled)     -> { color, edge, thickness } of a dashed route piece
]]

local TypeRules = require(script.Parent.MapNodeRules)

local M = {}

M.TYPE_ICON = { encounter = "\u{2694}", shop = "\u{1FA99}", event = "?", boss = "\u{1F451}" }
M.TYPE_WORD = { encounter = "Encounter", shop = "Shop", event = "Event", boss = "Boss" }
M.PAD = 16 -- clear inner padding: text never reaches the gold trim

function M.canSelect(state)
	return state ~= "locked"
end

function M.describe(node)
	local typeId = node.typeId or "encounter"
	local out = {
		name = node.name or "",
		typeId = typeId,
		typeText = M.TYPE_WORD[typeId] or "Encounter",
		typeIcon = M.TYPE_ICON[typeId] or M.TYPE_ICON.encounter,
		line = node.description or "",
		target = nil,
		button = { text = "Continue", enabled = true, visible = true },
		status = nil,
	}
	if typeId == "encounter" or typeId == "boss" then
		out.target = node.target -- only fights have a Target score
	end
	if node.state == "completed" then
		out.button = { text = "Continue", enabled = false, visible = false }
		out.status = "Completed"
	elseif node.state == "locked" then
		out.button = { text = "Locked", enabled = false, visible = true }
		out.status = "Locked"
	end
	return out
end

-- The node the panel shows when the map opens: the current one when it can be selected, else the first enterable one, else the
-- first node at all (never nil while the map has nodes, so the panel is never empty). states = list of node states by index.
function M.openSelection(currentIndex, states)
	if currentIndex and states[currentIndex] and M.canSelect(states[currentIndex]) then return currentIndex end
	for i = 1, #states do
		if states[i] ~= "locked" then return i end
	end
	return #states > 0 and 1 or nil
end

-- True when a rect is fully on screen with a real size (the panel must pass this after it opens).
function M.onScreen(r, sw, sh)
	return r.w > 0 and r.h > 0 and r.x >= 0 and r.y >= 0 and r.x + r.w <= sw and r.y + r.h <= sh
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Heights of the three modes: full = the whole zone, compact = name + Continue only, tab = one small plate with the name.
M.COMPACT_H, M.TAB_H = 56, 36

function M.panelRect(zone, mode)
	local h = zone.h
	if mode == "compact" then h = math.min(zone.h, M.COMPACT_H) end
	if mode == "tab" then h = math.min(zone.h, M.TAB_H) end
	local w = mode == "tab" and math.min(zone.w, 200) or zone.w
	return { x = zone.x, y = zone.y + zone.h - h, w = w, h = h }
end

function M.rects(zone, mode)
	mode = mode or "full"
	local pad = M.PAD
	local r = M.panelRect(zone, mode)
	local py = r.h < 170 and 8 or pad -- sides keep the full clear padding; a short panel trades vertical padding for the two line description
	local out = { w = r.w, h = r.h }
	if mode == "tab" then
		out.name = { x = pad, y = 0, w = r.w - pad * 2, h = r.h }
		return out
	end
	if mode == "compact" then
		local bw = clamp(math.floor(r.w * 0.34), 96, 150)
		out.name = { x = pad, y = py, w = r.w - bw - pad * 3, h = r.h - py * 2 }
		out.button = { x = r.w - bw - pad, y = py, w = bw, h = r.h - py * 2 }
		return out
	end
	local compact = r.h < 170
	local art = math.min(r.h - py * 2, math.floor(r.w * 0.34))
	out.art = { x = pad, y = py, w = art, h = art }
	local tx = pad * 2 + art
	local tw = r.w - tx - pad
	local nameH, typeH, lineH, targetH, buttonH = 24, 20, compact and 32 or 36, 20, compact and 28 or 36
	local y = py
	if compact then
		-- short panel: the type and the Target share one row, so the description keeps two full lines
		nameH, typeH = 22, 18
		out.name = { x = tx, y = y, w = tw, h = nameH }
		y = y + nameH
		local half = math.floor(tw / 2)
		out.type = { x = tx, y = y, w = half, h = typeH }
		out.target = { x = tx + half, y = y, w = tw - half, h = typeH }
		y = y + typeH
		out.line = { x = tx, y = y, w = tw, h = lineH }
		out.button = { x = tx, y = r.h - py - buttonH, w = math.min(tw, 190), h = buttonH }
		return out
	end
	out.name = { x = tx, y = y, w = tw, h = nameH }
	y = y + nameH
	out.type = { x = tx, y = y, w = tw, h = typeH }
	y = y + typeH
	out.line = { x = tx, y = y, w = tw, h = lineH }
	y = y + lineH
	out.target = { x = tx, y = y, w = tw, h = targetH }
	out.button = { x = tx, y = r.h - py - buttonH, w = math.min(tw, 190), h = buttonH }
	return out
end

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function M.pickMode(zone, boxes)
	for _, mode in ipairs({ "full", "compact", "tab" }) do
		local r = M.panelRect(zone, mode)
		local clear = true
		for _, b in ipairs(boxes or {}) do
			if overlaps(r, b) then clear = false break end
		end
		if clear then return mode end
	end
	return "tab"
end

-- The Target a Night's panel shows: the current Night uses the server's number for the round being played (the table's own),
-- any other Night its first round (a Night is entered at round 1). calc(night, round) is RunState.targetScoreFor.
function M.targetFor(night, currentNight, round, roundTargets, calc)
	if night == currentNight and type(roundTargets) == "table" then
		local t = tonumber(roundTargets[round or 1])
		if t then return math.floor(t) end
	end
	return calc(night, 1, 3)
end

function M.dashOn(k, on, off)
	on, off = on or 4, off or 3
	return ((k - 1) % (on + off)) < on
end

-- cream dashes; the route into the selected node is warmer and thicker; a travelled route is brighter
function M.routeLook(selectedInto, filled)
	if selectedInto then return { color = { 255, 214, 120 }, edge = { 150, 100, 30 }, thickness = 14 } end
	if filled then return { color = { 255, 246, 220 }, edge = { 110, 78, 40 }, thickness = 12 } end
	return { color = { 244, 230, 196 }, edge = { 110, 78, 40 }, thickness = 10 }
end

M.typeOf = TypeRules.typeOf

return M
