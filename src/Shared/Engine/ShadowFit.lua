--[[
	Engine/ShadowFit.lua
	Pure maths for panel drop shadows (Client/VisualHelpers addSoftShadow). The shadow is a sibling frame sized as the
	panel plus PAD on each axis. When the panel is clamped by a UISizeConstraint, the shadow must be clamped by the same
	constraint grown by PAD, or it overshoots the panel and leaves uneven strips.
]]

local ShadowFit = {}

ShadowFit.PAD = 14

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Constraint limits for the shadow, given the panel's limits (px).
function ShadowFit.limits(minX, minY, maxX, maxY)
	local p = ShadowFit.PAD
	return minX + p, minY + p, maxX + p, maxY + p
end

-- Panel size on one axis: scale * parent + offset, clamped to [lo, hi].
function ShadowFit.panelAxis(parent, scale, offset, lo, hi)
	return clamp(scale * parent + offset, lo, hi)
end

-- Shadow size on one axis using the same panel numbers; always panelAxis + PAD.
function ShadowFit.shadowAxis(parent, scale, offset, lo, hi)
	local p = ShadowFit.PAD
	return clamp(scale * parent + offset + p, lo + p, hi + p)
end

return ShadowFit
