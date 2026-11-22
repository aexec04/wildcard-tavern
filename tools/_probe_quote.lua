package.path = "src/Shared/?.lua;" .. package.path
local L = dofile("src/Shared/Engine/Gameplay2Layout.lua")
for _, s in ipairs({ { 1506, 751 }, { 1920, 957 }, { 1280, 720 } }) do
	local r = L.rects(s[1], s[2]); local sr = L.scoringRows(r, 26)
	print(s[1], s[2], "stage", r.stage.y, r.stage.h, "hand", r.hand.y, r.hand.h, "plateB", sr.plateBottom, "name", sr.name and sr.name.y, "band", sr.band.top, sr.band.bottom)
end
