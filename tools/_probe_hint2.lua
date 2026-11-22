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
local L = load(src .. "/Engine/Gameplay2Layout")
local RH = load(src .. "/Engine/RoundHints")
for _, sz in ipairs({ { 1920, 957 }, { 1506, 751 } }) do
	local r = L.rects(sz[1], sz[2])
	local s = RH.strip(r, sz[1], sz[2], {})
	print(sz[1], s and s.plate.x, s and s.plate.y, "stage", r.stage.x, r.stage.y, r.stage.w, r.stage.h)
	for name, rect in pairs(r) do if type(rect) == "table" and rect.x then print("  ", name, rect.x, rect.y, rect.w, rect.h) end end
end
