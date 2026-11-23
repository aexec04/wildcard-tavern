local L = dofile("src/Shared/Engine/ShopSceneLayout.lua")
local sizes = { { 800, 360 }, { 1280, 720 }, { 1920, 1080 } }
for _, sz in ipairs(sizes) do
	local ok, r = pcall(L.rects, sz[1], sz[2], { offers = 3, packs = 2 })
	if not ok then
		print("ERR", r)
	else
		print(sz[1], sz[2], "phone", r.phone)
		for _, k in ipairs({ "leave", "nextBoss", "bubble" }) do
			local x = r[k]
			if x then print("  ", k, x.x, x.y, x.w, x.h) end
		end
		if r.tabs then
			for i, t in ipairs(r.tabs) do print("  tab", i, t.x, t.y, t.w, t.h) end
		end
		for k, v in pairs(r.props or {}) do print("  prop", k, v.x, v.y, v.w, v.h) end
		for i, o in ipairs(r.offers) do print("  offer", i, o.x, o.y, o.w, o.h) end
		for i, o in ipairs(r.packs) do print("  pack", i, o.x, o.y, o.w, o.h) end
	end
end
