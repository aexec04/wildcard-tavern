local src = "src/Shared"
local cache = {}
local function proxy(path)
	return setmetatable({ __path = path }, { __index = function(_, key)
		if key == "WaitForChild" then return function(self, n) return self[n] end end
		if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
		return proxy(path .. "/" .. key) end })
end
local function load(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load(t.__path) end
	cache[path] = assert(loadfile(path .. ".lua", "t", env))()
	return cache[path]
end
Color3 = Color3 or { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
local L = load(src .. "/Engine/Gameplay2Layout")
local HS = load(src .. "/Engine/HandSizing")
local SP = load(src .. "/Engine/Gameplay2ScorePlate")
local CT = load(src .. "/Engine/ConceptTLayout")
for _, s in ipairs({ { 1920, 957 }, { 1506, 751 }, { 1280, 720 } }) do
	local r = L.rects(s[1], s[2])
	local pb = 0
	for _, sl in ipairs(r.slots) do for _, k in ipairs({ "card", "label", "pill" }) do local p = sl[k]; if p then pb = math.max(pb, p.y + p.h) end end end
	local s1 = r.slots[1]; print("slot1", s1.card.y, s1.card.h, s1.label and s1.label.y, s1.label and s1.label.h, s1.pill and s1.pill.y, s1.pill and s1.pill.h)
	local hf = HS.frameFor(s[1], CT.handFor(r.hand, s[1], 8), 8)
	local st = SP.idleStage(r.stage, hf.y, s[1])
	local live = SP.live(st, s[1], SP.capFor(s[1]), 22, false)
	print(s[1], s[2], "patronBottom", pb, "stage", r.stage.y, r.stage.h, "idleStage", st.y, st.h, "plate", live.plate.y, live.plate.h, "x", live.plate.x, live.plate.w)
end
