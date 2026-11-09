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
	housePasses = "Buy Vouchers in the Shop tab.",
	offers = "You have met everyone available so far.",
	seat = "Visit The Counter to recruit a Patron.",
}

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
