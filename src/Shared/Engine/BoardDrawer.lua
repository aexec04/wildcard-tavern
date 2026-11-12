--[[
	Engine/BoardDrawer.lua
	Pure rules for the left board drawer: the player presses and drags the painted board sideways; it slides off to the left and only a
	28 px strip of its wood post stays on the edge. Dragging the strip back (or a plain click on it) opens it again. No handle tab and no
	info chip. No Roblox types.

	enabled(screenW)                      -> false under 900 px wide (the compact layout already makes the board a drawer there)
	collapsed(userChoice, forced, sw)     -> the effective state: forced open (tutorial, tooltip) beats the user's choice
	distance(boardW)                      -> how far the pieces slide left (the board's width minus the 28 px strip)
	stripRect(sh, boardTop, boardH)       -> { x, y, w, h } the strip that stays on the left edge (hit area = the strip)
	dragDx(startDx, deltaX, boardW)       -> the board offset while dragging, clamped to [-distance, 0]
	isDrag(deltaX)                        -> true once the pointer moved 4 px or more (below that it is a click)
	settle(startCollapsed, dx, boardW)    -> the collapsed state after release: past 40 percent of the way flips it; a click on the strip opens
	handLeft(collapsed, boardRight)       -> left edge of the hand area
]]

local M = {}

M.STRIP = 28
M.SNAP = 0.4
M.DRAG_START = 4
M.SLIDE_TIME = 0.2
M.MIN_WIDTH = 900
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
	return math.max(0, math.floor(boardW - M.STRIP))
end

function M.stripRect(sh, boardTop, boardH)
	local y = math.max(0, math.floor(boardTop or 0))
	local h = math.min(sh - y, math.floor(boardH or sh))
	return { x = 0, y = y, w = M.STRIP, h = math.max(h, 0) }
end

function M.dragDx(startDx, deltaX, boardW)
	local lo = -M.distance(boardW)
	return math.max(lo, math.min(0, math.floor(startDx + deltaX)))
end

function M.isDrag(deltaX)
	return math.abs(deltaX or 0) >= M.DRAG_START
end

function M.settle(startCollapsed, dx, boardW)
	local dist = M.distance(boardW)
	if dist <= 0 then return false end
	local moved = startCollapsed and (dx + dist) or -dx -- distance travelled away from the start state, 0..dist
	if startCollapsed then
		return not (moved > M.SNAP * dist) -- dragged back more than 40 percent: open
	end
	return moved > M.SNAP * dist -- dragged away more than 40 percent: away
end

function M.handLeft(collapsed, boardRight)
	if collapsed then return M.HAND_LEFT_COLLAPSED end
	return boardRight + 24
end

return M
