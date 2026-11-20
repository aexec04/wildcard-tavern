--[[
	Shared/Engine/RoundHints.lua
	The hint layer for the first three rounds of Night 1 (after the guided first hand). Three short plates, one at a time, each
	dismissible and shown once per profile (profile.hintsSeen, ids registered in Engine/Hints): pick cards, Patron power tiers,
	what Target means. Pure Lua, no Roblox APIs. Display only: it never changes a run.

	RoundHints.ORDER                      list of { id, title, body }
	RoundHints.enabledFor(state, opts)    -> bool   the whole layer is on for this state (Night 1, rounds 1 to 3, playing, not Calm,
	                                      Hints toggle on, Night 1 not cleared before, tutorial and guided first hand excluded)
	RoundHints.next(state, seen, opts)    -> nil | entry   first unseen entry whose own condition holds; opts = { enabled, calm }
	RoundHints.expired(id, state) -> bool    the plate is spent for good (pick cards: any hand was played); it hides and is marked seen
	RoundHints.satisfied(id, selectedCount) -> bool   the plate has done its job (pick cards: one card is selected)
	RoundHints.place(r, viewW, viewH)     -> nil | { plate, button }   root pixel rects in the open middle beside the score stage,
	                                      clear of every table rect (nil when nothing fits: the hint is then skipped, never overlapped)
]]

local M = {}

M.ORDER = {
	{ id = "round_hint_select", title = "Pick your cards", body = "Tap up to five cards, then press Play Hand." },
	{ id = "round_hint_tiers", title = "Patron Power", body = "Wood frames are Common, gold are Legendary." },
	{ id = "round_hint_target", title = "What is Target?", body = "Score the Target before your hands run out." },
}

M.MAX_NIGHT = 1
M.MAX_ROUND = 3
-- the plate is the whole picture pk_w_hint (crown medallion on the left, 1408 x 543, so 2.59 : 1), 320 wide when it fits and down to 280; the small
-- dark Got it plate sits UNDER it, on the text column (reference: hint panel 320 x 140 with the button below)
M.PLATE_W = 320
M.PLATE_MIN_W = 280
M.PLATE_ASPECT = 1408 / 543
M.BUTTON_W, M.BUTTON_H = 90, 44
-- short screens (under about 160 px free above the hand) keep the compact plate: 300 x 72 with a 72 x 44 Got it beside it, the pill picture
M.WIDE_W, M.WIDE_H, M.WIDE_MIN_W, M.WIDE_BUTTON_W = 300, 84, 200, 92
M.WIDE_BUTTON_H = 44 -- a wide Got it, level with the middle of the plate (it was a square 72 x 72)
-- Got it plate: a warm green primary (cream on it is at least 4.5:1, which the Next Round green is not), gold edge, level with the hint plate
-- reference: the heading is gold serif on the dark plate (about 8:1), the body cream sans
M.TITLE_COLOR = { 246, 196, 70 }
M.PLATE_COLOR = { 46, 28, 14 }
-- Got it is a small dark wood plate with a gold edge and gold text (about 8:1), not green
M.GOT_IT = { fill = { 46, 28, 14 }, hover = { 70, 44, 22 }, edge = { 232, 184, 74 }, text = { 246, 196, 70 }, stroke = { 18, 10, 4 } }
-- the tall plate's Got it stands 8 px under the plate, its left edge on the text column (0.31 of the plate), well clear of the table candle at the right
M.BUTTON_COL = 0.31
M.GAP = 8

local BY_ID = {}
for _, e in ipairs(M.ORDER) do BY_ID[e.id] = e end
function M.getById(id) return BY_ID[id] end

function M.enabledFor(state, opts)
	opts = opts or {}
	if type(state) ~= "table" or state.phase ~= "playing" or state.isTutorial == true then return false end
	if opts.enabled == false or opts.calm == true then return false end
	if (tonumber(state.night) or 1) > M.MAX_NIGHT or (tonumber(state.round) or 1) > M.MAX_ROUND then return false end
	local best = state.profileStats and tonumber(state.profileStats.bestNightReached) or 0
	if best >= 2 then return false end -- Night 1 was cleared on an earlier run
	if state.guidedFirstHand == true and (tonumber(state.handsPlayedTotal) or 0) < 1 then return false end -- the guided hint owns the screen
	if state.choice ~= nil then return false end
	return true
end

local function owned(state)
	return type(state.ownedPatrons) == "table" and #state.ownedPatrons or 0
end

function M.next(state, seen, opts)
	if not M.enabledFor(state, opts) then return nil end
	seen = type(seen) == "table" and seen or {}
	local round = tonumber(state.round) or 1
	for _, e in ipairs(M.ORDER) do
		if not seen[e.id] then
			local ok = true
			if e.id == "round_hint_select" then ok = round == 1 and not M.expired(e.id, state)
			elseif e.id == "round_hint_tiers" then ok = owned(state) >= 1
			elseif e.id == "round_hint_target" then ok = round >= 2 end
			if ok then return e end
			-- an unseen entry that is not due yet does not block the ones after it, but only the first due one shows
		end
	end
	return nil
