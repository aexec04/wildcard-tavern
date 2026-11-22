-- probe: idle Score plate height by hand size (temporary, delete after use)
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
local S = load(src .. "/Engine/Gameplay2ScorePlate")
local H = load(src .. "/Engine/HandSizing")
local CT = load(src .. "/Engine/ConceptTLayout")
for _, n in ipairs({ 5, 8, 10 }) do
	local r = L.rects(1920, 957)
	local fr = H.frameFor(1920, CT.handFor(r.hand, 1920, n), math.max(n, 8))
	local st = S.idleStage({ x = r.stage.x, y = 410, w = r.stage.w, h = r.stage.h - 24 }, fr.y)
	local live = S.live(st, 1920, 30, 22, false)
	print(n, "handTop", fr.y, "stage h", st.h, "plateH", live.plate.h, live.N.numH)
end
