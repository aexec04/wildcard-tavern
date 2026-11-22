-- probe (temporary): Gameplay v2 boss, night and clear plates against the table rects
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
	cache[path] = assert(loadfile(path .. ".lua", "t", env))()
	return cache[path]
end
local L = load(src .. "/Engine/Gameplay2Layout")
local M = load(src .. "/Engine/Gameplay2Moments")
local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
for _, s in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 1024, 600 }, { 800, 400 } }) do
	local w, h = s[1], s[2]
	local r = L.rects(w, h)
	local rp, bb = M.rulePlate(r), M.bossBanner(r, w, h)
	print(w, h, "rulePlate", rp and string.format("%d,%d,%d,%d", rp.x, rp.y, rp.w, rp.h) or "nil", "banner", bb and string.format("%d,%d,%d,%d", bb.x, bb.y, bb.w, bb.h) or "nil")
	if rp then
		for _, k in ipairs({ "sortRank", "sortSuit", "hand", "stage", "mute", "calm", "bar" }) do if hit(rp, r[k]) then print("  RULEPLATE HITS", k) end end
		for i, sl in ipairs(r.slots) do for _, p in ipairs({ "card", "label", "pill" }) do if hit(rp, sl[p]) then print("  RULEPLATE HITS slot", i, p) end end end
	end
	if bb then
		for _, k in ipairs({ "mute", "calm" }) do if hit(bb, r[k]) then print("  BANNER HITS", k) end end
		for i, sl in ipairs(r.slots) do if hit(bb, sl.card) then print("  BANNER HITS slot", i) end end
	end
	local np = M.nightPlate(w, h, true)
	local cr = M.continueRect(np)
	print("  night plate", np.x, np.y, np.w, np.h, "continue", cr.w, cr.h, "unlockRow", tostring(M.unlockRow(np)))
	local cp = M.clearPlate(w, h)
	print("  clear plate", cp.x, cp.y, cp.w, cp.h)
	local ip = M.bossIntroPlate(w, h)
	print("  intro plate", ip.x, ip.y, ip.w, ip.h)
end
