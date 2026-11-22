--[[
	Shared/Engine/PatronPowerPanel.lua
	The Patron Power panel at the left of the table (reference 1672 x 941: x 15 to 335, y 345 to 485): a painted plate with the crown
	medallion on its left, the heading "Patron Power" and one line about the frame colours. Shown on Night 1 round 1 only, until the first hand of the round is played or Got it is pressed. Pure Lua, display only, it never changes a run.

	PatronPowerPanel.enabledFor(state, opts) -> bool   opts = { enabled }; playing, not the tutorial, not the guided first hand, no popup
	PatronPowerPanel.place(r, viewW, viewH, avoid) -> nil | { plate = rect, button = nil (no Got it plate of its own), textW }   root pixels; nil when nothing fits clear
	                                                  of the table (the panel is then skipped, never overlapped)
	PatronPowerPanel.handClear(viewH) -> px the panel ends above the hand frame (clears the highest left fan card, 10 cards too)
]]

local M = {}

M.TITLE = "Patron Power"
M.BODY = "The frame shows power: Wood is Common, gold is Legendary."
M.TITLE_SIZE, M.BODY_SIZE = 22, 18
M.X_CLEAR = 52 -- px the text columns keep from the right edge so the 44 px close X (inset 8) never covers them
M.MAX_ROUND = 1 -- Night 1, round 1 only: nobody needs the frame colour tip on every round
-- reference rect and the Got it plate under the text column
M.REF = { x = 15 / 1672, w = 320 / 1672, h = 140 / 941 }
M.ASPECT = 1408 / 543 -- the painted plate wh_hint
M.BUTTON_W, M.BUTTON_H = 90, 44
M.BUTTON_COL = 0.31
M.GAP = 8
M.HAND_GAP = 8 -- beside the seat column: the panel stays this far left of the first Patron seat
M.MIN_W = 280

local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end

-- nil when the panel is due, else the reason it is not (printed by the Studio [PanelCheck] line)
function M.reason(state, opts)
	opts = opts or {}
	if opts.enabled == false then return "hints off in Settings" end
	if opts.closedByX == true then return "closed with its X for this run" end
	if type(state) ~= "table" then return "no state" end
	if state.phase ~= "playing" then return "phase " .. tostring(state.phase) end
	if state.isTutorial == true then return "tutorial" end
	if state.choice ~= nil then return "a choice is open" end
	-- the guided hint owns the first hand of a run; a boss round (or any later round) is never that hand, whatever flag a jump left behind
	if state.guidedFirstHand == true and state.isBossRound ~= true and (tonumber(state.handsPlayedTotal) or 0) < 1 then return "guided first hand" end
	local early = (tonumber(state.night) or 1) == 1 and (tonumber(state.round) or 1) <= M.MAX_ROUND
	if not early then return ("night %s round %s is not Night 1 round 1"):format(tostring(state.night), tostring(state.round)) end
	return nil
end

-- A new run began when the hands played drop below what was last seen: an X pressed in the old run is forgotten.
function M.newRun(prevHands, hands)
	return (tonumber(hands) or 0) < (tonumber(prevHands) or 0)
end

function M.enabledFor(state, opts)
	return M.reason(state, opts) == nil
end

-- True once a hand has been played in this round (the panel is spent). handsLeft vs the round's start is the only per round signal the
-- state keeps, so the client passes the count it saw when the round began.
function M.spent(state, handsAtRoundStart)
	return (tonumber(state and state.handsPlayedTotal) or 0) > (tonumber(handsAtRoundStart) or 0)
end

-- The fan's highest left card stands about 16 px (at 957 tall) above the hand frame; the panel keeps 12 px clear of that.
function M.handClear(viewH) return 12 + math.floor(0.025 * viewH + 0.5) end

-- One try: the panel ends at `bottom`, nothing above `top`. Returns the spot, or nil when it would overlap a plate.
local function try(r, viewW, viewH, avoid, x, w0, bottom, top)
	local w = w0
	local avail = bottom - top
	if avail < math.floor(w / M.ASPECT + 0.5) then -- a short column: narrow the plate (down to MIN_W) so it still fits
		w = math.max(M.MIN_W, math.min(w, math.floor(avail * M.ASPECT)))
	end
	local plateH = math.floor(w / M.ASPECT + 0.5)
	if avail < plateH then return nil end
	local kind = "compact" -- no Got it plate of its own: the Got it on the hint strip and a tap on the panel both dismiss it
	local plate = { x = x, y = bottom - plateH, w = w, h = plateH }
	local button = nil
	for name, rect in pairs(r) do
		if name ~= "bar" and name ~= "slots" and type(rect) == "table" and rect.x and (hit(plate, rect) or (button and hit(button, rect))) then return nil end
	end
	for _, s in ipairs(r.slots) do
		for _, part in ipairs({ s.card, s.label, s.pill }) do
			if part and (hit(plate, part) or (button and hit(button, part))) then return nil end
		end
	end
	for _, a in ipairs(avoid) do
		if hit(plate, a) or (button and hit(button, a)) then return nil end
	end
	if plate.x < 0 or plate.x + plate.w > viewW or plate.y < 0 or plate.y + plateH > viewH then return nil end
	return { plate = plate, button = button, kind = kind, textW = math.floor(w * 0.62) }
end

function M.place(r, viewW, viewH, avoid)
	if type(r) ~= "table" or not r.hand or not r.slots or not r.slots[1] or not r.slots[1].card then return nil end
	avoid = avoid or {}
	local x = math.floor(M.REF.x * viewW + 0.5)
	local w = math.max(M.MIN_W, math.floor(M.REF.w * viewW + 0.5)) -- 367 at 1920, the reference scaled to the live width
	w = math.min(w, r.slots[1].card.x - M.HAND_GAP - x) -- only the first seat limits its width
	if w < M.MIN_W then return nil end
	local bottom = r.hand.y - M.handClear(viewH)
	local top = 0
	for _, key in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do -- under the consumables tray
		local t = r[key]
		if t then top = math.max(top, t.y + t.h + 6) end
	end
	-- a plate in the left column (the boss rule plate): try under it first, then above it
	local below, above = top, nil
	for _, a in ipairs(avoid) do
		if a.x < x + w and x < a.x + a.w and a.y < bottom then
			below = math.max(below, a.y + a.h + 6)
			above = math.min(above or (a.y - 6), a.y - 6)
		end
	end
	local spot = try(r, viewW, viewH, avoid, x, w, bottom, below)
	if not spot and above then spot = try(r, viewW, viewH, avoid, x, w, above, top) end
	return spot
end

return M
