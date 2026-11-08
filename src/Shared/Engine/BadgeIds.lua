--[[
	Shared/Engine/BadgeIds.lua
	Maps a game Badge id (Engine/Badges.lua) to the id of the matching real Roblox Badge.

	An entry stays ABSENT (nil) until you create the badge in Creator Hub (Create > your experience > Associated
	Items > Badges). While an id is missing the server skips that award silently, so shipping without any real
	Roblox Badges is fine. To switch one on, add a line, for example:

	    BadgeIds.wins_1 = 123456789

	Ids are numbers (never put secrets here; badge ids are public). Names to create, one per game badge id:
	biome_<region> and master_<region> for meadow, river, peaks, desert, swamp, snow, coast, tavern; wins_1, wins_5,
	wins_25; night_3, night_5, night_8, night_10; minigame_1, minigame_10; collection_25, collection_50,
	collection_100; streak_3, streak_7, streak_14; season_winter_lanterns.
]]

local BadgeIds = {}

return BadgeIds
