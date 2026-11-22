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
local L = load(src .. "/Engine/ShopSceneLayout")
for _, c in ipairs({{3,2},{4,2},{5,2},{3,1},{3,0},{4,1},{5,0}}) do
  for _, sz in ipairs({{1920,957},{1920,1080},{1280,720}}) do
    local r = L.rects(sz[1], sz[2], {offers=c[1], packs=c[2], room=true})
    local o, p = r.offers[1], r.packs[1]
    print(c[1], c[2], sz[1], sz[2], "offer", o and math.floor(o.w), o and math.floor(o.h), "y", o and math.floor(o.y), "pack", p and math.floor(p.w), "fitted", tostring(r.fitted))
  end
end
do
  local r = L.rects(1920, 957, {offers=3, packs=2, room=true})
  for i, o in ipairs(r.offers) do print("offer", i, o.x, o.y, o.w, o.h) end
  for i, o in ipairs(r.packs) do print("pack", i, o.x, o.y, o.w, o.h) end
  local p = L.rerollPlate(r) print("plate", p.x, p.y, p.w, p.h, "sideBySide", tostring(r.sideBySide))
end
