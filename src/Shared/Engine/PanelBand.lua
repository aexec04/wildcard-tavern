--[[
	Engine/PanelBand.lua
	Pure layout maths for set-skin panel frames: how thick the frame band is and how far panel content must be inset
	so titles and Close buttons never land on the ornament. Used by Client/SetSkin.lua and the overlap check.
]]

local PanelBand = {}

PanelBand.MAX_BAND = 24 -- px, visible border band at normal size
PanelBand.MIN_BAND = 8
PanelBand.SOURCE = 1024 -- assumed frame art edge in px (SliceCenter is cut from this)
PanelBand.SLICE_EDGE = 128 -- art px that form the border on each side

-- Band thickness for a panel of the given pixel size: about 3 percent of the short side, clamped to 8..24 px, and never
-- more than a quarter of the short side on tiny panels.
function PanelBand.band(w, h)
	local short = math.min(w or 0, h or 0)
	local b = math.floor(short * 0.03 + 0.5)
	b = math.max(PanelBand.MIN_BAND, math.min(PanelBand.MAX_BAND, b))
	return math.min(b, math.floor(short / 4))
end

-- Content rectangle inside the band, in px from the panel origin.
function PanelBand.inset(w, h, band)
	band = band or PanelBand.band(w, h)
	return {
		left = band, top = band, right = w - band, bottom = h - band,
		width = math.max(0, w - 2 * band), height = math.max(0, h - 2 * band),
	}
end

-- SliceScale that makes the art's border (SLICE_EDGE art px) draw `band` px thick.
function PanelBand.sliceScale(band)
	return band / PanelBand.SLICE_EDGE
end

-- True when a child rectangle (x, y, w, h relative to the panel) touches the border band.
function PanelBand.intersectsBand(panelW, panelH, band, x, y, w, h)
	local r = PanelBand.inset(panelW, panelH, band)
	return x < r.left or y < r.top or x + w > r.right or y + h > r.bottom
end

return PanelBand
