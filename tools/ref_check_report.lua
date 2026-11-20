-- Offline table vs reference report: lua tools/ref_check_report.lua 1920 957
local src = "src/Shared"
local cache = {}
local function proxy(path)
	return setmetatable({ __path = path }, {
		__index = function(_, key)
			if key == "WaitForChild" then return function(self, n) return self[n] end end
			if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
			return proxy(path .. "/" .. key)
		end,
	})
end
local function load(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load(t.__path) end
	local chunk = assert(loadfile(path .. ".lua", "t", env))
	cache[path] = chunk()
	return cache[path]
end
Color3 = Color3 or { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
local w, h = tonumber(arg[1]) or 1920, tonumber(arg[2]) or 957
local L = load(src .. "/Engine/Gameplay2Layout")
local G = load(src .. "/Engine/GearMenu")
local RC = load(src .. "/Engine/Gameplay2RefCheck")
local SP = load(src .. "/Engine/Gameplay2ScorePlate")
local r = L.rects(w, h)
local plate = SP.plate(w, h)
local live = RC.liveFrom(r, G.quickRects(w, h), plate and plate.w and plate or nil)
local rows = RC.compare(live, w, h)
for _, row in ipairs(rows) do
	print(string.format("%-13s dx=%5.0f dy=%5.0f size=%4.0f%% %s", row.name, row.dx, row.dy, row.sizePct, row.bad and "BAD" or "ok"))
end
print(string.format("%dx%d: %d of %d pieces off", w, h, RC.badCount(rows), #rows))
