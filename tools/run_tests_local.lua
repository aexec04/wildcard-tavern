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

-- Color3 is a Roblox datatype global. Our engine code only ever uses
-- Color3.fromRGB(...) as opaque cosmetic data (CosmeticSets/Palette) -- it's never
-- inspected or math'd on in engine logic -- so a minimal stand-in is
-- enough to let this run outside Roblox.
if not Color3 then
	Color3 = {
		fromRGB = function(r, g, b)
			return { r = r, g = g, b = b }
		end,
	}
end

local SRC_SHARED = (arg and arg[0] and arg[0]:match("(.*)/tools/run_tests_local%.lua$") or ".") .. "/src/Shared"

local moduleCache = {}

local function makeProxy(path)
	return setmetatable({ __path = path }, {
		__index = function(_, key)
			if key == "WaitForChild" then
				return function(self, name)
					return self[name]
				end
			end
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

-- Source lint: every UIList/UIGrid layout in src/Client must set SortOrder.
local lintOk, lintFails = pcall(dofile, "tools/lint_sort_order.lua")
if lintOk and lintFails and lintFails > 0 then
	print("FAILED: " .. lintFails .. " layout(s) without SortOrder")
	os.exit(1)
end

-- Source lint: no player-facing text under 14px.
local textOk, textFails = pcall(dofile, "tools/lint_text_size.lua")
if textOk and textFails and textFails > 0 then
	print("FAILED: " .. textFails .. " label(s) under 14px")
	os.exit(1)
end

-- Source lint: top level local counts of the two hub scripts (200 limit guard).
local locOk, locFails = pcall(dofile, "tools/check_locals.lua")
if locOk and locFails and locFails > 0 then
	os.exit(1)
end

-- Source lint: a top-level local used before its declaration reads as a nil global (python3 required).
local ordRes = os.execute("python3 -I tools/check_order.py")
if ordRes == false or (type(ordRes) == "number" and ordRes ~= 0) then
	print("FAILED: top-level local used before its declaration")
	os.exit(1)
end

os.exit(results.failed == 0 and 0 or 1)
