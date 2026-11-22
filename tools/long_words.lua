--[[
	long_words.lua
	Reading level audit: walks the text fields of the content registries (Patrons, BossRounds, Recipes, Packs, HousePasses,
	Tags, Achievements, Quests, CosmeticSets, TutorialSteps) and lists every word of LIMIT letters or more.

		lua tools/long_words.lua [limit]
]]
local toolsDir = arg[0]:match("(.*)/long_words%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local E = EngineLoader.load(toolsDir .. "/../src/Shared")
local LIMIT = tonumber(arg[1]) or 11

local TEXT_FIELDS = { name = true, description = true, desc = true, flavorText = true, text = true, label = true, hint = true, line = true, title = true, summary = true, unlockText = true, detail = true, effectText = true }
local registries = { "Patrons", "BossRounds", "Recipes", "Packs", "HousePasses", "Tags", "Achievements", "Quests", "CosmeticSets", "TutorialSteps" }

local found = {}
local function scan(value, where, depth)
	if depth > 6 then return end
	if type(value) == "table" then
		for k, v in pairs(value) do
			if type(v) == "string" and (TEXT_FIELDS[k] or type(k) == "number") then
				for word in v:gmatch("[%a']+") do
					if #word >= LIMIT then
						local lower = word:lower()
						found[lower] = found[lower] or { count = 0, where = where }
						found[lower].count = found[lower].count + 1
					end
				end
			elseif type(v) == "table" then
				scan(v, where, depth + 1)
			end
		end
	end
end

for _, name in ipairs(registries) do
	local ok, mod = pcall(E.loadEngineModule, name)
	if ok and type(mod) == "table" then
		for k, v in pairs(mod) do
			if type(v) == "table" and (k == "Definitions" or k == "Steps" or k == "STEPS" or k:find("Recipes$") or k == "Definitions") then scan(v, name, 0) end
		end
	end
end

local words = {}
for w, info in pairs(found) do words[#words + 1] = { w = w, n = info.count, where = info.where } end
table.sort(words, function(a, b) if #a.w ~= #b.w then return #a.w > #b.w end return a.w < b.w end)
for _, r in ipairs(words) do print(string.format("%2d %-18s %2d  %s", #r.w, r.w, r.n, r.where)) end
print(#words .. " words of " .. LIMIT .. " letters or more")
