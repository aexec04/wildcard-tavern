local L = dofile("src/Shared/Engine/ShopSceneLayout.lua")
for _, c in ipairs({{3,2},{4,2},{5,2},{5,3},{2,2}}) do
  for _, sz in ipairs({{1920,1080},{1280,720}}) do
    local r = L.rects(sz[1], sz[2], {offers=c[1], packs=c[2]})
    local o, p = r.offers[1], r.packs[1]
    print(c[1], c[2], sz[1], "offer w", o and math.floor(o.w), "pack w", p and math.floor(p.w), "fitted", tostring(r.fitted), "side", tostring(r.sideBySide))
  end
end
