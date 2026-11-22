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
local SP = load(src .. "/Engine/Gameplay2ScorePlate")
local F = load(src .. "/Engine/Gameplay2Flair")
local function s(r) return string.format("x%d y%d w%d h%d", r.x, r.y, r.w, r.h) end
for _, sz in ipairs({ { 1920, 1080 }, { 1506, 751 }, { 1280, 720 }, { 844, 390 } }) do
	local w, h = sz[1], sz[2]
	local r = L.rects(w, h)
	print("==", w, h, "stage", s(r.stage), "hand", s(r.hand))
	local avoid = 0
	for _, sl in ipairs(r.slots) do avoid = math.max(avoid, sl.pill.y + sl.pill.h, sl.label.y + sl.label.h) end
	local live = SP.live(r.stage, w, 26, 22, true)
	print("plate", s(live.plate), "contentBottom", live.contentBottom, "avoid", avoid)
	local band = L.playedBand(r, 26, 22)
	print("band", band.top, band.bottom, band.bottom - band.top)
	local size = F.fontSize(r.stage, avoid)
	local nm = F.nameRect(r.stage, avoid, size)
	print("name size", size, nm and s(nm))
end
print("---- new")
for _, sz in ipairs({ { 1920, 1080 }, { 1920, 957 }, { 1506, 751 }, { 1280, 720 }, { 1024, 768 }, { 1024, 600 }, { 844, 390 } }) do
	local r = L.rects(sz[1], sz[2])
	local sr = L.scoringRows(r, 26)
	print(sz[1], sz[2], "plateBottom", sr.plateBottom, "name", sr.name and sr.name.y, "band", sr.band.top, sr.band.bottom, "h", sr.band.bottom - sr.band.top, "w", math.floor((sr.band.bottom - sr.band.top) / 1.4), "hand.y", r.hand.y)
end
