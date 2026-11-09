--[[
	CardBacks.lua
	Cosmetic card backs. Right now the only way to unlock one is a
	Collection milestone (CollectionBook.Milestones); unlocked ids are kept
	in PlayerProfile.unlockedCardBackIds. Cosmetic Sets (CosmeticSets.lua) pick which back is shown;
	`setOnly` backs come only from a set.

	`colors` are {r, g, b} triples (0-255) so this file stays pure Lua.

	The ornate frame and plate behind the draw pile follow the equipped back: `pileStyle(back)` gives
	{ rim, plate, glow } colours. A back may set `pile = { rim, plate, glow }` itself (classic keeps the
	warm wood and gold, Gilded Ledger is gold, Winter Frost is frosted blue); any other back, including
	every back added later, gets one derived from its `colors` (rim = trim, plate = base darkened, glow =
	trim), so new backs look right for free. The count pill stays dark and readable on every plate.
]]

local CardBacks = {}

CardBacks.DefaultId = "classic"

local WOOD_PLATE = { 34, 22, 13 }

local function mix(a, b, t)
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

-- Pile frame colours for a back table (or nil -> the default warm wood and gold).
function CardBacks.pileStyle(back)
	if back and back.pile then
		return back.pile
	end
	local colors = back and back.colors
	if not colors then
		return { rim = { 205, 170, 95 }, plate = WOOD_PLATE, glow = { 235, 200, 120 } }
	end
	return {
		rim = colors.trim,
		plate = mix(colors.base, { 14, 10, 7 }, 0.72), -- the back's own colour, kept dark so the count reads
		glow = mix(colors.trim, { 255, 255, 255 }, 0.2),
	}
end

CardBacks.Definitions = {
	{
		id = "classic",
		name = "Classic Blue",
		icon = "🂠",
		colors = { base = { 50, 70, 110 }, trim = { 220, 190, 120 } },
		pile = { rim = { 205, 170, 95 }, plate = { 34, 22, 13 }, glow = { 235, 200, 120 } }, -- warm wood and gold: today's frame
		description = "The tavern's everyday deck.",
		flavorText = "Worn soft at the corners from a thousand friendly games.",
	},
	{
		id = "gilded_ledger",
		name = "Gilded Ledger",
		icon = "📜",
		colors = { base = { 120, 85, 40 }, trim = { 250, 215, 130 } },
		pile = { rim = { 250, 215, 130 }, plate = { 62, 44, 18 }, glow = { 255, 232, 160 } }, -- gold
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
		pile = { rim = { 190, 215, 245 }, plate = { 28, 42, 64 }, glow = { 220, 238, 255 } }, -- frosted blue
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
	-- Seasonal reward (Engine/Seasons.lua): earned during the Winter Lanterns season.
	{
		id = "winter_lanterns",
		name = "Winter Lanterns",
		icon = "🏮",
		colors = { base = { 40, 50, 95 }, trim = { 255, 200, 110 } },
		description = "A seasonal reward: clear 3 Nights in one run during Winter Lanterns.",
		flavorText = "Strung up for the longest nights of the year.",
		seasonal = true,
	},
	-- Tavern Season PREMIUM finals (Engine/SeasonTrack.lua premium tier 30): only premium owners of that season.
	{
		id = "harvest_premium",
		name = "Harvest Gold",
		icon = "🌾",
		colors = { base = { 150, 90, 30 }, trim = { 255, 226, 150 } },
		description = "A Tavern Season premium reward: tier 30 of the Harvest Moon premium row.",
		flavorText = "Gold wheat under a gold moon.",
		seasonal = true,
	},
	{
		id = "winter_premium",
		name = "Winter Silver",
		icon = "❄",
		colors = { base = { 40, 70, 120 }, trim = { 235, 242, 255 } },
		description = "A Tavern Season premium reward: tier 30 of the Winter Welcome premium row.",
		flavorText = "Frost-silver stitched by candlelight.",
		seasonal = true,
	},
	-- Legend prestige rewards (Engine/Legend.lua levels 3, 7 and 10): cosmetic only.
	{
		id = "legend_gold",
		name = "Legend Gold",
		icon = "🥇",
		colors = { base = { 90, 60, 20 }, trim = { 255, 220, 120 } },
		description = "A Legend reward: reach Legend level 3.",
		flavorText = "Stamped in real tavern gold.",
		seasonal = true,
	},
	{
		id = "legend_crown",
		name = "Legend Crown",
		icon = "👑",
		colors = { base = { 60, 30, 80 }, trim = { 255, 230, 150 } },
		description = "A Legend reward: reach Legend level 7.",
		flavorText = "Only worn by those who finished the hardest night.",
		seasonal = true,
	},
	{
		id = "legend_eternal",
		name = "Eternal Legend",
		icon = "🌟",
		colors = { base = { 20, 20, 40 }, trim = { 255, 245, 200 } },
		description = "A Legend reward: reach Legend level 10.",
		flavorText = "The last candle never goes out.",
		seasonal = true,
	},
	-- Tavern Season track finals (Engine/SeasonTrack.lua): tier 30 of that season only.
	{
		id = "harvest_moon",
		name = "Harvest Moon",
		icon = "🌕",
		colors = { base = { 120, 70, 30 }, trim = { 255, 214, 130 } },
		description = "A Tavern Season reward: reach tier 30 of the Harvest Moon season.",
		flavorText = "A big golden moon over a field of lanterns.",
		seasonal = true,
	},
	{
		id = "winter_welcome",
		name = "Winter Welcome",
		icon = "🧣",
		colors = { base = { 50, 80, 130 }, trim = { 240, 245, 255 } },
		description = "A Tavern Season reward: reach tier 30 of the Winter Welcome season.",
		flavorText = "Woven from warm scarves and cold stars.",
		seasonal = true,
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
