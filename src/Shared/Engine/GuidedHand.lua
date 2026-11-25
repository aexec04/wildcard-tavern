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

M.FOLLOW_UP_HANDS = 2 -- hands after the first that still get a hint line (the hint ends after hand 3)
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
	local played = tonumber(handsPlayed) or 0
	if not guided or played >= M.FOLLOW_UP_HANDS + 1 then return nil end
	if played >= 1 then -- the first hand is in: two more short lines so the next minute is never silent, then the hint ends
		if (tonumber(selectedCount) or 0) < 1 then
			return { line1 = "Nice! Now pick more cards.", line2 = "Reach the Target to clear the round.", target = "card", cards = 1, pulse = not calm }
		end
		return { line1 = "Play your hand", line2 = "Discard swaps weak cards.", target = "play", pulse = not calm }
	end
	if (tonumber(selectedCount) or 0) < 1 then -- one picked card is already a legal hand: from then on Play Hand is the one thing to press
		return { line1 = "Tap two cards to pick them.", line2 = "You can pick up to five.", target = "card", cards = 2, pulse = not calm }
	end
	return { line1 = "Play your hand", line2 = "Your best hand scores.", target = "play", pulse = not calm }
end

local NAME_RANK = { ["High Card"] = 1, ["Pair"] = 2, ["Two Pair"] = 3, ["Three of a Kind"] = 4, ["Straight"] = 5, ["Flush"] = 6, ["Full House"] = 7, ["Four of a Kind"] = 8, ["Straight Flush"] = 9 }

-- bestPlay(hand) -> nil | { indices = {1-based hand positions of the scoring cards, ascending}, name }
-- The strongest legal hand (1 to 5 cards) in the dealt cards, by the real hand evaluator; ties go to more scoring cards, then higher ranks.
function M.bestPlay(hand)
	if type(hand) ~= "table" or #hand == 0 then return nil end
	local Evaluator = require(script.Parent.HandEvaluator)
	local n = #hand
	local best, bestKey
	local pick = {}
	local function try()
		local cards = {}
		for i, idx in ipairs(pick) do cards[i] = hand[idx] end
		local ok, res = pcall(Evaluator.evaluate, cards)
		if not ok or type(res) ~= "table" then return end
		local sum = 0
		for _, c in ipairs(res.scoringCards) do sum = sum + (c.rank or 0) end
		local key = (NAME_RANK[res.name] or 0) * 1000000 + #res.scoringCards * 10000 + sum * 10 - #pick
		if not bestKey or key > bestKey then
			bestKey = key
			local scoring = {}
			for _, c in ipairs(res.scoringCards) do scoring[c] = true end
			local idxs = {}
			for i, idx in ipairs(pick) do if scoring[cards[i]] then idxs[#idxs + 1] = idx end end
			best = { indices = idxs, name = res.name }
		end
	end
	local function rec(start)
		if #pick >= 1 then try() end
		if #pick == 5 then return end
		for i = start, n do
			pick[#pick + 1] = i
			rec(i + 1)
			pick[#pick] = nil
		end
	end
	rec(1)
	return best
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
	-- the hand name plate ("Pair") sits where Gameplay2Preview.namePlate puts it (under the Round plate, or on the felt below the Patron seats); keep the hint plate below it
	local okP, Preview = pcall(function() return require(script.Parent.Gameplay2Preview) end)
	local nr = okP and r.round and Preview.namePlate(r, nil) or nil
	if nr then
		local nameBottom = nr.y + nr.h + 4
		if y < nameBottom and nameBottom < bottom - 24 then
			y = nameBottom
			if y + h > bottom then h = bottom - y end
		end
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
