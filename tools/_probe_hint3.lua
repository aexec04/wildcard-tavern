local function proxy(path)
	return setmetatable({ __path = path }, {
		__index = function(_, key)
			if key == "WaitForChild" then return function(self, n) return self[n] end end
			if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
			return proxy(path .. "/" .. key)
		end,
	})
end
local cache = {}
local function load_(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load_(t.__path) end
	local chunk = assert(loadfile(path .. ".lua", "t", env))
	cache[path] = chunk()
	return cache[path]
end
local L = load_("src/Shared/Engine/Gameplay2Layout")
local RH = load_("src/Shared/Engine/RoundHints")
for _, sz in ipairs({ { 1024, 768 }, { 1280, 720 }, { 800, 450 }, { 1920, 957 } }) do
	local w, h = sz[1], sz[2]
	local r = L.rects(w, h)
	local s = RH.place(r, w, h, {})
	if s then
		print(w, h, s.kind, "plate", s.plate.x, s.plate.y, s.plate.w, s.plate.h, "btn", s.button.x, s.button.y, s.button.w, s.button.h)
	else
		print(w, h, "none")
	end
end
