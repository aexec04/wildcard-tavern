--[[
	Shared/Engine/SidebarMetrics.lua
	ONE number for how much of the left edge the HUD column takes, so full screens (Counter, boss fight host) never
	draw over the painted board. The old flat sidebar is 240 px wide; the painted board (PlayBoardLayout.placement) is
	wider (361 px at 1506x751). PlayBoardPaint calls setPainted; screens ask for their left edge and refit on onChange.

	SidebarMetrics.width(screenW, screenH)    -> column width: the board's width when painted, else 240
	SidebarMetrics.hostLeft(screenW, screenH) -> left edge of a full-height host: 240 flat, board width + 8 painted
	SidebarMetrics.contentLeft(sw, sh)        -> left edge of a padded panel: 260 flat (240 + 20), board width + 8 painted
]]

local PlayBoardLayout = require(script.Parent.PlayBoardLayout)

local M = {}
M.BASE = 240
M.GAP = 8

local painted = false
local listeners = {}

function M.setPainted(on)
	on = on and true or false
	if on == painted then return end
	painted = on
	for _, fn in ipairs(listeners) do pcall(fn) end
end

function M.isPainted() return painted end

function M.onChange(fn)
	listeners[#listeners + 1] = fn
end

local function boardW(sw, sh)
	if not painted then return nil end
	local p = PlayBoardLayout.placement(sw, sh)
	return p and p.w or nil
end

function M.width(sw, sh)
	return boardW(sw, sh) or M.BASE
end

function M.hostLeft(sw, sh)
	local w = boardW(sw, sh)
	return w and (w + M.GAP) or M.BASE
end

function M.contentLeft(sw, sh)
	local w = boardW(sw, sh)
	return w and (w + M.GAP) or (M.BASE + 20)
end

return M
