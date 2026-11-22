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
local P = load(src .. "/Engine/PlayedLane")
for _, sz in ipairs({{1920,957},{1920,1080},{1280,720},{1024,768},{1024,600},{800,450}}) do
  local r = L.rects(sz[1], sz[2])
  local band = L.playedBand(r, 26, 22)
  local N = L.scoreStack(r.stage.h, 26, 22)
  local lane = P.rect({nookBottom = band.top, handTop = band.bottom, cardW = 120, cardH = 154, popupH = 0, gap = 0, minScale = 0.3})
  print(sz[1], sz[2], "stage", r.stage.y, r.stage.h, "numeral", r.stage.y + N.numTop, r.stage.y + N.numTop + N.numH, "progress", r.stage.y + N.progressY, "band", band.top, band.bottom, "rowY", math.floor(lane.rowY), "cardH", math.floor(lane.cardH), "hand", r.hand.y, "pills end", r.slots[1].pill.y + r.slots[1].pill.h)
end
