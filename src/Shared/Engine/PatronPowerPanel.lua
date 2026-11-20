--[[
	Shared/Engine/PatronPowerPanel.lua
	The Patron Power panel at the left of the table (reference 1672 x 941: x 15 to 335, y 345 to 485): a painted plate with the crown
	medallion on its left, the heading "Patron Power" and one line about the frame colours. Shown on Night 1 rounds 1 and 2 and on every
	boss round, until the first hand of the round is played or Got it is pressed. Pure Lua, display only, it never changes a run.

	PatronPowerPanel.enabledFor(state, opts) -> bool   opts = { enabled }; playing, not the tutorial, not the guided first hand, no popup
	PatronPowerPanel.place(r, viewW, viewH, avoid) -> nil | { plate = rect, button = rect, textW }   root pixels; nil when nothing fits clear
	                                                  of the table (the panel is then skipped, never overlapped)
]]

local M = {}

M.TITLE = "Patron Power"
M.BODY = "The frame shows power: Wood is Common, gold is Legendary."
M.TITLE_SIZE, M.BODY_SIZE = 22, 18
M.MAX_ROUND = 2 -- Night 1, rounds 1 and 2 (every boss round besides)
-- reference rect and the Got it plate under the text column
M.REF = { x = 15 / 1672, w = 320 / 1672, h = 140 / 941 }
M.ASPECT = 1408 / 543 -- the painted plate wh_hint
M.BUTTON_W, M.BUTTON_H = 90, 44
M.BUTTON_COL = 0.31
M.GAP = 8
M.HAND_GAP = 8 -- the panel ends this far above the hand frame, so it never touches the fan
M.MIN_W = 280

local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end

function M.enabledFor(state, opts)
	opts = opts or {}
	if opts.enabled == false then return false end
	if type(state) ~= "table" or state.phase ~= "playing" or state.isTutorial == true then return false end
	if state.choice ~= nil then return false end
	if state.guidedFirstHand == true and (tonumber(state.handsPlayedTotal) or 0) < 1 then return false end -- the guided hint owns the screen
	local early = (tonumber(state.night) or 1) == 1 and (tonumber(state.round) or 1) <= M.MAX_ROUND
	return early or state.isBossRound == true
end

-- True once a hand has been played in this round (the panel is spent). handsLeft vs the round's start is the only per round signal the
-- state keeps, so the client passes the count it saw when the round began.
function M.spent(state, handsAtRoundStart)
	return (tonumber(state and state.handsPlayedTotal) or 0) > (tonumber(handsAtRoundStart) or 0)
end

function M.place(r, viewW, viewH, avoid)
	if type(r) ~= "table" or not r.hand or not r.slots or not r.slots[1] or not r.slots[1].card then return nil end
	local x = math.floor(M.REF.x * viewW + 0.5)
	local w = math.max(M.MIN_W, math.floor(M.REF.w * viewW + 0.5)) -- 367 at 1920, the reference scaled to the live width
	w = math.min(w, r.slots[1].card.x - M.HAND_GAP - x) -- the panel ends above the hand frame, so only the first seat limits its width
	if w < M.MIN_W then return nil end
	local plateH = math.floor(w / M.ASPECT + 0.5)
	local bottom = r.hand.y - M.HAND_GAP
	local top = 0
	for _, key in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do -- under the consumables tray
		local t = r[key]
		if t then top = math.max(top, t.y + t.h + 6) end
	end
	local avail = bottom - top
	local kind
	if avail >= plateH + M.GAP + M.BUTTON_H then kind = "tall"
	elseif avail >= plateH then kind = "compact" -- no Got it plate: the whole panel is the dismiss button
	else return nil end
	local total = kind == "tall" and plateH + M.GAP + M.BUTTON_H or plateH
	local plate = { x = x, y = bottom - total, w = w, h = plateH }
	local button = kind == "tall" and { x = x + math.floor(w * M.BUTTON_COL), y = plate.y + plateH + M.GAP, w = M.BUTTON_W, h = M.BUTTON_H } or nil
	for name, rect in pairs(r) do
		if name ~= "bar" and name ~= "slots" and type(rect) == "table" and rect.x and (hit(plate, rect) or (button and hit(button, rect))) then return nil end
	end
	for _, s in ipairs(r.slots) do
		for _, part in ipairs({ s.card, s.label, s.pill }) do
			if part and (hit(plate, part) or (button and hit(button, part))) then return nil end
		end
	end
	for _, a in ipairs(avoid or {}) do
		if hit(plate, a) or (button and hit(button, a)) then return nil end
	end
	if plate.x < 0 or plate.x + plate.w > viewW or plate.y + total > viewH then return nil end
	return { plate = plate, button = button, kind = kind, textW = math.floor(w * 0.62) }
end

return M
