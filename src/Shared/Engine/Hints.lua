--[[
	Hints.lua
	First time hints: each new system is explained once, in one line, the first time it matters. Pure Lua, no Roblox APIs.
	The client (Client/FirstTimeHints.lua) asks `Hints.dueFor` on every state update and shows at most one painted bubble
	with an arrow at its target; the server stores which hints were shown (profile.hintsSeen) and Settings > Replay Hints
	clears the set.

	Rules (all tested):
	  * a hint is at most 12 words and names a target key the client resolves to a screen element;
	  * never twice (hintsSeen), never during the forced tutorial (state.isTutorial), never while another hint is up;
	  * the trigger reads plain state fields plus a small `ctx` of panels the player just opened:
	      ctx.runSetupOpen, ctx.questsOpen, ctx.seasonOpen
	Profile field: hintsSeen = { [hint id] = true }, cleaned on load (unknown ids are dropped, so hints can be renamed).
]]

local Hints = {}

Hints.MAX_WORDS = 12
Hints.SHOW_SECONDS = 6

local function count(list)
	return type(list) == "table" and #list or 0
end

-- `trigger(state, ctx)` is true when the hint is relevant right now. `text` marks the words to highlight with [ ].
Hints.Definitions = {
	{ id = "first_score", icon = "✨", target = "score", text = "[Chips] times [Mult] is your hand's score.",
		trigger = function(state) return state.phase == "playing" and (state.handsPlayedTotal or 0) >= 1 end },
	{ id = "first_patron", icon = "🧑‍🍳", target = "patrons", text = "Patrons score for you every hand. Keep them happy.",
		trigger = function(state) return count(state.ownedPatrons) >= 1 end },
	{ id = "first_recipe", icon = "📖", target = "recipes", text = "Recipes are one-use boosts. Use one from the shop.",
		trigger = function(state)
			return count(state.houseRecipeInventory) + count(state.menuRecipeInventory) + count(state.secretRecipeInventory) >= 1
		end },
	{ id = "first_boss", icon = "👑", target = "boss", text = "The Boss has a rule. Read it before you play.",
		trigger = function(state) return state.phase == "playing" and state.bossModifier ~= nil end },
	{ id = "first_stakes", icon = "🏅", target = "stakes", text = "Win to unlock harder stakes with better bragging rights.",
		trigger = function(_, ctx) return ctx and ctx.runSetupOpen == true end },
	{ id = "first_counter", icon = "🛒", target = "counter", text = "Spend Tips here on Patrons, Packs and Recipes.",
		trigger = function(state) return state.phase == "shop" end },
	{ id = "first_quests", icon = "📜", target = "quests", text = "Three new quests every day. Finish them for XP.",
		trigger = function(_, ctx) return ctx and ctx.questsOpen == true end },
	{ id = "first_season", icon = "🎟️", target = "season", text = "Earn XP all month to claim season rewards.",
		trigger = function(_, ctx) return ctx and ctx.seasonOpen == true end },
	{ id = "first_discovery", icon = "🔭", target = "map", text = "You found a hidden spot on the map!",
		trigger = function(state) return type(state.discoveries) == "table" and (state.discoveries.found or 0) >= 1 end },
	{ id = "first_interest", icon = "🪙", target = "tips", text = "Saved Tips earn interest at the end of each round.",
		trigger = function(state) return (state.lastInterest or 0) > 0 end },
	-- the first three rounds layer (Engine/RoundHints, Client/RoundHintsFX): shown on the table plate, never as a bubble, so no trigger here;
	-- they live in this list only so hintsSeen stores them and Replay Hints clears them
	{ id = "round_hint_select", icon = "🃏", target = "table", text = "Tap up to five cards, then press Play Hand.", trigger = function() return false end },
	{ id = "round_hint_tiers", icon = "👑", target = "table", text = "The frame shows power: wood is Common, gold is Legendary.", trigger = function() return false end },
	{ id = "round_hint_target", icon = "🎯", target = "table", text = "Reach the Target score before your hands run out.", trigger = function() return false end },
}

local BY_ID = {}
for _, hint in ipairs(Hints.Definitions) do
	BY_ID[hint.id] = hint
end

function Hints.getById(id)
	return BY_ID[id]
end

-- Words of a hint, ignoring the [ ] highlight marks.
function Hints.wordCount(text)
	local n = 0
	for _ in tostring(text):gsub("[%[%]]", ""):gmatch("%S+") do
		n = n + 1
	end
	return n
end

-- The first hint that is due and unseen, or nil. `seen` is profile.hintsSeen (a set). Nothing shows in the tutorial.
function Hints.dueFor(state, seen, ctx)
	if type(state) ~= "table" or state.isTutorial == true then
		return nil
	end
	seen = type(seen) == "table" and seen or {}
	for _, hint in ipairs(Hints.Definitions) do
		if not seen[hint.id] then
			local ok, due = pcall(hint.trigger, state, ctx or {})
			if ok and due then
				return hint
			end
		end
	end
	return nil
end

-- Marks one hint seen (server side). Unknown ids are refused. Returns true when it was newly marked.
function Hints.markSeen(profile, id)
	if type(id) ~= "string" or not BY_ID[id] then
		return false
	end
	profile.hintsSeen = profile.hintsSeen or {}
	if profile.hintsSeen[id] then
		return false
	end
	profile.hintsSeen[id] = true
	return true
end

-- Settings > Replay Hints.
function Hints.reset(profile)
	profile.hintsSeen = {}
end

function Hints.cleanSaved(raw)
	local out = {}
	if type(raw) == "table" then
		for id, flag in pairs(raw) do
			if flag == true and type(id) == "string" and BY_ID[id] then
				out[id] = true
			end
		end
	end
	return out
end

return Hints
