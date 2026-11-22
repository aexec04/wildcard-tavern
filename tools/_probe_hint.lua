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
for _, sz in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 1506, 751 }, { 1024, 768 } }) do
	local r = L.rects(sz[1], sz[2])
	local top = r.slots[1].pill.y + r.slots[1].pill.h + 4
	print(sz[1], sz[2], "free h", r.hand.y - 6 - top, "stage x", r.stage.x, r.stage.x + r.stage.w, "left room", r.stage.x - 16)
end
