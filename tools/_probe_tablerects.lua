-- probe: stage, plate and hand rects (temporary)
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
local HS = load(src .. "/Engine/HandSizing")
local SP = load(src .. "/Engine/Gameplay2ScorePlate")
local CT = load(src .. "/Engine/ConceptTLayout")
for _, s in ipairs({ { 1920, 957 }, { 1920, 1080 }, { 1506, 751 }, { 1280, 720 } }) do
	local r = L.rects(s[1], s[2])
	for _, n in ipairs({ 8, 9, 10 }) do
		local hf = HS.frameFor(s[1], CT.handFor(r.hand, s[1], n), math.max(n, 8))
		local st = SP.idleStage(r.stage, hf.y)
		local live = SP.live(st, s[1], 26, 22, false)
		print("idle", s[1], n, "handTop", hf.y, "stage h", st.h, "plateBottom", live.plate.y + live.plate.h, "noProg", tostring(live.N.noProgress))
	end
	local hf = HS.frameFor(s[1], r.hand, 8)
	local cw, ch = HS.cardSize(s[1], hf.w, hf.h, 8)
	local p = SP.plate(s[1], s[2])
	print(s[1], s[2], "stage", r.stage.y, r.stage.h, "plate", p.y, p.h, "handFrame", hf.y, hf.h, "cardTop", hf.y + hf.h - 16 - ch, "play", r.play.y, "cnt", r.playCount.y)
end
