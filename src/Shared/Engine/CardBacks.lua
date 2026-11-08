--[[
	CardBacks.lua
	Cosmetic card backs. Right now the only way to unlock one is a
	Collection milestone (CollectionBook.Milestones); unlocked ids are kept
	in PlayerProfile.unlockedCardBackIds. Cosmetic Sets (CosmeticSets.lua) pick which back is shown;
	`setOnly` backs come only from a set.

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
	{
		id = "winter_frost",
		name = "Winter Frost",
		icon = "❄",
		colors = { base = { 70, 100, 140 }, trim = { 230, 240, 255 } },
		description = "Part of the Frosted Garden set.",
		flavorText = "Frosted at the edges like a window in January.",
		setOnly = true,
	},
	{
		id = "festival_ribbon",
		name = "Festival Ribbon",
		icon = "🎊",
		colors = { base = { 150, 50, 70 }, trim = { 255, 220, 120 } },
		description = "Part of the Mountain Festival set.",
		flavorText = "Tied with the same ribbon as the lanterns outside.",
		setOnly = true,
	},
	{
		id = "closing_lantern",
		name = "Closing Lantern",
		icon = "🏮",
		colors = { base = { 60, 40, 30 }, trim = { 240, 170, 80 } },
		description = "Part of the Closing Time set.",
		flavorText = "Glows like the last lamp left burning.",
		setOnly = true,
	},
	{
		id = "kitchen_checks",
		name = "Meadow Checks",
		icon = "🍲",
		colors = { base = { 170, 70, 50 }, trim = { 250, 235, 200 } },
		description = "A Journey reward for clearing Night 2.",
		flavorText = "Checkered like a picnic blanket in the wildflowers.",
		setOnly = true,
	},
	{
		id = "hall_banner",
		name = "Gate Banner",
		icon = "🏛",
		colors = { base = { 90, 40, 90 }, trim = { 240, 200, 120 } },
		description = "A Journey reward for clearing Night 6.",
		flavorText = "Stitched from the banners that wave over the tavern gate.",
		setOnly = true,
	},
	{
		id = "ember_hours",
		name = "Ember Hours",
		icon = "🔥",
		colors = { base = { 60, 24, 40 }, trim = { 255, 170, 90 } },
		description = "A Journey reward for clearing Endless Night 15.",
		flavorText = "Warm as the last coals after the doors should have closed.",
		setOnly = true,
	},
	-- Biome rewards (Engine/BiomeRewards.lua): earned by finishing a road through that biome.
	{
		id = "dune_gold",
		name = "Dune Gold",
		icon = "🏜",
		colors = { base = { 196, 150, 80 }, trim = { 255, 226, 150 } },
		description = "A Map reward for finishing the dunes road.",
		flavorText = "Rippled like the sand after a warm evening breeze.",
	},
	{
		id = "lilypad_green",
		name = "Lilypad Green",
		icon = "🐸",
		colors = { base = { 52, 96, 70 }, trim = { 220, 235, 150 } },
		description = "A Map reward for finishing the marsh road.",
		flavorText = "Small frogs sit on every leaf and keep the secret.",
	},
	{
		id = "shell_pearl",
		name = "Shell Pearl",
		icon = "🐚",
		colors = { base = { 70, 130, 140 }, trim = { 250, 240, 225 } },
		description = "A Map reward for finishing the coast road.",
		flavorText = "Still sounds faintly of the tide.",
	},
	{
		id = "frost_walker",
		name = "Frost Walker",
		icon = "❄",
		colors = { base = { 90, 120, 160 }, trim = { 235, 244, 255 } },
		description = "A Map reward for finishing the snow road.",
		flavorText = "Each flake is different, and so is every hand dealt.",
	},
	{
		id = "gala",
		name = "Gala Night",
		icon = "👑",
		colors = { base = { 110, 30, 50 }, trim = { 255, 215, 120 } },
		description = "A Map reward for reaching the Keeper's Table.",
		flavorText = "Dealt only at the grandest table of the tavern.",
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
