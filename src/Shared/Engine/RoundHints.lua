--[[
	Shared/Engine/RoundHints.lua
	The hint layer for the first three rounds of Night 1 (after the guided first hand). Three short plates, one at a time, each
	dismissible and shown once per profile (profile.hintsSeen, ids registered in Engine/Hints): pick cards, Patron power tiers,
	what Target means. Pure Lua, no Roblox APIs. Display only: it never changes a run.

	RoundHints.ORDER                      list of { id, title, body }
	RoundHints.enabledFor(state, opts)    -> bool   the whole layer is on for this state (Night 1, rounds 1 to 3, playing, not Calm,
	                                      Hints toggle on, Night 1 not cleared before, tutorial and guided first hand excluded)
	RoundHints.next(state, seen, opts)    -> nil | entry   first unseen entry whose own condition holds; opts = { enabled, calm }
	RoundHints.satisfied(id, selectedCount) -> bool   the plate has done its job (pick cards: one card is selected)
	RoundHints.place(r, viewW, viewH)     -> nil | { plate, button }   root pixel rects in the open middle beside the score stage,
	                                      clear of every table rect (nil when nothing fits: the hint is then skipped, never overlapped)
]]

local M = {}

M.ORDER = {
	{ id = "round_hint_select", title = "Pick your cards", body = "Tap up to five cards, then press Play Hand." },
	{ id = "round_hint_tiers", title = "Patron power", body = "The frame shows power: wood is Common, gold is Legendary." },
	{ id = "round_hint_target", title = "What is Target?", body = "Reach the Target score before your hands run out." },
}

M.MAX_NIGHT = 1
M.MAX_ROUND = 3
M.PLATE_W, M.PLATE_H = 300, 56
M.PLATE_MIN_W = 200
M.BUTTON_W, M.BUTTON_H = 72, 44
M.GAP = 6

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
			if e.id == "round_hint_select" then ok = round == 1
			elseif e.id == "round_hint_tiers" then ok = owned(state) >= 1
			elseif e.id == "round_hint_target" then ok = round >= 2 end
			if ok then return e end
			-- an unseen entry that is not due yet does not block the ones after it, but only the first due one shows
		end
	end
	return nil
end

function M.satisfied(id, selectedCount)
	return id == "round_hint_select" and (tonumber(selectedCount) or 0) >= 1
end

local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end

-- The open middle: left of the score stage, or right of it, between the Patron pills and the hand. The stage itself holds the score,
-- and the played cards land under it, so the plate stays beside it.
function M.place(r, viewW, viewH)
	if type(r) ~= "table" or not r.stage or not r.hand or not r.slots or not r.slots[1] then return nil end
	local top = r.slots[1].pill.y + r.slots[1].pill.h + 4
	local bottom = r.hand.y - 6
	local h = math.max(M.PLATE_H, M.BUTTON_H)
	if bottom - top < h then return nil end
	local pad = 8
	local cols = {
		{ x0 = pad, x1 = r.stage.x - pad }, -- left of the stage
		{ x0 = r.stage.x + r.stage.w + pad, x1 = viewW - pad }, -- right of it
	}
	for _, col in ipairs(cols) do
		local total = math.min(M.PLATE_W + M.GAP + M.BUTTON_W, col.x1 - col.x0)
		local plateW = total - M.GAP - M.BUTTON_W
		if plateW >= M.PLATE_MIN_W then
			local x = col.x0
			local y = top
			local plate = { x = x, y = y, w = plateW, h = h }
			local button = { x = x + plateW + M.GAP, y = y, w = M.BUTTON_W, h = M.BUTTON_H }
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
			if plate.x >= 0 and button.x + button.w <= viewW and y + h <= viewH and clear then
				return { plate = plate, button = button }
			end
		end
	end
	return nil
end

return M
