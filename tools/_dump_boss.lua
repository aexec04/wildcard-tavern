-- one-off: prints every boss with its effect fields
local loader = dofile("tools/sim/EngineLoader.lua")
local engine = loader.load("src/Shared")
local BR = engine.BossRounds
local skip = { id = 1, name = 1, description = 1, flavorText = 1, rules = 1 }
for _, d in ipairs(BR.Definitions) do
	local keys = {}
	for k, v in pairs(d) do
		if not skip[k] then
			if type(v) == "table" then
				local t = {}
				for kk in pairs(v) do t[#t + 1] = tostring(kk) end
				table.sort(t)
				v = "{" .. table.concat(t, ",") .. "}"
			end
			keys[#keys + 1] = k .. "=" .. tostring(v)
		end
	end
	table.sort(keys)
	print(d.id, table.concat(keys, " "))
end
