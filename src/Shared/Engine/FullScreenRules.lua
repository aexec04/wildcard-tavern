--[[
	Engine/FullScreenRules.lua
	Pure rules for the full-screen scenes (the Tavern Map first): the panel is the whole screen, a thin strip carries the title, the corner
	icon dock hides while one is open and comes back exactly as it was. No Roblox types.

	panelRect(sw, sh)        -> { x = 0, y = 0, w = sw, h = sh }
	stripRect(sw, sh)        -> the 64 px header strip at the top
	closeRect(sw, sh)        -> the bottom-centre Close button; xRect(sw, sh) the small round X at the top right (16 px margin)
	new()                    -> state; enter(state, reason) / leave(state, reason); hidden(state) -> true while any reason is active
	HIDE                     -> names of the root children hidden while a full-screen scene is open
]]

local M = {}

M.STRIP_H = 64
M.MARGIN = 16
M.CLOSE = { w = 160, h = 44 }
M.X = 40
M.HIDE = { "CornerIconRow" }
-- Roblox's own buttons sit over the top left corner of the screen (Engine/ResponsiveLayout: a zone TOPBAR_ZONE_W wide
-- and TOPBAR_H tall), and a full screen scene is drawn under them. Its header words start right of that zone and its
-- top-left controls start below the strip. (On the Tavern Map the title was hidden under those buttons, and "Find
-- me" sat under them where it could not be pressed.)
M.HEADER_LEFT = require(script.Parent.ResponsiveLayout).TOPBAR_ZONE_W
M.CONTROLS_TOP = M.STRIP_H + 4

function M.panelRect(sw, sh) return { x = 0, y = 0, w = sw, h = sh } end

function M.stripRect(sw, sh) return { x = 0, y = 0, w = sw, h = M.STRIP_H } end

function M.closeRect(sw, sh)
	return { x = math.floor((sw - M.CLOSE.w) / 2), y = sh - M.CLOSE.h - M.MARGIN, w = M.CLOSE.w, h = M.CLOSE.h }
end

function M.xRect(sw, sh)
	return { x = sw - M.X - M.MARGIN, y = math.floor((M.STRIP_H - M.X) / 2), w = M.X, h = M.X }
end

function M.new() return { reasons = {} } end

function M.enter(state, reason) state.reasons[reason] = true end

function M.leave(state, reason) state.reasons[reason] = nil end

function M.hidden(state) return next(state.reasons) ~= nil end

return M
