--[[
	Synergy.lua
	Why a Patron fits your build: pure helper for the small glowing tags in the Counter and in pack picks. No gameplay
	effect, display only. Pure Lua, no Roblox APIs.

	Every Patron has 1 to 3 `tags` (Engine/Patrons.lua, PATRON_TAGS). A tag is shown on an offered Patron when:
	  1. it matches your dominant hand (the hand type you have played most this run), or
	  2. it is "economy" and you own no economy Patron yet, or
	  3. you already own a Patron with that tag (they work together).
	At most 2 tags are returned, in that priority. "flat" (steady bonuses that fit everything) is never shown.
	Each tag is an icon plus one word, with one hover line.
]]

local Patrons = require(script.Parent.Patrons)

local Synergy = {}

Synergy.MAX_TAGS = 2

Synergy.Tags = {
	flush = { icon = "🌊", word = "Flush", line = "Scores from suits." },
	pairs = { icon = "👯", word = "Pairs", line = "Scores from pairs and sets." },
	straight = { icon = "📏", word = "Straight", line = "Scores from straights." },
	economy = { icon = "🪙", word = "Economy", line = "Earns or saves Tips." },
	scaling = { icon = "📈", word = "Scaling", line = "Grows as the run goes on." },
	rulebender = { icon = "🔧", word = "Rules", line = "Changes your hands, discards or cards." },
	ranks = { icon = "👑", word = "Ranks", line = "Scores from certain ranks and faces." },
	flat = { icon = "⭐", word = "Steady", line = "A bonus that always works." },
	marks = { icon = "🔖", word = "Marks", line = "Scores from marked cards." },
}

-- Which Patron tags a poker hand type feeds.
Synergy.HandTags = {
	["Pair"] = { "pairs" }, ["Two Pair"] = { "pairs" }, ["Three of a Kind"] = { "pairs" }, ["Four of a Kind"] = { "pairs" },
	["Full House"] = { "pairs" }, ["Straight"] = { "straight" }, ["Flush"] = { "flush" },
	["Straight Flush"] = { "straight", "flush" },
}

-- { [tag] = how many of these Patrons carry it }. Accepts Patron definitions or { id = ... } entries.
function Synergy.ownedTags(owned)
	local counts = {}
	for _, entry in ipairs(owned or {}) do
		local def = entry.tags and entry or Patrons.getById(entry.id)
		for _, tag in ipairs((def and def.tags) or {}) do
			counts[tag] = (counts[tag] or 0) + 1
		end
	end
	return counts
end

-- The hand type played most this run (ties go to the alphabetically first name), or nil before any hand.
function Synergy.dominantHand(handStats)
	local best, bestCount
	for name, count in pairs(handStats or {}) do
		if type(count) == "number" and count > 0 and Synergy.HandTags[name]
			and (not best or count > bestCount or (count == bestCount and name < best)) then
			best, bestCount = name, count
		end
	end
	return best
end

-- The tags your dominant hand feeds, as a set.
function Synergy.dominantTags(handStats)
	local set = {}
	local hand = Synergy.dominantHand(handStats)
	for _, tag in ipairs(hand and Synergy.HandTags[hand] or {}) do
		set[tag] = true
	end
	return set
end

-- Builds the context once per Counter rebuild.
function Synergy.context(owned, handStats)
	local counts = Synergy.ownedTags(owned)
	return { ownedCounts = counts, dominant = Synergy.dominantTags(handStats), ownsEconomy = (counts.economy or 0) > 0 }
end

-- Up to MAX_TAGS tags for an offered Patron (definition or { id }): { { tag, icon, word, line, reason } }.
function Synergy.tagsFor(patron, ctx)
	local def = patron and (patron.tags and patron or Patrons.getById(patron.id))
	if not def or not def.tags or not ctx then
		return {}
	end
	local out, used = {}, {}
	local function add(tag, reason)
		local info = Synergy.Tags[tag]
		if info and tag ~= "flat" and not used[tag] and #out < Synergy.MAX_TAGS then
			used[tag] = true
			out[#out + 1] = { tag = tag, icon = info.icon, word = info.word, line = info.line, reason = reason }
		end
	end
	for _, tag in ipairs(def.tags) do
		if ctx.dominant and ctx.dominant[tag] then add(tag, "Fits the hand you play most.") end
	end
	for _, tag in ipairs(def.tags) do
		if tag == "economy" and not ctx.ownsEconomy then add(tag, "You have no Tips Patron yet.") end
	end
	for _, tag in ipairs(def.tags) do
		local n = ctx.ownedCounts and ctx.ownedCounts[tag] or 0
		if n > 0 then add(tag, n == 1 and "Works with a Patron you own." or ("Works with " .. n .. " Patrons you own.")) end
	end
	return out
end

-- Registry check for the tests: every Patron has 1 to 3 known tags, no repeats.
function Synergy.validate()
	local problems = {}
	for _, patron in ipairs(Patrons.Definitions) do
		local tags = patron.tags
		if type(tags) ~= "table" or #tags < 1 or #tags > 3 then
			problems[#problems + 1] = patron.id .. ": needs 1 to 3 tags"
		else
			local seen = {}
			for _, tag in ipairs(tags) do
				if not Synergy.Tags[tag] then problems[#problems + 1] = patron.id .. ": unknown tag " .. tostring(tag) end
				if seen[tag] then problems[#problems + 1] = patron.id .. ": repeated tag " .. tag end
				seen[tag] = true
			end
		end
	end
	return problems
end

return Synergy
