local ok, L = pcall(dofile, "src/Shared/Engine/Gameplay2Layout.lua")
if not ok then print(L) return end
for _, s in ipairs({{1920,1080},{1280,720},{1506,751}}) do
  local r = L.rects(s[1], s[2])
  local function e(b) return b.x + b.w end
  print(s[1], s[2], "tops", r.sortRank.y, r.sortSuit.y, r.play.y, r.discard.y, "h", r.sortRank.h, r.sortSuit.h, r.play.h, r.discard.h)
  print(" gaps rs", r.sortSuit.x - e(r.sortRank), "sp", r.play.x - e(r.sortSuit), "pd", r.discard.x - e(r.play), "cnt", r.playCount.y + r.playCount.h, r.play.y)
end
