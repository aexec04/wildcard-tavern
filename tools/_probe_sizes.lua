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
local L = load("src/Shared/Engine/Gameplay2Layout")
for _, sz in ipairs({ { 1024, 768 }, { 1366, 768 }, { 800, 450 }, { 1280, 720 } }) do
	local w, h = sz[1], sz[2]
	local r = L.rects(w, h)
	local ok, nm = L.onScreen(r, w, h)
	print(w, h, "onScreen", ok, nm, "overlaps", table.concat(L.overlaps(r), ","))
	for _, k in ipairs({ "play", "discard", "sortRank", "sortSuit", "gear", "hand", "deck", "stage", "traySlot1" }) do
		local v = r[k]
		if v then print("  ", k, v.x, v.y, v.w, v.h) end
	end
	print("  card1", r.slots[1].card.w, r.slots[1].card.h, "pill1 h", r.slots[1].pill.h)
end
