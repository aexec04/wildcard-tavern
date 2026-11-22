--[[
	StartingDecks.lua
	The card pool a run starts with, picked on the pre run screen. Data only, pure Lua, no Roblox APIs.

	  classic  52 cards, the normal deck. Always open.
	  lucky    56 cards: the normal deck plus one extra King of every suit. Open once you have reached Night 3.
	  slim     40 cards: the 2s, 3s and 4s are taken out, so hands come up bigger. Open once you have reached Night 5.

	The server validates the pick (StartingDecks.resolve), never the client: a locked or unknown id falls back to classic.
	Daily, Weekly, Seed and the tutorial always use classic (fair boards). Never pay to win: both unlocks are earned by
	reaching a Night, nothing is sold.

	Fields: id, name, icon, text (one short kid safe line), unlockNight, remove = { [rank] = true }, extra = { rank, ... } (one per suit), configDelta = { key = delta } added to the run config (Slim: 1 fewer Discard, the balance cost of better hands).
]]

local Card = require(script.Parent.Card)

local StartingDecks = {}

StartingDecks.DefaultId = "classic"

StartingDecks.Definitions = {
	{ id = "classic", name = "Classic Deck", icon = "🃏", text = "The full 52 cards. A safe, balanced start.", unlockNight = 0, size = 52 },
	{ id = "lucky", name = "Lucky Deck", icon = "🍀", text = "56 cards: an extra King of every suit.", unlockNight = 3, size = 56, extra = { 13 } },
	{ id = "slim", name = "Slim Deck", icon = "✂️", text = "40 cards, no 2s, 3s or 4s, but 1 fewer Discard.", unlockNight = 5, size = 40, configDelta = { discardsPerRound = -1 }, remove = { [2] = true, [3] = true, [4] = true } },
}

function StartingDecks.getById(id)
	for _, def in ipairs(StartingDecks.Definitions) do
		if def.id == id then return def end
	end
	return nil
end

-- The best Night the profile has reached (0 when unknown).
local function bestNight(profile)
	return math.floor(tonumber(profile and profile.stats and profile.stats.bestNightReached) or 0)
end

function StartingDecks.isUnlocked(profile, id)
	local def = StartingDecks.getById(id)
	if not def then return false end
	return bestNight(profile) >= def.unlockNight
end

function StartingDecks.unlockHint(id)
	local def = StartingDecks.getById(id)
	if not def or def.unlockNight <= 0 then return "" end
	return "Reach Night " .. def.unlockNight .. " to open this deck."
end

-- The id a run really starts with: the asked one if it exists and is open to this profile, else classic.
function StartingDecks.resolve(profile, id)
	if type(id) == "string" and StartingDecks.isUnlocked(profile, id) then return id end
	return StartingDecks.DefaultId
end

-- Builds the unshuffled cards of a deck (fresh Card tables every call). An unknown id gives the classic deck.
function StartingDecks.build(id)
	local def = StartingDecks.getById(id) or StartingDecks.getById(StartingDecks.DefaultId)
	local deck = {}
	for _, suit in ipairs(Card.Suits) do
		for rank = 2, 14 do
			if not (def.remove and def.remove[rank]) then
				deck[#deck + 1] = Card.new(rank, suit)
			end
		end
		for _, rank in ipairs(def.extra or {}) do
			deck[#deck + 1] = Card.new(rank, suit)
		end
	end
	return deck
end

-- What the pre run screen draws: one row per deck, with whether it is open.
function StartingDecks.view(profile)
	local rows = {}
	for _, def in ipairs(StartingDecks.Definitions) do
		local open = StartingDecks.isUnlocked(profile, def.id)
		rows[#rows + 1] = { id = def.id, name = def.name, icon = def.icon, text = def.text, size = def.size, open = open, hint = open and "" or StartingDecks.unlockHint(def.id) }
	end
	return rows
end

return StartingDecks
