--[[
	Marks.lua
	Card marks: one small permanent mark a deck card can carry for the rest of the run. Pure Lua, no Roblox APIs.

	  Gilded  +30 Chips when the card scores
	  Lucky   +4 Mult when the card scores
	  Lively  x1.2 Mult when the card scores

	The numbers live in Card.Marks and are scored by Scoring.calculate (so the hand preview agrees by construction).
	The Counter offers one Mark pack per visit from Night 2 (Shop.rollOffers gives `offers.mark`, a mark id): it costs
	Tips only, never Robux, and it says exactly which mark you get, no random wording. You then pick the deck card.
	Server authoritative: Marks.buy validates the id, the price and the card, and a card holds at most one mark.
	A True Wildcard that is still hidden cannot be marked (its rank is a secret).
]]

local Card = require(script.Parent.Card)

local Marks = {}

Marks.PRICE = 3
Marks.MIN_NIGHT = 2 -- the first Night is for learning; the Mark pack starts at the Night 2 Counter

function Marks.getById(id)
	return Card.Marks[id]
end

-- The mark id this visit's pack holds (nil on Night 1). It cycles with the Night and round, and draws nothing from the
-- run rng, so every other offer and every seeded board stays exactly as it was.
function Marks.rollOffer(state)
	local night = state.night or 1
	if night < Marks.MIN_NIGHT then return nil end
	return Card.MarkOrder[(night * 2 + (state.round or 1)) % #Card.MarkOrder + 1]
end

function Marks.price(state)
	return Marks.PRICE
end

-- One line for the pack: exactly what you get ("Gilded Mark: +30 Chips when this card scores.").
function Marks.packText(id)
	local def = Card.Marks[id]
	if not def then return "" end
	return def.name .. " Mark: " .. def.description
end

-- A short tooltip line for a card that carries a mark.
function Marks.cardLine(id)
	local def = Card.Marks[id]
	if not def then return "" end
	return def.name .. ": " .. def.description
end

-- Every card the run owns, wherever it is right now (draw pile, hand, discard pile).
local function allCards(state)
	local out = {}
	for _, list in ipairs({ state.deck or {}, state.hand or {}, state.discardPile or {} }) do
		for _, card in ipairs(list) do out[#out + 1] = card end
	end
	return out
end

-- The first unmarked card of that rank and suit (a Lucky Deck holds two Kings of a suit; either one will do).
function Marks.findCard(state, rank, suit)
	for _, card in ipairs(allCards(state)) do
		if card.rank == rank and card.suit == suit and not card.mark
			and not (card.isTrueWildcard and not card.wildcardLocked) then
			return card
		end
	end
	return nil
end

-- Spends Tips and puts the mark on the picked card. Returns ok, message.
function Marks.buy(state, markId, rank, suit, price)
	local def = type(markId) == "string" and Card.Marks[markId] or nil
	if not def then return false, "Unknown mark" end
	if type(rank) ~= "number" or type(suit) ~= "string" then return false, "Pick a card" end
	price = price or Marks.price(state) -- the Market node sells at its own price
	if (state.tips or 0) < price then return false, "Not enough tips" end
	local card = Marks.findCard(state, rank, suit)
	if not card then return false, "That card is not in your deck, or it is already marked" end
	state.tips = state.tips - price
	card.mark = markId
	state.marksBought = (state.marksBought or 0) + 1
	return true, def.name .. " Mark added to your " .. Card.toString(card) .. "."
end

return Marks
