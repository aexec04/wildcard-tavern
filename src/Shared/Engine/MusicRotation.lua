--[[
	Shared/Engine/MusicRotation.lua
	The tavern music library, pure and tested (Client/Sound plays it, Engine/MusicPicker lists it).

	  TAVERN               the rotation for the menu, the table and the map: { key, name, length } in play order
	  BOSS                 the two Boss Round tracks, played one after the other while a Boss Round is active
	  nextTavern(prevKey, rand)   a random tavern key that is never prevKey (rand(n) -> 1..n, default math.random)
	  nextBoss(prevKey)           the other boss key (starts with the first)
	  isRotationKey(key)          true for the keys that rotate: menu, title, gameplay, map and the region beds
	  isBossKey(key)              true for the boss keys
	  JINGLES                     moment -> cue name: run, boss, round
	  jingleFor(event)            the cue for "run_complete", "victory_screen", "boss_cleared", "round_cleared", else nil
	  JingleGate.new()            :take(event, id) -> true once per (event, id); a second ask for the same moment is false
]]

local M = {}

-- in-game names; no alcohol words anywhere (the Creator Store title "The Ale and the Dragon" is shown as "The Dragon's Hearth")
M.TAVERN = {
	{ key = "lantern_waltz", name = "Lantern Waltz", length = 194 },
	{ key = "midnight_fiddle", name = "Midnight Fiddle", length = 139 },
	{ key = "harvest_jig", name = "Harvest Jig", length = 150 },
	{ key = "dragons_breath_inn", name = "Dragon's Breath Inn", length = 138 },
	{ key = "dragon_hearth", name = "The Dragon's Hearth", length = 185 },
	{ key = "through_the_trees", name = "Through the Trees", length = 205 },
	{ key = "would_have_followed", name = "I Would Have Followed", length = 159 },
}

M.BOSS = {
	{ key = "boss", name = "Boss Theme", length = 67 },
	{ key = "boss_b", name = "Forces of Nature", length = 122 },
}

M.VICTORY_NAME = "Victory Fanfare"

local TAVERN_SET, BOSS_SET = {}, {}
for _, t in ipairs(M.TAVERN) do TAVERN_SET[t.key] = true end
for _, t in ipairs(M.BOSS) do BOSS_SET[t.key] = true end

-- the screen keys that play the rotation (Engine/MusicMix beds)
local ROTATES = { menu = true, title = true, gameplay = true }
function M.isRotationKey(key)
	if ROTATES[key] or TAVERN_SET[key] then return true end
	return type(key) == "string" and string.sub(key, 1, 7) == "region_"
end

function M.isBossKey(key) return BOSS_SET[key] == true end

function M.nextTavern(prevKey, rand)
	rand = rand or math.random
	local pool = {}
	for _, t in ipairs(M.TAVERN) do
		if t.key ~= prevKey then pool[#pool + 1] = t.key end
	end
	return pool[rand(#pool)]
end

function M.nextBoss(prevKey)
	if prevKey == M.BOSS[1].key then return M.BOSS[2].key end
	return M.BOSS[1].key
end

M.JINGLES = { run = "jingle_run", boss = "jingle_boss", round = "jingle_round" }
local BY_EVENT = {
	run_complete = "jingle_run", victory_screen = "jingle_run",
	boss_cleared = "jingle_boss", round_cleared = "jingle_round",
}
function M.jingleFor(event) return BY_EVENT[event] end

-- a jingle plays once per moment: Run complete and the Victory screen are the same moment for one run, so a key such as the run id
-- makes the second ask a no-op
local Gate = {}
Gate.__index = Gate
function Gate:take(event, id)
	local cue = BY_EVENT[event]
	if not cue then return false end
	local slot = (cue == "jingle_run" and "run" or event) .. ":" .. tostring(id)
	if self.seen[slot] then return false end
	self.seen[slot] = true
	return true
end
M.JingleGate = { new = function() return setmetatable({ seen = {} }, Gate) end }

return M
