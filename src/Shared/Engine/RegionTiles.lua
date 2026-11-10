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
		local smooth = t * t * t * (t * (t * 6 - 15) + 10) -- smootherstep: eased ends, no visible stair step
		out[k] = { x = x0, w = x1 - x0, transparency = 1 - smooth }
	end
	return out
end

-- Width of the cross-fade zone between two neighbouring regions of widths wa and wb: at least 25 percent of the
-- narrower one (and never under `minW`), capped at `maxW` and at the narrower region itself.
function RegionTiles.joinWidth(wa, wb, minW, maxW)
	local narrow = math.min(wa, wb)
	local w = math.max(minW or 96, narrow * 0.25)
	w = math.min(w, maxW or 480, narrow)
	return math.floor(w)
end

-- Number of slices for a fade zone of `width` pixels: about one per 6px, between 16 and 64.
function RegionTiles.sliceCount(width)
	return math.max(16, math.min(64, math.ceil(width / 6)))
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

-- Horizontal mask for a painting `width` px wide: transparency keypoints { t, transparency } for a UIGradient
-- (NumberSequence). Fully clear (1) at a faded edge easing to opaque (0) over fadeL px on the left and fadeR px on the
-- right (smootherstep, `perSide` keypoints per faded side, default 10). t runs 0..1 and never decreases.
-- Roblox allows at most 20 keypoints in a NumberSequence or ColorSequence, so perSide is capped to keep the total at 20 or less
-- (a faded side has perSide + 1 points and an unfaded side one: both faded gives at most 10 + 10, one faded at most 19 + 1).
RegionTiles.MAX_KEYPOINTS = 20

function RegionTiles.maskStops(width, fadeL, fadeR, perSide)
	width = math.max(1, width)
	fadeL, fadeR = math.max(0, fadeL or 0), math.max(0, fadeR or 0)
	local both = fadeL > 0 and fadeR > 0
	perSide = math.max(8, math.min(math.floor(perSide or 10), both and (RegionTiles.MAX_KEYPOINTS // 2 - 1) or (RegionTiles.MAX_KEYPOINTS - 2)))
	local total = fadeL + fadeR
	if total > width then -- the two fades share the width when it is too small for both
		fadeL, fadeR = fadeL * width / total, fadeR * width / total
	end
	local function ease(u) return u * u * u * (u * (u * 6 - 15) + 10) end
	local out = {}
	local function add(t, tr)
		local last = out[#out]
		if last and t <= last.t then t = math.min(1, last.t + 1e-4) end
		out[#out + 1] = { t = math.min(t, 1), transparency = tr }
	end
	if fadeL > 0 then
		for k = 0, perSide do add(fadeL / width * (k / perSide), 1 - ease(k / perSide)) end
	else
		add(0, 0)
	end
	if fadeR > 0 then
		local start = 1 - fadeR / width
		for k = 0, perSide do add(start + fadeR / width * (k / perSide), ease(k / perSide)) end
	else
		add(1, 0)
	end
	out[1].t = 0
	out[#out].t = 1
	return out
end

return RegionTiles
