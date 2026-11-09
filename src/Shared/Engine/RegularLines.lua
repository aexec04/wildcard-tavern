--[[
	Shared/Engine/RegularLines.lua
	One short greeting per Tavern Regular (Engine/Regulars.lua), shown when you hover them in the Menu. The greeting
	rotates once per UTC day: RegularLines.greeting(kind, id, dayIndex) is deterministic.
	Kid-safe, 60 characters or fewer, no dashes (tested).
]]

local RegularLines = {}

RegularLines.Greetings = {
	boss = {
		"Good rematch, friend!",
		"You beat me fair and square.",
		"Pull up a chair!",
		"I still remember that hand.",
		"No hard feelings here!",
		"Care for another round?",
		"Your table, your rules today.",
		"I saved you a seat.",
	},
	patron = {
		"Great run together!",
		"Table for two again?",
		"I am glad you came back!",
		"Winning looks good on you.",
		"Say the word and I will deal in.",
		"The soup is hot today!",
		"We make a fine team.",
		"Cards are lucky tonight!",
	},
}

local function hash(text)
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

function RegularLines.greeting(kind, id, dayIndex)
	local pool = RegularLines.Greetings[kind] or RegularLines.Greetings.patron
	local day = math.floor(tonumber(dayIndex) or 0)
	return pool[((hash(tostring(id)) + day) % #pool) + 1]
end

return RegularLines
