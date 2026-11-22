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
local PP = load(src .. "/Engine/PatronPowerPanel")
for _, sz in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1280, 720 }, { 1024, 768 }, { 800, 450 } }) do
	local r = L.rects(sz[1], sz[2])
	local s = PP.place(r, sz[1], sz[2], {})
	print(sz[1], sz[2], "hand", r.hand.x, r.hand.y, r.hand.w, r.hand.h, "stage", r.stage.x, r.stage.y, r.stage.w, r.stage.h)
	print("  panel", s and s.plate.x, s and s.plate.y, s and s.plate.w, s and s.plate.h)
	for _, k in ipairs({ "round" }) do local v = r[k]; if v and v.x then print("  ", k, v.x, v.y, v.w, v.h) end end
end
