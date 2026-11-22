-- probe: idle stage vs hand frame vs strip (temporary)
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
local HSz = load(src .. "/Engine/HandSizing")
local CT = load(src .. "/Engine/ConceptTLayout")
local P = load(src .. "/Engine/Gameplay2Preview")
for _, s in ipairs({ { 1920, 957 }, { 1920, 921 }, { 1506, 751 }, { 1440, 900 }, { 1366, 768 }, { 1280, 720 }, { 1600, 900 } }) do
	local r = L.rects(s[1], s[2])
	local ih = HSz.frameFor(s[1], CT.handFor(r.hand, s[1], 8), 8)
	local st = SP.idleStage(r.stage, ih.y)
	local ps, sh = P.plateStage(st, SP.MIN_H)
	print(s[1], s[2], "stage", r.stage.y, r.stage.h, "handFrameTop", ih.y, "idle", st.y, st.h, "MIN_H", SP.MIN_H, "shifted", sh, ps.y, ps.h)
end
