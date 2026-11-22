local function proxy(path)
	return setmetatable({ __path = path }, {
		__index = function(_, key)
			if key == "WaitForChild" then return function(self, n) return self[n] end end
			if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
			return proxy(path .. "/" .. key)
		end,
	})
end
local cache = {}
local function load_(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load_(t.__path) end
	local chunk = assert(loadfile(path .. ".lua", "t", env))
	cache[path] = chunk()
	return cache[path]
end
local L = load_("src/Shared/Engine/Gameplay2Layout")
local RH = load_("src/Shared/Engine/RoundHints")
local SP = load_("src/Shared/Engine/Gameplay2ScorePlate")
for _, sz in ipairs({ {1920,1080},{1920,957},{1506,751},{1366,768},{1280,720},{1024,768},{800,450} }) do
	local w, h = sz[1], sz[2]
	local r = L.rects(w, h)
	local sp = RH.place(r, w, h, {})
	local p = SP.live(r.stage, w, 20, 22).progress
	print(w, h, sp and sp.kind, sp and ("%d,%d,%d,%d"):format(sp.plate.x, sp.plate.y, sp.plate.w, sp.plate.h),
		p and ("prog %d,%d,%d,%d"):format(p.x, p.y, p.w, p.h), "stage", r.stage.x, r.stage.y, r.stage.w, r.stage.h, "deck", r.deck and r.deck.x)
end
