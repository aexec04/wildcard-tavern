local src = "src/Shared"
local cache = {}
local function proxy(p)
	return setmetatable({ __path = p }, { __index = function(_, k)
		if k == "WaitForChild" then return function(s, n) return s[n] end end
		if k == "Parent" then return proxy(p:match("(.*)/[^/]+$") or ".") end
		return proxy(p .. "/" .. k)
	end })
end
local function load(p)
	if cache[p] then return cache[p] end
	local env = setmetatable({ script = proxy(p) }, { __index = _G })
	env.require = function(t) return load(t.__path) end
	cache[p] = assert(loadfile(p .. ".lua", "t", env))()
	return cache[p]
end
Color3 = Color3 or { fromRGB = function() return {} end }
local L = load(src .. "/Engine/Gameplay2Layout")
local CT = load(src .. "/Engine/ConceptTLayout")
local HS = load(src .. "/Engine/HandSizing")
for _, s in ipairs({ { 1920, 957 }, { 1920, 1080 }, { 1280, 720 } }) do
	local w, h = s[1], s[2]
	local r = L.rects(w, h)
	print(w, h, "hand", r.hand.x, r.hand.w, "play", r.play.x, r.play.w, "disc", r.discard.x, r.discard.w, "deck", r.deck.x)
	for n = 5, 9 do
		local f = HS.frameFor(w, CT.handFor(r.hand, w, n), math.max(n, 8))
		local cw = HS.cardSize(w, f.w, f.h, n)
		local span = HS.fanSpan(w, cw, n)
		local c = f.x + f.w / 2
		print("  n", n, "cardW", cw, "span", span, string.format("%.0f%%", 100 * span / w), "centre", c, "left", c - span / 2, "right", c + span / 2)
	end
end
