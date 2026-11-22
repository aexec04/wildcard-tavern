local L = dofile("src/Shared/Engine/ShopSceneLayout.lua")
for _, s in ipairs({{1920,1080},{1280,720},{844,390}}) do
  for _, room in ipairs({true, false}) do
    local r = L.rects(s[1], s[2], {offers=3, packs=2, room=room})
    local m, b, n = r.marlo, r.bubble, r.nextBoss
    local f = {x=m.x+m.w*0.25, y=m.y, w=m.w*0.5, h=m.h*0.35}
    local function hit(a,c) return a.x<c.x+c.w and c.x<a.x+a.w and a.y<c.y+c.h and c.y<a.y+a.h end
    print(s[1], room, "marlo", m.x,m.y,m.w,m.h, "bubble", b.x,b.y,b.w,b.h, "boss", n.x,n.y,n.w,n.h, "bubbleHitsFace", hit(b,f), "bossHitsFace", hit(n,f))
  end
end
