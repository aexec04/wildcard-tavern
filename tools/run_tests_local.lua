--[[
	run_tests_local.lua
	Runs the engine test suite with a *plain* Lua interpreter (lua5.1+),
	no Roblox or Rojo required. This is only possible because the engine
	modules (src/Shared/Engine/*) and the tests (src/Shared/Tests/*) avoid
	any Roblox-specific APIs.

	Usage:
		lua5.3 tools/run_tests_local.lua

	How it works: Roblox scripts use `require(script.Parent.Something)`,
	where `script` is a special instance object Roblox injects. Plain Lua
	has no such thing, so this file builds a tiny fake `script` object that
	mirrors the real one closely enough (Parent navigation + child lookup by
	filename) for our module tree, and points `require` at it.
]]

-- Roblox's Luau dialect adds a few extra stdlib functions on top of vanilla
-- Lua (e.g. table.find). Polyfill the ones our engine code uses so it can
-- run under a plain `lua5.x` interpreter too.
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

local SRC_SHARED = (arg and arg[0] and arg[0]:match("(.*)/tools/run_tests_local%.lua$") or ".") .. "/src/Shared"

local moduleCache = {}

local function makeProxy(path)
	return setmetatable({ __path = path }, {
		__index = function(_, key)
			if key == "Parent" then
				local parent = path:match("(.*)/[^/]+$")
				return makeProxy(parent or ".")
			end
			return makeProxy(path .. "/" .. key)
		end,
	})
end

local function loadModuleByPath(path)
	if moduleCache[path] then
		return moduleCache[path]
	end

	local fullPath = path .. ".lua"
	local env = setmetatable({
		script = makeProxy(path),
	}, { __index = _G })
	env.require = function(target)
		if type(target) == "table" and target.__path then
			return loadModuleByPath(target.__path)
		end
		error("run_tests_local shim: unsupported require() target")
	end

	local chunk, loadErr = loadfile(fullPath, "t", env)
	if not chunk then
		error("Could not load module at " .. fullPath .. ": " .. tostring(loadErr))
	end

	local result = chunk()
	moduleCache[path] = result
	return result
end

local testsProxy = makeProxy(SRC_SHARED .. "/Tests/EngineTests")
local tests = loadModuleByPath(testsProxy.__path)

local TestRunner = loadModuleByPath(SRC_SHARED .. "/Tests/TestRunner")

print("Running Wildcard Tavern engine tests (plain Lua, no Roblox)...\n")
local results = TestRunner.run(tests)

os.exit(results.failed == 0 and 0 or 1)
