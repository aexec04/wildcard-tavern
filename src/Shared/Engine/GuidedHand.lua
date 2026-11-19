--[[
	Shared/Engine/GuidedHand.lua
	The short guided first hand (Backlog 8, option b). A brand new profile's first normal run starts with one fixed starter
	Patron and no blessing draft, and the play screen shows a two line hint that points at one card, then at Play Hand, until
	the first hand is played. The 24 step tutorial is separate and untouched.

	GuidedHand.STARTER                   id of the fixed starter Patron
	GuidedHand.isGuided(runsStarted, seeded, rush, tutorial) -> bool   true only for the first normal run of a profile
	GuidedHand.apply(state) -> ok        seats the starter Patron (RunState.grantPatron), nothing else
	GuidedHand.plateRect(r, viewH) -> { x, y, w, h }   where the hint plate stands (Concept T rects): in the stage band, never over the
	    Patron pills above it or the hand below it, centred on the stage
	GuidedHand.hint(guided, handsPlayed, selectedCount, calm) -> nil | { line1, line2, target = "card" | "play", cards = 2 (card step), pulse }
	GuidedHand.skipRect(plate, viewW) -> { x, y, w, h }   the small Skip plate beside the hint plate, 44 px tall, on screen
]]

local M = {}

M.STARTER = "the_regular" -- +4 Mult on every hand, easy to read, painted card exists

function M.isGuided(runsStarted, seeded, rush, tutorial)
	if seeded or rush or tutorial then return false end
	return type(runsStarted) == "number" and runsStarted <= 1
end

function M.apply(state)
	local RunState = require(script.Parent.RunState)
	local ok = RunState.grantPatron(state, M.STARTER)
	if ok then state.startPatronId = M.STARTER end
	return ok
end

function M.hint(guided, handsPlayed, selectedCount, calm)
	if not guided or (tonumber(handsPlayed) or 0) >= 1 then return nil end
	if (tonumber(selectedCount) or 0) < 2 then
		return { line1 = "Tap two cards to pick them.", line2 = "You can pick up to five.", target = "card", cards = 2, pulse = not calm }
	end
	return { line1 = "Play your hand", line2 = "Your best hand scores.", target = "play", pulse = not calm }
end

M.TEXT = { 255, 244, 214 } -- line 1, on the dark plate
M.TEXT2 = { 235, 218, 180 } -- line 2
M.PLATE = { 46, 28, 14 }

function M.plateRect(r, viewH)
	local st = r.stage
	local w, h = math.max(220, math.floor(st.w * 0.8)), math.max(52, math.floor(st.h * 0.45))
	local top = math.floor(viewH * 0.495) + 4 -- under the effect pills of the Patron row
	if r.slots and r.slots[1] and r.slots[1].pill then -- Gameplay v2: under the pill row of the five seats
		local pill = r.slots[1].pill
		top = pill.y + pill.h + 2
	end
	local bottom = r.hand.y - 6
	local y = st.y
	if y + h > bottom then y = bottom - h end
	if y < top then
		y = top
		h = math.max(24, math.min(h, bottom - top))
	end
	return { x = st.x + math.floor((st.w - w) / 2), y = y, w = w, h = h }
end

M.SKIP_W, M.SKIP_H = 72, 44

function M.skipRect(p, viewW)
	local x = p.x + p.w + 6
	if x + M.SKIP_W > viewW then x = viewW - M.SKIP_W end -- no room beside the plate: hang on its right end, on screen
	return { x = x, y = p.y + math.floor((p.h - M.SKIP_H) / 2), w = M.SKIP_W, h = M.SKIP_H }
end

return M
