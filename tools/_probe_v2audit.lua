-- probe (temporary): v2 hand card size and rects per window
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
local HS = load(src .. "/Engine/HandSizing")
local CT = load(src .. "/Engine/ConceptTLayout")
for _, s in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 1024, 600 }, { 800, 400 }, { 390, 844 }, { 844, 390 } }) do
	local w, h = s[1], s[2]
	print(w, h, "fits", L.fits(w, h))
	local r = L.rects(w, h)
	local hf = CT.handFor(r.hand, w, 8)
	local cw, ch = HS.cardSize(w, hf.w, hf.h, 8)
	print("  hand", hf.x, hf.y, hf.w, hf.h, "card", cw, ch, "play", r.play.h, "bar", r.bar.h, "stage", r.stage.h)
	print("  overlaps", table.concat(L.overlaps(r), ","), "onscreen", tostring(L.onScreen(r, w, h)))
end
