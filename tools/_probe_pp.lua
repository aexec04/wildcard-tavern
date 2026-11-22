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
local PP = load(src .. "/Engine/PatronPowerPanel")
local M = load(src .. "/Engine/Gameplay2Moments")
for _, sz in ipairs({ { 1920, 957 }, { 1506, 751 }, { 1280, 720 } }) do
	local r = L.rects(sz[1], sz[2])
	local pr = M.rulePlate(r)
	local s = PP.place(r, sz[1], sz[2], {})
	local sb = PP.place(r, sz[1], sz[2], { pr })
	print(sz[1], "hand.y", r.hand.y, "rule", pr and pr.x, pr and pr.y, pr and pr.w, pr and pr.h)
	print("  plain", s and s.kind, s and s.plate.x, s and s.plate.y, s and s.plate.w, s and s.plate.h)
	print("  boss ", sb and sb.kind, sb and sb.plate.y)
end
for _, sz in ipairs({ { 1920, 957 }, { 1506, 751 }, { 1280, 720 } }) do
	local r2 = L.rects(sz[1], sz[2])
	for _, k in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do r2[k] = nil end
	local pr = M.rulePlate(r2)
	local sb = PP.place(r2, sz[1], sz[2], { pr })
	print("notray", sz[1], sb and sb.kind, sb and sb.plate.y, sb and sb.plate.w, sb and sb.plate.h)
end
local r = L.rects(1280, 720)
for name, rect in pairs(r) do if type(rect) == "table" and rect.x then print("  ", name, rect.x, rect.y, rect.w, rect.h) end end
print("slot1", r.slots[1].card.x, r.slots[1].card.y)
