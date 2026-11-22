--[[
	Shared/Engine/RoundHints.lua
	The hint layer for the first three rounds of Night 1 (after the guided first hand). Three short plates, one at a time, each
	dismissible and shown once per profile (profile.hintsSeen, ids registered in Engine/Hints): pick cards, Patron power tiers
	(the Target is printed in the top bar, so it has no card). At most one tip card is on screen: while the Patron Power panel shows, next() gives nothing. Pure Lua, no Roblox APIs. Display only: it never changes a run.

	RoundHints.ORDER                      list of { id, title, body }
	RoundHints.enabledFor(state, opts)    -> bool   the whole layer is on for this state (Night 1, rounds 1 to 3, playing, not Calm,
	                                      Hints toggle on, Night 1 not cleared before, tutorial and guided first hand excluded)
	RoundHints.next(state, seen, opts)    -> nil | entry   first unseen entry whose own condition holds; opts = { enabled, calm, panelShowing }
	RoundHints.expired(id, state) -> bool    the plate is spent for good (pick cards: any hand was played); it hides and is marked seen
	RoundHints.satisfied(id, selectedCount) -> bool   the plate has done its job (pick cards: one card is selected)
	RoundHints.place(r, viewW, viewH)     -> nil | { plate, button }   root pixel rects in the open middle beside the score stage,
	                                      clear of every table rect (nil when nothing fits: the hint is then skipped, never overlapped)
]]

local M = {}
local ScorePlate = require(script.Parent.Gameplay2ScorePlate)

