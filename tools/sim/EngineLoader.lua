--[[
	EngineLoader.lua
	Loads src/Shared/Engine/* under a plain Lua interpreter, the same way
	tools/run_tests_local.lua does: a fake `script` object plus a `require`
	shim per module, and polyfills for the Roblox globals the engine touches.
]]

local EngineLoader = {}

function EngineLoader.load(sharedPath)
	if not table.find then
		table.find = function(t, value)
			for i, v in ipairs(t) do
				if v == value then
					return i
				end
			end
			return nil
		end
	end
	if not Color3 then
		Color3 = {
			fromRGB = function(r, g, b)
				return { r = r, g = g, b = b }
			end,
		}
	end

	local moduleCache = {}

	local function makeProxy(path)
		return setmetatable({ __path = path }, {
			__index = function(_, key)
				if key == "Parent" then
					return makeProxy(path:match("(.*)/[^/]+$") or ".")
				end
				return makeProxy(path .. "/" .. key)
			end,
		})
	end

	local function loadModule(path)
		if moduleCache[path] then
			return moduleCache[path]
		end
		local env = setmetatable({ script = makeProxy(path) }, { __index = _G })
		env.require = function(target)
			return loadModule(target.__path)
		end
		local chunk, err = loadfile(path .. ".lua", "t", env)
		if not chunk then
			error("Could not load " .. path .. ".lua: " .. tostring(err))
		end
		local result = chunk()
		moduleCache[path] = result
		return result
	end

	local engine = {}
	for _, name in ipairs({
		"Card", "Deck", "HandEvaluator", "Scoring", "Patrons", "RunState", "Shop", "Packs", "Onboarding",
		"HousePasses", "Recipes", "BossRounds", "DeckVariants", "DifficultyTiers", "SeededRng", "Tags", "Stakes", "EndlessRules",
	}) do
		engine[name] = loadModule(sharedPath .. "/Engine/" .. name)
	end
	-- Boss and Challenge scoring rules. Optional so an older engine given with --src still loads.
	local hasRules, rules = pcall(loadModule, sharedPath .. "/Engine/BossRules")
	engine.BossRules = hasRules and rules or nil
	-- any other Engine module by name (tools/economy_report.lua)
	engine.loadEngineModule = function(name)
		return loadModule(sharedPath .. "/Engine/" .. name)
	end
	return engine
end

return EngineLoader
