local L = dofile("src/Shared/Engine/Gameplay2Layout.lua")
for _, s in ipairs({{1920,1080},{1920,957},{1506,751},{1280,720}}) do
  local r = L.rects(s[1], s[2])
  local N = L.scoreStack(math.max(1, r.stage.h - 16), 26, 22, true)
  print(s[1], s[2], "stage.h", r.stage.h, "numTop", N.numTop, "noProgress", N.noProgress, "roomy", N.roomy)
end
