--[[
	Shared/Engine/PanelGroups.lua
	Pure data for the account panel navigation (Client/PanelTabs.lua): three tavern furniture groups, each with
	the pages inside it. Every page belongs to exactly one group; opening any page opens its group.

	  The Tome       (leather brown)  Collection, Card Sets, Badges, Legend, Flair, Stats
	  The Strongbox  (deep green)     Rewards, Daily, Quests, Season
	  The Coin Jar   (brass)          Store

	Page ids match OverlayManager.register / registerOpener names. `art` is { category, key } for the painted group
	icon (the UI falls back to `emoji` while the id is empty). Colours are {r, g, b}.
]]

local PanelGroups = {}

PanelGroups.GROUPS = {
	{
		id = "tome", text = "The Tome", emoji = "📖", art = { "menu_scene", "menu_item_tome" },
		color = { 112, 72, 40 }, glow = { 150, 104, 60 },
		pages = {
			{ id = "collection", text = "Collection", emoji = "🃏" },
			{ id = "cosmeticSets", text = "Card Sets", emoji = "🎴" },
			{ id = "badges", text = "Badges", emoji = "🏅" },
			{ id = "legend", text = "Legend", emoji = "👑" },
			{ id = "flair", text = "Flair", emoji = "✨" },
			{ id = "stats", text = "Stats", emoji = "📊" },
		},
	},
	{
		id = "strongbox", text = "The Strongbox", emoji = "🧰", art = { "menu_icons", "daily" },
		color = { 40, 92, 60 }, glow = { 70, 138, 92 },
		pages = {
			{ id = "collectionRewards", text = "Rewards", emoji = "🎁" },
			{ id = "dailyRewards", text = "Daily", emoji = "📅", art = { "menu_icons", "daily" } },
			{ id = "quests", text = "Quests", emoji = "📜", art = { "menu_icons", "quests" } },
			{ id = "season", text = "Season", emoji = "🍂" },
		},
	},
	{
		id = "coinjar", text = "The Coin Jar", emoji = "🫙", art = { "menu_icons", "menu_coinjar" },
		color = { 176, 132, 48 }, glow = { 222, 182, 104 },
		pages = {
			{ id = "store", text = "Store", emoji = "🪙", art = { "menu_icons", "store" } },
		},
	},
}

function PanelGroups.groupOf(pageId)
	for _, g in ipairs(PanelGroups.GROUPS) do
		for _, p in ipairs(g.pages) do
			if p.id == pageId then return g end
		end
	end
	return nil
end

function PanelGroups.group(groupId)
	for _, g in ipairs(PanelGroups.GROUPS) do
		if g.id == groupId then return g end
	end
	return nil
end

-- Flat page list in display order (group order, then page order inside the group).
function PanelGroups.pages()
	local out = {}
	for _, g in ipairs(PanelGroups.GROUPS) do
		for _, p in ipairs(g.pages) do out[#out + 1] = p end
	end
	return out
end

-- The page a group tab opens: the first page of the group.
function PanelGroups.defaultPage(groupId)
	local g = PanelGroups.group(groupId)
	return g and g.pages[1].id or nil
end

return PanelGroups
