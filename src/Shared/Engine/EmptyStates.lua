--[[
	Shared/Engine/EmptyStates.lua
	The short lines (and ghost icons) for empty pages, in ONE editable table. Each line is 3 to 6 words, with
	no explaining after a dash: no em dashes and no double dashes (tested). The hint about how to fill the page
	lives in the hover tooltip, not on the page. Client/ShopCards.emptyScene draws the page.

	line(key) -> string     icons(key) -> { emoji, emoji, emoji } for the three ghost cards
]]

local EmptyStates = {}

EmptyStates.Lines = {
	patrons = "Your table is quiet",
	recipes = "Nothing cooking yet",
	housePasses = "No passes in your pocket",
	offers = "The shelves are bare today",
	seat = "An open seat awaits",
}

EmptyStates.Icons = {
	patrons = { "🎩", "🎻", "🧑‍🍳" },
	recipes = { "🍲", "🥧", "🍞" },
	housePasses = { "🎟️", "🔑", "📜" },
	offers = { "🎩", "🍲", "🎁" },
}

-- Where the missing thing comes from (hover tooltip text, never printed on the page).
EmptyStates.Hints = {
	patrons = "Recruit Patrons in the Shop tab.",
	recipes = "Open Packs to find Recipes.",
	housePasses = "Buy House Passes in the Shop tab.",
	offers = "You have met everyone available so far.",
	seat = "Visit The Counter to recruit a Patron.",
}

-- One friendly line per screen that can be empty or fail to load. Drawn in the painted serif (EmptyStates.FONT) on the
-- screen's own panel, so a panel is never blank. Plain words, no dashes (tested).
EmptyStates.FONT = "Merriweather"
EmptyStates.Screens = {
	quests = "No quests posted yet. Check back soon.",
	questsLoading = "The quest board is being written up.",
	questsDone = "All quests done. Rest your feet.",
	offlineSave = "Playing offline. Your progress waits safely here.",
	loadFailed = "The tavern door is stuck. Try again in a moment.",
	collection = "Your collection starts with your first card.",
	leaderboard = "Nobody has signed the board yet.",
	friends = "No friends here yet. Invite someone to the table.",
	badges = "Your first badge is waiting to be earned.",
	titles = "Earn a title and it will hang here.",
	season = "No season right now. Check back soon.",
	twistNone = "No twist today. Enjoy a normal Daily.",
	twistFailed = "Today's twist is hiding. Try again soon.",
	bossUnknown = "Boss rule: a surprise waits at the end.",
	ledgerRuns = "Nothing written yet. Go lose gracefully.",
}

-- Where each screen line is drawn (a file under src/, searched for the key or the table) or why it is held: a list that can never be empty
-- (locked entries stay on show) does not need a line yet. Tested, so a new line cannot be added without saying where it goes.
EmptyStates.Used = {
	quests = "src/Client/QuestsPanel.lua", questsLoading = "src/Client/QuestsPanel.lua", questsDone = "src/Client/QuestsPanel.lua",
	leaderboard = "src/Shared/Engine/LeaderboardText.lua", friends = "src/Shared/Engine/LeaderboardText.lua",
	twistNone = "src/Shared/Engine/TwistPreview.lua", bossUnknown = "src/Shared/Engine/MapSelectRules.lua",
	ledgerRuns = "src/Client/StatsRoom.lua",
	collection = "held: every Collection entry stays on show as a locked silhouette, so a tab is never empty",
	badges = "held: all 32 badges hang on the wall, locked ones as dark medals",
	titles = "held: Titles is a Collection section, and Collection sections keep locked entries on show",
	season = "src/Client/SeasonPanel.lua",
	offlineSave = "held: no offline banner exists yet",
	loadFailed = "held: the fallback for any screenLine key that is missing",
	twistFailed = "held: the twist popup falls back to twistNone",
}

function EmptyStates.screenLine(key)
	return EmptyStates.Screens[key] or EmptyStates.Screens.loadFailed
end

function EmptyStates.line(key)
	return EmptyStates.Lines[key] or EmptyStates.Lines.patrons
end

function EmptyStates.icons(key)
	return EmptyStates.Icons[key] or EmptyStates.Icons.patrons
end

function EmptyStates.hint(key)
	return EmptyStates.Hints[key] or ""
end

return EmptyStates
