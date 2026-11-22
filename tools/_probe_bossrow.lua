local cache = {}
local function proxy(path) return setmetatable({ __path = path }, { __index = function(_, key)
  if key == "WaitForChild" then return function(self, n) return self[n] end end
  if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
  return proxy(path .. "/" .. key) end }) end
local function load(path) if cache[path] then return cache[path] end
  local env = setmetatable({ script = proxy(path) }, { __index = _G })
  env.require = function(t) return load(t.__path) end
  cache[path] = assert(loadfile(path .. ".lua", "t", env))(); return cache[path] end
local L = load("src/Shared/Engine/Gameplay2Layout"); local B = load("src/Shared/Engine/BossCard")
for _, sz in ipairs({ {1920,957},{1280,720},{1024,768},{800,450} }) do
  local r = L.rects(sz[1], sz[2]); local c = B.cardRect(r, sz[1], sz[2]); local s = B.seatRect(r)
  print(sz[1], sz[2], c and (c.x..","..c.y.." "..c.w.."x"..c.h) or "nil", s and (s.x..","..s.y.." "..s.w.."x"..s.h))
end
