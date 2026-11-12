--[[
	SpectateLayout: pure geometry for the Spectate overlay (Client/SpectatePanel.lua).
	The overlay is HEIGHT tall; the reaction row sits above the strip at the bottom, where the Leave button is centred,
	so the two never overlap.
]]
local SpectateLayout = {}

SpectateLayout.WIDTH_MAX = 760
SpectateLayout.HEIGHT = 376
SpectateLayout.REACT_H = 36
SpectateLayout.LEAVE_W = 120
SpectateLayout.LEAVE_H = 32
SpectateLayout.EDGE = 8

-- Rects are { x, y, w, h } in overlay pixels for an overlay `width` wide.
function SpectateLayout.rects(width)
	local L = SpectateLayout
	local leaveY = L.HEIGHT - L.EDGE - L.LEAVE_H
	local reactY = leaveY - 6 - L.REACT_H
	return {
		react = { 12, reactY, width - 24, L.REACT_H },
		leave = { (width - L.LEAVE_W) / 2, leaveY, L.LEAVE_W, L.LEAVE_H },
	}
end

return SpectateLayout
