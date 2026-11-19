--[[
	Shared/Engine/SetBonuses.lua
	Patron set bonuses: three small rewards for building a team. Server-authoritative (Scoring applies them, once per hand).
	  * Tavern Circle: three owned Patrons that share one synergy tag (Bonds.Tags)  -> +2 Mult
	  * Rare Court:    three owned Rare or better Patrons                          -> x1.2
	  * Full Table:    this hand a Chips Patron, a Mult Patron and a Tips Patron all scored -> +1 Tip
	Each set is found at most once; its members are the first three Patrons (seat order) that qualify.
	Pure Lua, no Roblox APIs.

	SetBonuses.find(owned, bonuses) -> array of { id, name, members = { seatIndex x3 }, kind, amount }
	    owned = Patron defs or { id }; bonuses = optional [seat] = that Patron's effect result this hand (needed only for Full Table)
	SetBonuses.members(sets, seat) -> the sets a seat is part of
	SetBonuses.threads(sets) -> array of { a, b, setId } seat pairs to join with a gold thread
]]

local Patrons = require(script.Parent.Patrons)
local Bonds = require(script.Parent.Bonds)

local M = {}

M.Definitions = {
	{ id = "tavern_circle", name = "Tavern Circle", kind = "mult", amount = 2, line = "3 Patrons with one shared tag: +2 Mult" },
	{ id = "rare_court", name = "Rare Court", kind = "xmult", amount = 1.2, line = "3 Rare or better Patrons: x1.2 Mult" },
	{ id = "full_table", name = "Full Table", kind = "tips", amount = 1, line = "Chips, Mult and Tips Patrons all score: +1 Tip" },
}

local RANK = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, mythical = 6 }

local function defOf(entry)
	if entry.tags or entry.price then return entry end
	return Patrons.getById(entry.id) or entry
end

local function rarityRank(def)
	local ok, CollectionBook = pcall(require, script.Parent.CollectionBook)
	if not ok then return 1 end
	return RANK[CollectionBook.rarityOf({ tab = "patrons", id = def.id, def = def })] or 1
end

local function gave(b, field)
	if not b then return false end
	return (b[field] or 0) ~= 0
end

local function make(d, members, extra)
	local s = { id = d.id, name = d.name, kind = d.kind, amount = d.amount, line = d.line, members = members }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

function M.find(owned, bonuses)
	local out = {}
	owned = owned or {}
	-- Tavern Circle: first tag in Bonds.Tags order that three or more Patrons share
	for _, tag in ipairs(Bonds.Tags) do
		local members = {}
		for i, entry in ipairs(owned) do
			for _, t in ipairs(defOf(entry).tags or {}) do
				if t == tag then members[#members + 1] = i break end
			end
		end
		if #members >= 3 then
			out[#out + 1] = make(M.Definitions[1], { members[1], members[2], members[3] }, { tag = tag })
			break
		end
	end
	-- Rare Court
	local rare = {}
	for i, entry in ipairs(owned) do
		if rarityRank(defOf(entry)) >= RANK.rare then rare[#rare + 1] = i end
	end
	if #rare >= 3 then
		out[#out + 1] = make(M.Definitions[2], { rare[1], rare[2], rare[3] })
	end
	-- Full Table: three different Patrons that gave Chips, Mult and Tips this hand
	if bonuses then
		local pick, used = {}, {}
		for _, field in ipairs({ "chips", "mult", "tips" }) do
			for i = 1, #owned do
				if not used[i] and gave(bonuses[i], field) then
					pick[#pick + 1] = i
					used[i] = true
					break
				end
			end
		end
		if #pick == 3 then
			out[#out + 1] = make(M.Definitions[3], pick)
		end
	end
	return out
end

-- One plain line per formed set for plates and tooltips, e.g. "Tavern Circle: +2 Mult" (the effect is the part after the colon in `line`)
function M.lineOf(set)
	local effect = tostring(set.line or ""):match(":%s*(.+)$") or ""
	return set.name .. ": " .. effect
end

-- Sets formed by these owned Patron ids (Full Table needs a scored hand, so it shows only inside scoring), seat order
function M.formed(ownedIds)
	local list = {}
	for i, id in ipairs(ownedIds or {}) do list[i] = { id = id } end
	return M.find(list, nil)
end

function M.members(sets, seat)
	local out = {}
	for _, s in ipairs(sets or {}) do
		for _, m in ipairs(s.members) do
			if m == seat then
				out[#out + 1] = s
				break
			end
		end
	end
	return out
end

function M.threads(sets)
	local out = {}
	for _, s in ipairs(sets or {}) do
		local m = { s.members[1], s.members[2], s.members[3] }
		table.sort(m)
		out[#out + 1] = { a = m[1], b = m[2], setId = s.id }
		out[#out + 1] = { a = m[2], b = m[3], setId = s.id }
	end
	return out
end

return M
