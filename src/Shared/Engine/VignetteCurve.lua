--[[
	Engine/VignetteCurve.lua
	Pure numbers for smooth edge vignettes (no Roblox types). A vignette edge is ONE frame with a UIGradient whose
	Transparency runs from dark at the screen edge to fully clear at its far side, so there is no hard edge anywhere.

	keypoints(count)    -> { {time, transparency}, ... } for an edge at time 0 (opaque) fading to clear at time 1,
	                       with an ease-out curve (opacity = (1 - t)^2). At least 6 points, strictly increasing time,
	                       transparency never decreasing, ends at exactly 1.
	stacked(layer, n)   -> the opacity n equal layers of opacity `layer` give at the edge (used to keep the old darkness).
	edgeOpacity(old)    -> helper for tests: opacity at depth t for a keypoint list.
]]

local VignetteCurve = {}

VignetteCurve.DEFAULT_POINTS = 9

function VignetteCurve.keypoints(count)
	count = math.max(6, math.floor(count or VignetteCurve.DEFAULT_POINTS))
	local out = {}
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local opacity = (1 - t) * (1 - t)
		out[#out + 1] = { t, 1 - opacity }
	end
	out[#out][2] = 1
	return out
end

-- Opacity of `n` stacked layers that each have opacity `layer` (0..1).
function VignetteCurve.stacked(layer, n)
	layer = math.max(0, math.min(1, layer))
	return 1 - (1 - layer) ^ n
end

return VignetteCurve
