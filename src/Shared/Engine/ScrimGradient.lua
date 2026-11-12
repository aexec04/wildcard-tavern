--[[
	Engine/ScrimGradient.lua
	Keypoints for a black fade drawn by ONE frame with a UIGradient (a fade is the intended use of UIGradient.Transparency).
	Stacked strip frames with stepped transparency show as hard dark bands, so never build a fade from strips.

	ScrimGradient.keypoints(points, peakAlpha, exponent) -> { { t, transparency }, ... }
	  t runs 0 (top of the frame) to 1 (bottom); opacity at t is peakAlpha * t^exponent, so transparency is 1 - that.
	  Transparency is 1 at the top. Rotation 90 on the gradient puts time 0 at the top.
]]

local M = {}

M.MAX_POINTS = 20 -- Roblox NumberSequence and ColorSequence accept at most 20 keypoints

function M.keypoints(points, peakAlpha, exponent)
	points = math.min(M.MAX_POINTS, math.max(2, math.floor(points or 16)))
	exponent = exponent or 1
	local out = {}
	for i = 0, points - 1 do
		local t = i / (points - 1)
		out[#out + 1] = { t, 1 - peakAlpha * (t ^ exponent) }
	end
	return out
end

return M
