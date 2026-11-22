-- probe: Patron row bottom vs stage vs plate (temporary)
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
for _, s in ipairs({ { 1920, 957 }, { 1280, 720 }, { 1920, 1080 }, { 844, 390 } }) do
	local r = L.rects(s[1], s[2])
	local p, lb = r.slots[1].pill, r.slots[1].label
	print(s[1], s[2], "label", lb.y, lb.h, "pill", p.y, p.h, "stage", r.stage.y, r.stage.h, "hand", r.hand.y)
end
