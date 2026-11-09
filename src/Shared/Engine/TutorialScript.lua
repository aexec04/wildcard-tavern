--[[
	Shared/Engine/TutorialScript.lua
	The scripted hands of the first-run tutorial (pure, tested). The server deals them to a brand-new player's
	first real run so the guided steps can name an exact combo: a pair, then two pair, then a flush, and last a
	straight flush for a big score. Each stage puts its target cards FIRST in the hand (so the tutorial can
	spotlight a contiguous block and dim the rest) and fills the rest with other cards that do not make a
	better hand by accident. Cards are never created or lost: the old hand goes back into the deck.

	Stages[n] = { name, targets = { {rank, suit}, ... } }
	applyStage(state, stage, handSize?) -> ok    rewrites state.hand / state.deck; false if a target card is gone
	targetCount(stage) -> number
]]

local Patrons = require(script.Parent.Patrons)
local Packs = require(script.Parent.Packs)

local TutorialScript = {}

TutorialScript.Stages = {
	{ name = "pair", targets = { { 7, "Hearts" }, { 7, "Spades" } } },
	{ name = "two_pair", targets = { { 13, "Hearts" }, { 13, "Clubs" }, { 4, "Diamonds" }, { 4, "Spades" } } },
	{ name = "flush", targets = { { 2, "Diamonds" }, { 6, "Diamonds" }, { 9, "Diamonds" }, { 11, "Diamonds" }, { 14, "Diamonds" } } },
	{ name = "straight_flush", targets = { { 5, "Clubs" }, { 6, "Clubs" }, { 7, "Clubs" }, { 8, "Clubs" }, { 9, "Clubs" } } },
}

function TutorialScript.targetCount(stage)
	local s = TutorialScript.Stages[stage]
	return s and #s.targets or 0
end

local function key(rank, suit)
	return tostring(rank) .. suit
end

function TutorialScript.applyStage(state, stage, handSize)
	local spec = TutorialScript.Stages[stage]
	if not spec or type(state) ~= "table" then
		return false
	end
	handSize = handSize or #state.hand
	if handSize < #spec.targets then
		handSize = #spec.targets
	end

	-- Everything we can deal from: the deck (top of the deck is its END, drawn first) plus the current hand.
	local pool = {}
	for _, card in ipairs(state.deck) do pool[#pool + 1] = card end
	for _, card in ipairs(state.hand) do pool[#pool + 1] = card end

	local function take(rank, suit)
		for i, card in ipairs(pool) do
			if card.rank == rank and card.suit == suit then
				table.remove(pool, i)
				return card
			end
		end
		return nil
	end

	local newHand = {}
	local usedRanks = {}
	for _, t in ipairs(spec.targets) do
		local card = take(t[1], t[2])
		if not card then
			return false -- a target is already gone (should not happen); leave the hand alone
		end
		newHand[#newHand + 1] = card
		usedRanks[card.rank] = true
	end

	-- keep later stages' targets in the deck (they must still be there when their stage comes)
	local reserved = {}
	for later = stage + 1, #TutorialScript.Stages do
		for _, t in ipairs(TutorialScript.Stages[later].targets) do
			reserved[key(t[1], t[2])] = true
		end
	end

	-- fillers: distinct ranks (no accidental pair) that are not part of a later stage
	local fillers = {}
	for i = #pool, 1, -1 do
		local card = pool[i]
		if #newHand + #fillers >= handSize then break end
		if not usedRanks[card.rank] and not reserved[key(card.rank, card.suit)] then
			usedRanks[card.rank] = true
			fillers[#fillers + 1] = i
		end
	end
	-- (if the ranks ran out, fall back to any non-reserved card)
	if #newHand + #fillers < handSize then
		for i = #pool, 1, -1 do
			local card = pool[i]
			if #newHand + #fillers >= handSize then break end
			local already = false
			for _, f in ipairs(fillers) do if f == i then already = true end end
			if not already and not reserved[key(card.rank, card.suit)] then
				fillers[#fillers + 1] = i
			end
		end
	end
	table.sort(fillers, function(a, b) return a > b end)
	for _, i in ipairs(fillers) do
		newHand[#newHand + 1] = table.remove(pool, i)
	end

	state.hand = newHand
	state.deck = pool
	return true
end

-- SCRIPTED SHOP for the tutorial run (server, applied on every roll including a reroll): a cheap Patron and a
-- cheap Pack are always on the shelf (the cheapest the run does not own), no House Pass, and the player has
-- enough Tips for a Patron, a Pack and one Reroll. Mutates `offers` and state.tips, returns the cost it covers.
function TutorialScript.shopFor(state, offers, rerollCost)
	local owned = {}
	for _, p in ipairs(state.ownedPatrons or {}) do owned[p.id] = true end
	local cheapPatron
	for _, p in ipairs(Patrons.Definitions) do
		if not owned[p.id] and (not cheapPatron or p.price < cheapPatron.price) then cheapPatron = p end
	end
	local cheapPack
	for _, pk in ipairs(Packs.Definitions) do
		if not cheapPack or pk.price < cheapPack.price then cheapPack = pk end
	end
	offers.voucher = nil
	if cheapPatron then
		offers.patrons = offers.patrons or {}
		for i = #offers.patrons, 1, -1 do
			if offers.patrons[i].id == cheapPatron.id then table.remove(offers.patrons, i) end
		end
		table.insert(offers.patrons, 1, cheapPatron)
		while #offers.patrons > 2 do table.remove(offers.patrons) end
	end
	if cheapPack then
		offers.packs = offers.packs or {}
		for i = #offers.packs, 1, -1 do
			if offers.packs[i].id == cheapPack.id then table.remove(offers.packs, i) end
		end
		table.insert(offers.packs, 1, cheapPack)
		while #offers.packs > 2 do table.remove(offers.packs) end
	end
	local need = (cheapPatron and cheapPatron.price or 0) + (cheapPack and cheapPack.price or 0) + (rerollCost or 5) + 2
	if (state.tips or 0) < need then state.tips = need end
	return need
end

return TutorialScript
