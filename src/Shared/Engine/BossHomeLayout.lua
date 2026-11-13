-- BossHomeLayout: where the boss lives on the Play screen. Pure numbers, no Roblox.
--
-- The boss gets one home: a round portrait medallion with a name plate (name and rule text) beside it, standing in the
-- top strip of the screen, between the left board and the corner dock. That strip is above the Patron Nook
-- (PatronRowLayout.TOP_LIMIT), so the home can never overlap the nook, the hand, the score slot or the board.
--
--   BossHomeLayout.place(screenW, screenH, left, dockW) -> {
--       medallion = {x,y,w,h}, plate = {x,y,w,h}, group = {x,y,w,h}   (screen pixels)
--     } | nil   (nil when the strip is too narrow to hold a readable medallion)
local M = {}

M.TOP = 4 -- air above the home
M.BOTTOM_LIMIT = 88 -- the Patron Nook starts at PatronRowLayout.TOP_LIMIT (92); keep 4 px clear of it
M.EDGE = 12 -- air to the board and the dock
M.GAP = 8 -- between medallion and plate
M.MEDALLION = 72
M.MEDALLION_SMALL = 56
M.PLATE_MAX = 340
M.PLATE_MIN = 150
M.PLATE_H = 64 -- 18 px name over two 15 px rule lines

local floor = math.floor

function M.place(screenW, screenH, left, dockW)
	if not screenW or not screenH or screenW < 1 or screenH < 1 then return nil end
	left = left or 0
	dockW = dockW or math.min(300, floor(screenW * 0.35))
	local x0 = left + M.EDGE
	local x1 = screenW - dockW - M.EDGE
	local span = x1 - x0
	local height = M.BOTTOM_LIMIT - M.TOP
	local d = math.min(M.MEDALLION, height)
	if span < d + M.GAP + M.PLATE_MIN then d = math.min(M.MEDALLION_SMALL, height) end
	local plateW = math.min(M.PLATE_MAX, span - d - M.GAP)
	if plateW < M.PLATE_MIN then
		-- too narrow for the plate beside the medallion: the medallion alone still has a home, the plate takes what is left
		plateW = span - d - M.GAP
		if plateW < 96 then return nil end
	end
	local groupW = d + M.GAP + plateW
	local gx = floor(x0 + (span - groupW) / 2)
	local plateH = math.min(M.PLATE_H, height)
	local gy = M.TOP
	local medallion = { x = gx, y = gy + floor((height - d) / 2), w = d, h = d }
	local plate = { x = gx + d + M.GAP, y = gy + floor((height - plateH) / 2), w = plateW, h = plateH }
	return { medallion = medallion, plate = plate, group = { x = gx, y = gy, w = groupW, h = height } }
end

return M
