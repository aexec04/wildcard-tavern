--[[
	Engine/DeckCountText.lua
	The deck pile's count text, "44/52": cards still in the draw pile over every card in the run's deck.
	The total is the length of the state's deckView (every card with its status), so a deck that gained or lost cards
	(packs, Recipes, deck variants) reads true instead of a fixed 52.

	DeckCountText.total(deckView, remaining) -> number   (falls back to 52 when no view is available, never below remaining)
	DeckCountText.format(remaining, deckView) -> string
	DeckCountText.spaced(remaining, deckView) -> string   ("37 / 52", the Concept T count plate)
]]

local M = {}

M.DEFAULT_TOTAL = 52

function M.total(deckView, remaining)
	remaining = math.max(0, math.floor(tonumber(remaining) or 0))
	local n = (type(deckView) == "table") and #deckView or 0
	if n <= 0 then n = M.DEFAULT_TOTAL end
	return math.max(n, remaining)
end

function M.format(remaining, deckView)
	remaining = math.max(0, math.floor(tonumber(remaining) or 0))
	return string.format("%d/%d", remaining, M.total(deckView, remaining))
end

function M.spaced(remaining, deckView)
	return (M.format(remaining, deckView):gsub("/", " / "))
end

return M
