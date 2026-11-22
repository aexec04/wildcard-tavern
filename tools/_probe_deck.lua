-- prints the live deck, hand and stage rects at four sizes (run from the repo root: lua tools/_probe_deck.lua)
local ROOT = "./src/Shared"
local cache = {}
local function proxy(path)
	return setmetatable({ __path = path }, { __index = function(_, k)
		if k == "WaitForChild" then return function(self, n) return self[n] end end
		if k == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
		return proxy(path .. "/" .. k)
	end })
end
local function load_(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load_(t.__path) end
	local chunk = assert(loadfile(path .. ".lua", "t", env))
	cache[path] = chunk()
	return cache[path]
end
Color3 = Color3 or { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
local G = load_(ROOT .. "/Engine/Gameplay2Layout")
local CT = load_(ROOT .. "/Engine/ConceptTLayout")
for _, s in ipairs({ { 1920, 957 }, { 1920, 1080 }, { 1672, 941 }, { 1506, 751 }, { 1280, 720 } }) do
	local w, h = s[1], s[2]
	local r = G.rects(w, h)
	local function p(n, b) print(w, h, n, b.x, b.y, b.w, b.h) end
	p("deck", r.deck); p("hand", r.hand); p("stage", r.stage); p("deckCount", r.deckCount)
	local f = CT.feltFor(w, h).rim
	p("felt", f)
	local HS = load_(ROOT .. "/Engine/HandSizing")
	for n = 7, 9 do
		local fr = HS.frameFor(w, CT.handFor(r.hand, w, n), math.max(n, 8))
		local cw = HS.cardSize(w, fr.w, fr.h, n)
		local span = HS.fanSpan(w, cw, n)
		print(w, h, "fanEnd n=" .. n, fr.x + fr.w / 2 + span / 2, "centre", fr.x + fr.w / 2)
	end
	print(w, h, "inside30", CT.insideFelt(r.deck, CT.DECK_TILT, w, h, 30))
end
