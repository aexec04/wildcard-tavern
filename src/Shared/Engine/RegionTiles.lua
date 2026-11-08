--[[
	Engine/RegionTiles.lua
	Pure layout helper for the Tavern Map region art, so no part of a region frame is ever
	left uncovered (a gap shows the bare parchment base as a flat block).

	single(frameW, frameH, aspect, centerX) -> { fillW, heroX, heroW }
		The "fill" image is a Crop copy covering the whole frame (x 0, width frameW). The
		"hero" image keeps its native aspect (never stretched) at heroX, centred on centerX
		(frame-relative) so the landmark sits where the node is.

	tiled(frameW, frameH, aspect) -> tileCount
		Number of equal tiles (each Crop) that span the frame; tiles share the width exactly.
]]

local RegionTiles = {}

function RegionTiles.single(frameW, frameH, aspect, centerX)
	local heroW = math.floor(frameH * aspect)
	local cx = centerX or (frameW / 2)
	return {
		fillW = math.ceil(frameW),
		heroX = math.floor(cx - heroW / 2),
		heroW = heroW,
	}
end

function RegionTiles.tiled(frameW, frameH, aspect)
	return math.max(1, math.floor(frameW / (frameH * aspect) + 0.5))
end

-- Cross-fade between two neighbouring paintings: `n` thin vertical slices across `width` pixels, each with the
-- ImageTransparency to draw its slice of the LATER painting at: nearly clear on the left (the earlier painting
-- shows) to nearly opaque on the right. Slices tile the width exactly (no gap, no overlap).
-- Returns { { x, w, transparency }, ... }.
function RegionTiles.fadeSlices(width, n)
	n = math.max(1, math.floor(n))
	local out = {}
	for k = 1, n do
		local x0 = math.floor((k - 1) * width / n)
		local x1 = math.floor(k * width / n)
		local t = (k - 0.5) / n -- 0..1 across the join
		local smooth = t * t * (3 - 2 * t)
		out[k] = { x = x0, w = x1 - x0, transparency = 1 - smooth }
	end
	return out
end

-- Colour of seam strip i of n: runs from the left biome's colour (a) to the right biome's (b), each an
-- {r, g, b} triple of 0..255 numbers. Returns {r, g, b} (rounded), so a join is tinted by the two biomes
-- instead of one cream band.
function RegionTiles.seamColor(a, b, i, n)
	local t = n <= 1 and 0.5 or (i - 1) / (n - 1)
	local out = {}
	for c = 1, 3 do
		out[c] = math.floor(a[c] + (b[c] - a[c]) * t + 0.5)
	end
	return out
end

return RegionTiles
