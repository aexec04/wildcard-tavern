--[[
	CardBacks.lua
	Cosmetic card backs. Right now the only way to unlock one is a
	Collection milestone (CollectionBook.Milestones); unlocked ids are kept
	in PlayerProfile.unlockedCardBackIds. Choosing which back to show in a
	run is not built yet -- the deck widget still draws the classic back.

	`colors` are {r, g, b} triples (0-255) so this file stays pure Lua.
]]

local CardBacks = {}

CardBacks.DefaultId = "classic"

CardBacks.Definitions = {
	{
		id = "classic",
		name = "Classic Blue",
		icon = "🂠",
		colors = { base = { 50, 70, 110 }, trim = { 220, 190, 120 } },
		description = "The tavern's everyday deck.",
		flavorText = "Worn soft at the corners from a thousand friendly games.",
	},
	{
		id = "gilded_ledger",
		name = "Gilded Ledger",
		icon = "📜",
		colors = { base = { 120, 85, 40 }, trim = { 250, 215, 130 } },
		description = "A Collection milestone reward.",
		flavorText = "Bound in the same gold leaf as the keeper's guest book.",
	},
	{
		id = "starlit_keeper",
		name = "Starlit Keeper",
		icon = "🌌",
		colors = { base = { 30, 30, 70 }, trim = { 200, 210, 255 } },
		description = "A Collection milestone reward.",
		flavorText = "Only handed to guests who have met every face in the tavern.",
	},
}

function CardBacks.getById(id)
	for _, back in ipairs(CardBacks.Definitions) do
		if back.id == id then
			return back
		end
	end
	return nil
end

return CardBacks
