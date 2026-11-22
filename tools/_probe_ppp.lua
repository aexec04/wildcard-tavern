local src = "src/Shared"
local cache = {}
local function proxy(path)
	return setmetatable({ __path = path }, { __index = function(_, key)
		if key == "WaitForChild" then return function(self, n) return self[n] end end
		if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
		return proxy(path .. "/" .. key) end })
end
local function load(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load(t.__path) end
	cache[path] = assert(loadfile(path .. ".lua", "t", env))()
	return cache[path]
end
Color3 = Color3 or { fromRGB = function() return {} end }
local L = load(src .. "/Engine/Gameplay2Layout")
local P = load(src .. "/Engine/PatronPowerPanel")
for _, s in ipairs({ { 1920, 1080 }, { 1920, 957 }, { 1506, 751 }, { 1280, 720 }, { 844, 390 } }) do
	local r = L.rects(s[1], s[2])
	local p = P.place(r, s[1], s[2], {})
	if p then
		print(s[1], s[2], "plate", p.plate.x, p.plate.y, p.plate.w, p.plate.h, "kind", p.kind, "hand", r.hand.x, r.hand.y)
	else
		print(s[1], s[2], "nil")
	end
end
