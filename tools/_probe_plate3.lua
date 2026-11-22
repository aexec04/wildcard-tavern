package.path="src/Shared/Engine/?.lua;"..package.path
local L=require("Gameplay2Layout") local P=require("Gameplay2ScorePlate")
for _,s in ipairs{{1920,957},{1280,720},{1506,751}} do
 local r=L.rects(s[1],s[2]) local p=P.plate(s[1],s[2])
 print(s[1],"stage",r.stage.y,r.stage.h,"plate",p.y,p.h,"pill",r.slots[1].pill.y,r.slots[1].pill.h,"card",r.slots[1].card.y,r.slots[1].card.h, "ref y",365/941*s[2])
end
