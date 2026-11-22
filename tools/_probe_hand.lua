-- probe: hand frame width and card size per window (temporary, delete after use)
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
local P = load(src .. "/Engine/PlayTableLayout")
local HS = load(src .. "/Engine/HandSizing")
local sizes = { { 1506, 751, 260 }, { 1920, 957, 300 }, { 1280, 720, 240 } }
for _, s in ipairs(sizes) do
	for _, set in ipairs({ "classic_tavern", "none" }) do
		local p = P.placement(s[1], s[2], s[3], 150, set ~= "none" and set or nil)
		if p then
			local cw, ch = HS.cardSize(s[1], p.hand.w, p.hand.h, 8)
			print(s[1], set, "hand", p.hand.x, p.hand.y, p.hand.w, p.hand.h, "card", cw, ch)
		else
			print(s[1], set, "nil")
		end
	end
end
