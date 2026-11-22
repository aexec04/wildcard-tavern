-- Offline whole-table overlap probe: lua tools/_probe_overlap.lua
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
Color3 = Color3 or { fromRGB = function() return {} end }
local L = load(src .. "/Engine/Gameplay2Layout")
local BC = load(src .. "/Engine/BossCard")
local GM = load(src .. "/Engine/GearMenu")
local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
for _, sz in ipairs({ { 1920, 957 }, { 1309, 751 }, { 1280, 720 }, { 800, 450 } }) do
	local w, h = sz[1], sz[2]
	local r = L.rects(w, h)
	local set = L.flat(r)
	local q = GM.quickRects(w, h)
	set.speaker, set.pause = q.speaker, q.pause
	set.bossCard = BC.cardRect(r, w, h)
	set.bossPlate = BC.plateRect(r)
	local names = {}
	for k, v in pairs(set) do if v then names[#names + 1] = k end end
	table.sort(names)
	print(w .. "x" .. h)
	for i = 1, #names do for j = i + 1, #names do
		local a, b = names[i], names[j]
		if not L.ALLOWED[a .. "|" .. b] and not L.ALLOWED[b .. "|" .. a] and hit(set[a], set[b]) then
			print("  overlap", a, b)
		end
	end end
end
