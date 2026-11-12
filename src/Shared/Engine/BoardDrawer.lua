--[[
	Engine/BoardDrawer.lua
	Pure rules for the left board drawer: the whole left HUD (painted board, Tips and hint plates, medallion) slides off to the left so
	the room and table show; a brass tab handle and a small chip with the key numbers stay behind. No Roblox types.

	enabled(screenW)                      -> false under 900 px wide (the compact layout already makes the board a drawer there)
	collapsed(userChoice, forced, sw)     -> the effective state: forced open (tutorial, tooltip) beats the user's choice
	distance(boardW)                      -> how far the pieces slide left (the board's width plus its 40 px shadow room)
	handleRect(sw, sh, boardW, collapsed) -> { x, y, w, h, hit } the visual tab; hit is the width of the hit area
	chipRect(sw, sh)                      -> { x, y, w, h } of the chip shown while collapsed
	chipLines(score, target, tips, hands, discards) -> { "Score 0 / 317", "Tips 26", "H 4  D 3" }
	handLeft(collapsed, boardRight)       -> left edge of the hand area
]]

local M = {}

M.HANDLE = { w = 36, h = 96, hit = 48 }
M.CHIP = { w = 176, h = 84 }
M.SLIDE_TIME = 0.28
M.MIN_WIDTH = 900
M.SHADOW = 40
M.HAND_LEFT_COLLAPSED = 60
-- the root children that make up the left HUD (a missing one is skipped)
M.NAMES = { "SidebarBoard", "Sidebar", "EdgeShadow", "PlayBoardPaint", "PlayBoardPaintBand", "PlayBoardPaintCap", "PlayBoardFiller", "BlessingChip" }

function M.enabled(screenW)
	return (screenW or 0) >= M.MIN_WIDTH
end

function M.collapsed(userChoice, forced, screenW)
	if not M.enabled(screenW) then return false end
	if forced then return false end
	return userChoice == true
end

function M.distance(boardW)
	return math.floor(boardW + M.SHADOW)
end

function M.handleRect(sw, sh, boardW, collapsed)
	local h = M.HANDLE
	return { x = collapsed and 0 or math.floor(boardW), y = math.floor(sh / 2 - h.h / 2), w = h.w, h = h.h, hit = h.hit }
end

function M.chipRect(sw, sh)
	local c, h = M.CHIP, M.HANDLE
	return { x = h.hit + 6, y = math.floor(sh / 2 - c.h / 2), w = c.w, h = c.h }
end

local function whole(v) return math.floor((tonumber(v) or 0) + 0.5) end

function M.chipLines(score, target, tips, hands, discards)
	return {
		string.format("Score %d / %d", whole(score), whole(target)),
		string.format("Tips %d", whole(tips)),
		string.format("H %d  D %d", whole(hands), whole(discards)),
	}
end

function M.handLeft(collapsed, boardRight)
	if collapsed then return M.HAND_LEFT_COLLAPSED end
	return boardRight + 24
end

return M
