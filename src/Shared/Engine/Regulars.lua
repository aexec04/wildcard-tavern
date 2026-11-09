--[[
	Shared/Engine/Regulars.lua
	Tavern Regulars: the Menu remembers you. Defeated bosses and Patrons you won a run with sit at tables in the lobby
	(at most 6 shown, the most recent first). No gameplay power.

	A Regular exists only if the player earned it: RunHistory.recordBoss adds "boss:<id>" the first time you clear that
	Boss Round, RunHistory.record adds "patron:<id>" the first time you win a run with that Patron. Both live in
	profile.lifetime.regulars (oldest first) next to the win and loss records.

	Regulars.view(lifetime, dayIndex) -> { { key, kind, id, name, icon, greeting, story, wins, losses }, ... }
	Pure Lua, no Roblox APIs.
]]

local Patrons = require(script.Parent.Patrons)
local BossRounds = require(script.Parent.BossRounds)
local RegularLines = require(script.Parent.RegularLines)

local Regulars = {}

Regulars.MAX_SHOWN = 6

-- Splits "boss:slow_night" into "boss", "slow_night".
function Regulars.parse(key)
	if type(key) ~= "string" then return nil end
	local kind, id = key:match("^(%a+):(.+)$")
	if (kind == "boss" or kind == "patron") and id then
		return kind, id
	end
	return nil
end

-- The keys to show: newest first, only ones that still exist in the registries, at most `max`.
function Regulars.select(lifetime, max)
	max = max or Regulars.MAX_SHOWN
	local out = {}
	local list = (lifetime and lifetime.regulars) or {}
	for i = #list, 1, -1 do
		local kind, id = Regulars.parse(list[i])
		local def = kind == "boss" and BossRounds.getById(id) or kind == "patron" and Patrons.getById(id) or nil
		if def then
			out[#out + 1] = list[i]
			if #out >= max then break end
		end
	end
	return out
end

function Regulars.view(lifetime, dayIndex)
	local out = {}
	for _, key in ipairs(Regulars.select(lifetime, Regulars.MAX_SHOWN)) do
		local kind, id = Regulars.parse(key)
		local def = kind == "boss" and BossRounds.getById(id) or Patrons.getById(id)
		local wins, losses
		if kind == "boss" then
			local rec = lifetime.bossRecord and lifetime.bossRecord[id]
			wins, losses = rec and rec.w or 0, rec and rec.l or 0
		else
			wins = lifetime.patronWins and lifetime.patronWins[id] or 0
		end
		out[#out + 1] = {
			key = key, kind = kind, id = id, name = def.name, icon = def.icon,
			greeting = RegularLines.greeting(kind, id, dayIndex),
			story = def.flavorText or def.description or "",
			wins = wins, losses = losses, -- losses only for bosses
		}
	end
	return out
end

return Regulars
