-- probe: idle Score plate numbers at several sizes (temporary)
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
local SP = load(src .. "/Engine/Gameplay2ScorePlate")
local HS = load(src .. "/Engine/HandSizing")
local CT = load(src .. "/Engine/ConceptTLayout")
for _, s in ipairs({ { 1920, 957 }, { 1506, 751 }, { 1280, 720 }, { 844, 390 } }) do
	local r = L.rects(s[1], s[2])
	local ih = HS.frameFor(s[1], CT.handFor(r.hand, s[1], 5), 8)
	print("hint", s[1], s[2], "hand.y", r.hand.y, "h", r.hand.h, "frame y", ih.y, "stage", r.stage.x, r.stage.y, r.stage.w, r.stage.h)
end
for _, s in ipairs({ { 1920, 957 }, { 1506, 751 }, { 1280, 720 }, { 1920, 1080 } }) do
	local r = L.rects(s[1], s[2])
	local ih = HS.frameFor(s[1], CT.handFor(r.hand, s[1], 5), 8)
	local st = SP.idleStage(r.stage, ih.y, s[1])
	local lv = SP.live(st, s[1], SP.capFor(s[1]), 22, false)
	print(s[1], s[2], "stage y", r.stage.y, "h", r.stage.h, "w", r.stage.w, "idle h", st.h, "plate h", lv.plate.h, "numH", lv.N.numH, lv.N.textSize)
end