end

-- A plate that has done its job for good: "Pick your cards" is spent once any hand was played (the guided first hand teaches it too),
-- so it never shows after a hand and is marked seen.
function M.expired(id, state)
	return id == "round_hint_select" and type(state) == "table" and (tonumber(state.handsPlayedTotal) or 0) >= 1
end

function M.satisfied(id, selectedCount)
	return id == "round_hint_select" and (tonumber(selectedCount) or 0) >= 1
end

local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end

-- The open middle: left of the score stage, or right of it, between the Patron pills and the hand. The stage itself holds the score,
-- and the played cards land under it, so the plate stays beside it.
local function placeAt(r, viewW, viewH, avoid, topAt)
	if type(r) ~= "table" or not r.stage or not r.hand or not r.slots or not r.slots[1] then return nil end
	local top = topAt or (r.slots[1].pill.y + r.slots[1].pill.h + 4)
	local bottom = r.hand.y - 6
	local pad = 8
	local cols = {
		{ x0 = pad, x1 = r.stage.x - pad }, -- left of the stage
		{ x0 = r.stage.x + r.stage.w + pad, x1 = viewW - pad }, -- right of it
	}
	for _, col in ipairs(cols) do
		local plateW = math.min(math.max(M.PLATE_MIN_W, math.min(360, math.floor(0.19 * viewW + 0.5))), col.x1 - col.x0) -- the mockup plate is 317 of 1672 wide
		while plateW >= M.PLATE_MIN_W do
			local plateH = math.floor(plateW / M.PLATE_ASPECT + 0.5)
			local total = plateH + M.GAP + M.BUTTON_H
			if bottom - top >= total then
				local x, y = col.x0, top
				local plate = { x = x, y = y, w = plateW, h = plateH }
				local button = { x = x + math.floor(plateW * M.BUTTON_COL), y = y + plateH + M.GAP, w = M.BUTTON_W, h = M.BUTTON_H }
				local clear = true
				for name, rect in pairs(r) do
					if name ~= "stage" and name ~= "bar" and name ~= "slots" and rect.x and (hit(plate, rect) or hit(button, rect)) then clear = false end
				end
				for _, s in ipairs(r.slots) do
					for _, part in ipairs({ s.card, s.label, s.pill }) do
						if hit(plate, part) or hit(button, part) then clear = false end
					end
				end
				if hit(plate, r.stage) or hit(button, r.stage) then clear = false end
				for _, a in ipairs(avoid or {}) do -- a boss rule plate and anything else that must stay uncovered
					if hit(plate, a) or hit(button, a) then clear = false end
				end
				if plate.x >= 0 and button.x + button.w <= viewW and y + total <= viewH and clear then
					return { plate = plate, button = button, kind = "tall" }
				end
			end
			plateW = plateW - 20
		end
	end
	local h = math.max(M.WIDE_H, M.BUTTON_H)
	if bottom - top < h then return nil end
	for _, col in ipairs(cols) do
		local total = math.min(M.WIDE_W + M.GAP + M.WIDE_BUTTON_W, col.x1 - col.x0)
		local plateW = total - M.GAP - M.WIDE_BUTTON_W
		if plateW >= M.WIDE_MIN_W then
			local x, y = col.x0, top
			local plate = { x = x, y = y, w = plateW, h = h }
			local button = { x = x + plateW + M.GAP, y = y + math.floor((h - M.WIDE_BUTTON_H) / 2), w = M.WIDE_BUTTON_W, h = M.WIDE_BUTTON_H } -- vertically centred on the plate
			local clear = true
			for name, rect in pairs(r) do
				if name ~= "stage" and name ~= "bar" and name ~= "slots" and rect.x and (hit(plate, rect) or hit(button, rect)) then clear = false end
			end
			for _, s in ipairs(r.slots) do
				for _, part in ipairs({ s.card, s.label, s.pill }) do
					if hit(plate, part) or hit(button, part) then clear = false end
				end
			end
			if hit(plate, r.stage) or hit(button, r.stage) then clear = false end
			for _, a in ipairs(avoid or {}) do
				if hit(plate, a) or hit(button, a) then clear = false end
			end
			if plate.x >= 0 and button.x + button.w <= viewW and y + h <= viewH and clear then
				return { plate = plate, button = button, kind = "wide" }
			end
		end
	end
	return nil
end

-- The mockup's hint plate stands in the left column beside the Patron seats (x 18 to 335, y 345 to 485 of 1672 x 941), level with
-- the first seat's label row; where the consumables tray or anything else is in the way it drops to the open middle under the pills.
function M.place(r, viewW, viewH, avoid)
	if type(r) == "table" and r.slots and r.slots[1] and r.slots[1].label then
		local top = r.slots[1].label.y
		for _, key in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do -- stay under the consumables tray
			local t = r[key]
			if t then top = math.max(top, t.y + t.h + 6) end
		end
		local beside = placeAt(r, viewW, viewH, avoid, top)
		if beside then return beside end
	end
	return placeAt(r, viewW, viewH, avoid, nil)
end

return M