M.ORDER = {
	{ id = "round_hint_select", title = "Pick your cards", body = "Pick up to 5 cards, then Play Hand." },
	{ id = "round_hint_tiers", title = "Patron Power", body = "Wood frames are Common, gold are Legendary." },
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
	local panelShowing = opts and opts.panelShowing
	seen = type(seen) == "table" and seen or {}
	local round = tonumber(state.round) or 1
	for _, e in ipairs(M.ORDER) do
		-- the Patron Power panel is the permanent tip card, so later plates wait for it; the pick-your-cards line is the first
		-- instruction of a new profile and always shows (the client moves the panel aside while it is up)
		if not seen[e.id] and not (panelShowing and e.id ~= "round_hint_select") then
			local ok = true
			if e.id == "round_hint_select" then ok = round == 1 and not M.expired(e.id, state)
			elseif e.id == "round_hint_tiers" then ok = owned(state) >= 1 and not (opts and opts.panelOwnsTiers) -- the left panel shows it
			end
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
			local total = plateH + M.GAP + M.BUTTON_H + M.STRIP_PAD
			if bottom - top >= total then
				local x, y = col.x0, top
				local plate = { x = x, y = y, w = plateW, h = plateH + M.GAP + M.BUTTON_H + M.STRIP_PAD } -- one card: Got it sits inside it, bottom right
				local button = { x = x + plateW - M.STRIP_PAD - M.BUTTON_W, y = y + plateH + M.GAP, w = M.BUTTON_W, h = M.BUTTON_H }
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
					return { plate = plate, button = button, kind = "tall", textW = plateW - 2 * M.STRIP_PAD - 4 }
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
			local plate = { x = x, y = y, w = total, h = h } -- one card: Got it sits inside it, at the right
			local button = { x = x + total - M.STRIP_PAD - M.WIDE_BUTTON_W, y = y + math.floor((h - M.WIDE_BUTTON_H) / 2), w = M.WIDE_BUTTON_W, h = M.WIDE_BUTTON_H } -- vertically centred on the plate
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
				return { plate = plate, button = button, kind = "wide", textW = total - 3 * M.STRIP_PAD - M.WIDE_BUTTON_W - 4 }
			end
		end
	end
	return nil
end

-- The mockup's hint plate stands in the left column beside the Patron seats (x 18 to 335, y 345 to 485 of 1672 x 941), level with
-- the first seat's label row; where the consumables tray or anything else is in the way it drops to the open middle under the pills.
-- The slim strip: one 60 px plate centred above the hand fan with the Got it plate inside it on the right (the concept shows nothing at the
-- left of the table). 520 wide at 1920 and scaled with the screen (never under 360); it ends STRIP_GAP above the hand rect and never stands
-- over the Score plate or its progress line, and never over a Patron seat or the avoid rects. nil when it does not fit.
M.STRIP_W, M.STRIP_H, M.STRIP_MIN_W, M.STRIP_GAP, M.STRIP_PAD = 520, 60, 360, 6, 8
M.STRIP_TITLE, M.STRIP_BODY = 22, 20
M.STRIP_SIDE_GAP = 12
M.STRIP_SIDE_MIN_W = 330 -- the side spot may be a little narrower than the strip above the hand (the tray gap takes 20 px of it)
M.STRIP_TRAY_GAP =24 + 8 -- 24 px clear of the deck tray lip (the lip is 8 px outside the deck rect)
function M.strip(r, viewW, viewH, avoid)
	if type(r) ~= "table" or not r.hand or not r.slots or not r.slots[1] then return nil end
	local w = math.min(M.STRIP_W, math.max(M.STRIP_MIN_W, math.floor(M.STRIP_W / 1920 * viewW + 0.5)))
	local above = { x = math.floor((viewW - w) / 2), y = r.hand.y - M.STRIP_GAP - M.STRIP_H, w = w, h = M.STRIP_H }
	local cands, score, progress = {}, nil, nil -- score: the Score plate and its progress line, which the strip never covers
	-- preferred spot: level with the top of the Score plate and just right of it (the strip above the hand covered the "o of N" line),
	-- then the mirror spot left of it, then above the hand; the Score plate is min(stage w, max(240, 0.19 x screen)) wide, centred in the stage
	if r.stage then
		local pw = math.min(r.stage.w, math.max(240, math.floor(0.19 * viewW)))
		local plateLeft = r.stage.x + math.floor((r.stage.w - pw) / 2)
		local sx = plateLeft + pw + M.STRIP_SIDE_GAP
		local live = ScorePlate.live(r.stage, viewW, 20, 22)
		score, progress = live.plate, live.progress
		local sw = w
		if r.deck and r.deck.x then sw = math.min(w, r.deck.x - M.STRIP_TRAY_GAP - sx) end -- narrower beside the deck, never under the minimum
		if sx + sw <= viewW - M.STRIP_SIDE_GAP and sw >= M.STRIP_SIDE_MIN_W then
			cands[#cands + 1] = { x = sx, y = r.stage.y, w = sw, h = M.STRIP_H }
		end
	end
	cands[#cands + 1] = above
	for _, plate in ipairs(cands) do
		local ok = plate.x >= 0 and plate.y >= 0 and plate.x + plate.w <= viewW and plate.y + plate.h <= viewH
		if ok and plate ~= above then
			for name, rect in pairs(r) do -- any table piece in the way (the deck, the bar) sends it to the next spot
				if name ~= "stage" and name ~= "slots" and type(rect) == "table" and rect.x and hit(plate, rect) then ok = false end
			end
		end
		if ok and score and hit(plate, score) then ok = false end
		if ok and progress and hit(plate, progress) then ok = false end -- the "0 of N" line under the plate stays readable
		for _, s in ipairs(r.slots) do
			for _, part in ipairs({ s.card, s.label, s.pill }) do
				if ok and part and hit(plate, part) then ok = false end
			end
		end
		for _, a in ipairs(avoid or {}) do
			if ok and hit(plate, a) then ok = false end
		end
		if ok then
			local bh = M.BUTTON_H
			local button = { x = plate.x + plate.w - M.STRIP_PAD - M.BUTTON_W, y = plate.y + math.floor((M.STRIP_H - bh) / 2), w = M.BUTTON_W, h = bh }
			return { plate = plate, button = button, kind = "strip", textW = plate.w - 3 * M.STRIP_PAD - M.BUTTON_W }
		end
	end
	return nil
end

function M.place(r, viewW, viewH, avoid)
	local strip = M.strip(r, viewW, viewH, avoid)
	if strip then return strip end
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
