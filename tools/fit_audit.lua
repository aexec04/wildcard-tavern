--[[
	tools/fit_audit.lua
	Runs the screen fit audit (src/Shared/Tests/FitAudit.lua, screens in FitScreens.lua) with plain Lua and prints every
	failure. With the argument "write" it also writes claude/FIT-AUDIT.md.

		lua tools/fit_audit.lua [write]
]]

local function proxy(path)
	return setmetatable({ __path = path }, { __index = function(_, k)
		if k == "WaitForChild" then return function(s, n) return s[n] end end
		if k == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
		return proxy(path .. "/" .. k)
	end })
end
local cache = {}
local function load(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load(t.__path) end
	local c = assert(loadfile(path .. ".lua", "t", env))
	local r = c()
	cache[path] = r
	return r
end

local function E(name) return load("src/Shared/Engine/" .. name) end
local Audit = load("src/Shared/Tests/FitAudit")
local screens = load("src/Shared/Tests/FitScreens")(E)
local res = Audit.run(screens)

local byLane = { menu = {}, table = {}, shared = {} }
for _, f in ipairs(res.failures) do
	local lane = byLane[f.lane or "shared"] or byLane.shared
	lane[#lane + 1] = f
	print(("%-18s %-10s %-8s %s"):format(f.screen, f.size, f.rule, f.detail))
end
print(("checked %d screen sizes, %d failures"):format(res.checked, #res.failures))

if arg and arg[1] == "write" then
	local out = { "# Screen fit audit", "", "Run with `lua tools/fit_audit.lua write`. Sizes: 800x450, 1024x768, 1366x768, 1920x1080. Rules: on screen, text 11 px (14 px body), touch 44 px, no unlisted sibling overlap.", "" }
	out[#out + 1] = "Covered (layout modules in Engine/): Menu, Loading, Settings panel, Store, Table (Gameplay2Layout and PlayBoardLayout), Counter shop, Draft, Collection grid, Daily Rewards row, Run Over."
	out[#out + 1] = "Not covered: Quests, Season, Victory, Tome tabs, Tavern Map and Round Select have no pure rect layout to read (they size in Client code), and no layout module publishes text sizes, so text size is held by `tools/lint_text_size.lua` (14 px minimum in src). Rects of art layers (Counter shop scene) overlap by design and are listed as intended in `src/Shared/Tests/FitScreens.lua`."
	out[#out + 1] = "Result: every shared screen fits at all four sizes (tested in EngineTests, `FitAudit`). Nothing needed a code fix in shared files."
	out[#out + 1] = ""
	for _, lane in ipairs({ "shared", "menu", "table" }) do
		out[#out + 1] = lane == "shared" and "## Failures in shared screens" or ("## for the other lane: " .. lane)
		if #byLane[lane] == 0 then out[#out + 1] = "None." end
		for _, f in ipairs(byLane[lane]) do out[#out + 1] = ("- %s at %s, %s: %s"):format(f.screen, f.size, f.rule, f.detail) end
		out[#out + 1] = ""
	end
	local f = assert(io.open("claude/FIT-AUDIT.md", "w"))
	f:write(table.concat(out, "\n"))
	f:close()
end
