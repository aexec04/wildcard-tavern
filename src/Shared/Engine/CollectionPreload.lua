--[[
	Engine/CollectionPreload.lua
	The art the Collection needs, as ContentArt preload items, so opening it warms every sub-tab before the first click (no pop-in).
	Pure lists; Client/Collection feeds them to ContentArt.preload in small batches.

	items()             -> { { category }, ... } for Patrons, Recipes, Boss Rounds, House Passes, Titles, Bonds and the painted scenes
	urls(ContentArt)    -> the deduplicated, non-empty urls those items resolve to (ContentArt.collectUrls)
	batches(urls, size) -> the urls cut into batches of `size` (default 20)
]]

local CollectionPreload = {}

CollectionPreload.CATEGORIES = { "patrons", "recipes", "boss_rounds", "house_passes", "titles", "bonds", "collection_scene" }
CollectionPreload.BATCH = 20

function CollectionPreload.items()
	local out = {}
	for _, c in ipairs(CollectionPreload.CATEGORIES) do out[#out + 1] = { c } end
	return out
end

function CollectionPreload.urls(ContentArt)
	return ContentArt.collectUrls(CollectionPreload.items())
end

function CollectionPreload.batches(urls, size)
	size = math.max(1, math.floor(size or CollectionPreload.BATCH))
	local out = {}
	for i = 1, #urls, size do
		local b = {}
		for j = i, math.min(i + size - 1, #urls) do b[#b + 1] = urls[j] end
		out[#out + 1] = b
	end
	return out
end

return CollectionPreload
