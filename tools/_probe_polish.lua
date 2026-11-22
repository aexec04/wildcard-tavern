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
for _, sz in ipairs({ { 1672, 941 }, { 1506, 751 }, { 1920, 1080 }, { 1280, 720 } }) do
	local w, h = sz[1], sz[2]
	local r = L.rects(w, h)
	local k, ky = 1672 / w, 941 / h
	print("== ", w, h)
	for _, n in ipairs({ "target", "round", "tips", "playCount", "discardCount", "deck", "deckCount", "play", "discard" }) do
		local b = r[n]
		print(string.format("%-12s x %4d-%4d  y %4d-%4d  (h %d)", n, b.x * k, (b.x + b.w) * k, b.y * ky, (b.y + b.h) * ky, b.h * ky))
	end
end
