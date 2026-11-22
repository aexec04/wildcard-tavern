-- Lists Patrons whose effect() never scores on plain contexts, with the rule/economy hooks they carry. Run: lua tools/_probe_dead.lua
local toolsDir = arg[0]:match("(.*)/_probe_dead%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local E = require("EngineLoader").load(toolsDir .. "/../src/Shared")
local keys = {}
for _, p in ipairs(E.Patrons.Definitions) do
	for k, v in pairs(p) do
		if type(v) ~= "table" and k ~= "effect" and not keys[k] then keys[k] = true end
	end
end
local ids = {
	"the_understudy", "second_opinion", "tip_jar", "ace_of_the_house", "the_apprentice", "big_spender", "nest_egg", "jack_of_all_trades",
	"queens_gambit", "spare_change", "full_house_crowd", "perfect_ten", "rainy_day_fund", "boss_bane", "tasting_menu", "pair_bonds",
	"sand_merchant", "marsh_gardener", "warm_hearth", "royal_road", "savings_club", "bargain_hunter", "quick_service", "lucky_penny_jar",
	"extra_chair", "second_helpings", "overtime",
}
for _, id in ipairs(ids) do
	local p = E.Patrons.getById(id)
	local f = {}
	for k, v in pairs(p) do
		if k ~= "effect" and k ~= "id" and k ~= "name" and k ~= "icon" and k ~= "price" and k ~= "description" and k ~= "flavorText" and k ~= "tags" then
			f[#f + 1] = k .. "=" .. tostring(type(v) == "table" and "tbl" or v)
		end
	end
	table.sort(f)
	print(id, table.concat(f, ","), "|", p.description)
end
