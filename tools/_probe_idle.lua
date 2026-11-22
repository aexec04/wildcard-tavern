-- probe: hand frame width and card size per window (temporary, delete after use)
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
for _, sz in ipairs({ { 1920, 1080 }, { 1920, 957 }, { 1506, 751 }, { 1280, 720 } }) do
	local w, h = sz[1], sz[2]
	local r = L.rects(w, h)
	local fr = H.frameFor(w, CT.handFor(r.hand, w, 8), 8)
	local st = S.idleStage(r.stage, fr.y)
	local live = S.live(st, w, 20, 22, false)
	print(w, h, "stage y", r.stage.y, "h", r.stage.h, "handTop", fr.y, "idle h", st.h, "roomy", live.N.roomy, "noProg", live.N.noProgress, "plateH", live.plate.h)
end
