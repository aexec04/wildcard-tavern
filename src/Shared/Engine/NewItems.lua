--[[
	Engine/NewItems.lua
	"New" ribbons: a Patron, Card Set, Card Back or flair option the player has unlocked but not looked at yet.
	Pure and tested. The profile keeps one saved id set, seenNewIds ("kind:id" = true). Something is new when the profile owns it and
	its key is not in that set. Opening the item's screen marks it seen (server side, MarkSeenNew remote). Existing saves are seeded by
	PlayerProfile.migrate so nobody sees a flood of ribbons on the first load.

	key(kind, id)             -> "patron:the_regular"; kinds: patron, set, back, flair
	owned(profile)            -> { [key] = true } everything the profile has unlocked (defaults left out)
	pending(profile)          -> sorted array of keys that are new
	isNew(profile, kind, id)  -> boolean
	markSeen(profile, keys)   -> count marked; only keys the profile really owns are accepted (a client can not invent ids)
	seed(profile)             -> marks everything currently owned as seen
]]

local Flair = require(script.Parent.Flair)
local CosmeticSets = require(script.Parent.CosmeticSets)

local M = {}
M.KINDS = { patron = true, set = true, back = true, flair = true }
M.MAX_KEYS = 40 -- most keys one mark request may carry

function M.key(kind, id)
	return tostring(kind) .. ":" .. tostring(id)
end

function M.owned(profile)
	local out = {}
	if type(profile) ~= "table" then return out end
	local function take(kind, set)
		for id, flag in pairs(type(set) == "table" and set or {}) do
			if flag == true and type(id) == "string" then out[M.key(kind, id)] = true end
		end
	end
	take("patron", profile.discoveredPatronIds)
	take("back", profile.unlockedCardBackIds)
	for id, flag in pairs(type(profile.ownedSetIds) == "table" and profile.ownedSetIds or {}) do
		if flag == true and type(id) == "string" and id ~= CosmeticSets.DefaultId then out[M.key("set", id)] = true end
	end
	for _, slot in ipairs(Flair.Slots) do
		for _, option in ipairs(Flair.optionsFor(slot.id)) do
			if not option.default and Flair.isOwned(profile, option.id) then out[M.key("flair", option.id)] = true end
		end
	end
	return out
end

local function seen(profile)
	return type(profile.seenNewIds) == "table" and profile.seenNewIds or {}
end

function M.isNew(profile, kind, id)
	if type(profile) ~= "table" then return false end
	local key = M.key(kind, id)
	return M.owned(profile)[key] == true and seen(profile)[key] ~= true
end

function M.pending(profile)
	local out = {}
	if type(profile) ~= "table" then return out end
	local s = seen(profile)
	for key in pairs(M.owned(profile)) do
		if s[key] ~= true then out[#out + 1] = key end
	end
	table.sort(out)
	return out
end

function M.markSeen(profile, keys)
	if type(profile) ~= "table" or type(keys) ~= "table" then return 0 end
	if type(profile.seenNewIds) ~= "table" then profile.seenNewIds = {} end
	local owned, n = M.owned(profile), 0
	for i, key in ipairs(keys) do
		if i > M.MAX_KEYS then break end
		if type(key) == "string" and #key <= 80 and owned[key] and profile.seenNewIds[key] ~= true then
			profile.seenNewIds[key] = true
			n = n + 1
		end
	end
	return n
end

function M.seed(profile)
	profile.seenNewIds = {}
	for key in pairs(M.owned(profile)) do profile.seenNewIds[key] = true end
end

return M
