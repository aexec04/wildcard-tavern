-- Offline boss-round geometry: lua tools/_probe_boss.lua 1920 957
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
local M = load(src .. "/Engine/Gameplay2Moments")
local SP = load(src .. "/Engine/Gameplay2ScorePlate")
local r = L.rects(w, h)
local function p(n, q)
	if q then print(string.format("%-10s x%4d y%4d w%4d h%4d  (x2 %d y2 %d)", n, q.x, q.y, q.w, q.h, q.x + q.w, q.y + q.h)) else print(n, "nil") end
end
p("round", r.round); p("target", r.target); p("tips", r.tips)
local s1, s5 = r.slots[1], r.slots[#r.slots]
p("seat1", s1.card); p("pill1", s1.pill); p("seat5", s5.card); p("pill5", s5.pill)
p("stage", r.stage); p("hand", r.hand)
p("plate", SP.plate(w, h))
p("rulePlate", M.rulePlate(r))
print("RULE_H", M.RULE_H)
