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
local PP = load_("src/Shared/Engine/PatronParchment")
local S = load_("src/Shared/Engine/Gameplay2ScorePlate")
local live = { "Tab Regulars", "The Regular", "Suit Yourself", "Early Bird", "The Bard" }
for _, sz in ipairs({ { 800, 450 }, { 1024, 768 } }) do
	local r = L.rects(sz[1], sz[2])
	local c = r.slots[1].card
	local st = PP.rowStyle(live, c.w, c.h)
	print(sz[1], "card", c.w, c.h, "size", st.size, st.wrapped, "labelW", PP.labelRect(c.w, st.wrapped).w, "ribbon", PP.layout(c.h, st.wrapped, st.size).ribbon.h * c.h)
	local lv = S.live(r.stage, sz[1], 20, 22, false)
	print("stage", r.stage.x, r.stage.y, r.stage.w, r.stage.h, "plate", lv.plate.x, lv.plate.y, lv.plate.w, lv.plate.h, "progress", lv.progress and "y" or "nil", lv.N.roomy, lv.N.noProgress, lv.N.below)
	local inl = S.inline(lv, 1)
	print("inline", inl and (inl.x .. " " .. inl.w) or "nil")
end
