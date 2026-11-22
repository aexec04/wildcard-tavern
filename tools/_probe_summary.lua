local SL=dofile("src/Shared/Engine/ShopSceneLayout.lua")
for _,s in ipairs{{1920,1080},{1280,720},{1024,768},{800,450}} do
 local r=SL.rects(s[1],s[2])
 io.write(s[1],"x",s[2],"\n")
 for k,v in pairs(r) do if type(v)=="table" and v.x then io.write("  ",k," ",v.x," ",v.y," ",v.w," ",v.h,"\n") end end
end
