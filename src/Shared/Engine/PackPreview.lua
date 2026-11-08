--[[
	Shared/Engine/PackPreview.lua
	For the pack pick screen's hover (pure, tested): which card of your run a revealed playing card sits next to.

	A Standard Pack card joins your deck (RunState.resolvePack adds it to the discard pile; nothing is removed),
	so the hover shows the plain card with the same rank and suit that you already own, with an arrow to the new
	special card, and says how many copies you hold. When you own no plain copy, `match` is nil.

	matchFromDeckView(deckView, spec) -> { entry, copies, status } | nil
	    deckView = state.deckView (one entry per card of the run: rank, suit, garnish, special, stamp, status);
	    spec = the revealed item's card ({ rank, suit, garnish?, special?, stamp? }).
	caption(match) -> "You hold 1 plain Seven of Hearts. The new card joins your deck."
]]

local PackPreview = {}

local RANK_NAMES = { [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace" }

local function rankName(rank)
	return RANK_NAMES[rank] or tostring(rank)
end

local function plain(entry)
	return entry.garnish == nil and entry.special == nil and entry.stamp == nil
end

function PackPreview.matchFromDeckView(deckView, spec)
	if type(deckView) ~= "table" or type(spec) ~= "table" then return nil end
	local first, copies = nil, 0
	for _, entry in ipairs(deckView) do
		if entry.rank == spec.rank and entry.suit == spec.suit and plain(entry) then
			copies = copies + 1
			first = first or entry
		end
	end
	if not first then return nil end
	return { entry = first, copies = copies, status = first.status }
end

function PackPreview.caption(match, spec)
	if not match then
		return "You own no plain copy. The new card joins your deck."
	end
	local what = rankName(spec.rank) .. " of " .. spec.suit
	return string.format("You hold %d plain %s. The new card joins your deck.", match.copies, what)
end

return PackPreview
