-- Prints Gameplay2Layout.rects for a screen size: lua tools/probe_table_rects.lua 1920 957
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
local L = load(src .. "/Engine/Gameplay2Layout")
local r = L.rects(tonumber(arg[1]), tonumber(arg[2]))
local keys = {}
for k in pairs(r) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
	local v = r[k]
	if type(v) == "table" and v.x then print(k, v.x, v.y, v.w, v.h) end
end
for i, s in ipairs(r.slots) do print("slot" .. i, s.card.x, s.card.y, s.card.w, s.card.h) end
