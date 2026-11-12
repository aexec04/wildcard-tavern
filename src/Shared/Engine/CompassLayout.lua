--[[
	Shared/Engine/CompassLayout.lua
	Pure numbers for the Compass wheel (Client/CompassWheel.lua). The cardinal letters N, E, S, W stand on the outer rim in fixed
	places; the road markers (28 px discs) ride an inner ring, so a marker can never cover a letter. Markers are fanned apart
	so two never overlap, whatever the road bearings are. Tested in EngineTests ("CompassLayout").

	  CompassLayout.LETTERS                 { { text, bearing } } for N, E, S, W
	  CompassLayout.LETTER_BOX              side of a letter label (px), text is 15
	  CompassLayout.MARKER                  marker disc diameter (px)
	  CompassLayout.radii(size)             { rim, marker } radii of the letter centres and the marker centres
	  CompassLayout.minSeparation(r, n)     smallest angle (degrees) between two markers on a ring of radius r
	  CompassLayout.spread(bearings, size)  shown bearings in the same order, at least minSeparation apart (or 360 / n when crowded)
]]

local CompassLayout = {}

CompassLayout.LETTERS = { { text = "N", bearing = 0 }, { text = "E", bearing = 90 }, { text = "S", bearing = 180 }, { text = "W", bearing = 270 } }
CompassLayout.LETTER_BOX = 16
CompassLayout.MARKER = 28
CompassLayout.RIM_PAD = 9 -- letter centres sit this far inside the wheel's edge
CompassLayout.MIN_DEGREES = 40 -- never closer than this, whatever the ring size

function CompassLayout.radii(size)
	local half = size * 0.5
	local rim = half - CompassLayout.RIM_PAD
	local letterInner = rim - CompassLayout.LETTER_BOX * 0.5
	local marker = letterInner - 2 - CompassLayout.MARKER * 0.5 -- a 2 px gap between the letters and the markers
	return { rim = rim, marker = marker }
end

-- the chord between two disc centres must be at least the disc size plus 2 px
function CompassLayout.minSeparation(r, n)
	local want = CompassLayout.MIN_DEGREES
	if r > 0 then
		local ratio = math.min(1, (CompassLayout.MARKER + 2) * 0.5 / r)
		want = math.max(want, math.deg(2 * math.asin(ratio)))
	end
	if n and n > 0 then want = math.min(want, 360 / n) end
	return want
end

local function wrap(a) return a % 360 end

-- Cut the circle at its widest gap, then spread the markers along the line so neighbours are at least `sep` apart while moving as
-- little as possible (pool adjacent violators on a - k * sep). A closing gap that still comes out too small falls back to even spacing.
function CompassLayout.spread(bearings, size)
	local n = #bearings
	local out = {}
	if n == 0 then return out end
	local sep = CompassLayout.minSeparation(CompassLayout.radii(size).marker, n)
	local items = {}
	for i, b in ipairs(bearings) do items[i] = { i = i, a = wrap(b or 0) } end
	table.sort(items, function(x, y) if x.a ~= y.a then return x.a < y.a end return x.i < y.i end)
	if n == 1 then
		out[items[1].i] = items[1].a
		return out
	end
	-- the widest gap (between k and k + 1, wrapping) is where the line starts
	local cut, widest = n, -1
	for k = 1, n do
		local gap = (items[k % n + 1].a - items[k].a) % 360
		if k == n and gap == 0 then gap = 360 end
		if gap > widest then widest, cut = gap, k end
	end
	local line = {}
	local prev = nil
	for t = 1, n do
		local it = items[(cut + t - 1) % n + 1]
		local a = it.a
		if prev and a < prev then a = a + 360 end
		line[t] = { it = it, a = a }
		prev = a
	end
	-- pool adjacent violators on q = a - (t - 1) * sep
	local blocks = {}
	for t = 1, n do
		blocks[#blocks + 1] = { sum = line[t].a - (t - 1) * sep, count = 1 }
		while #blocks > 1 and blocks[#blocks - 1].sum / blocks[#blocks - 1].count > blocks[#blocks].sum / blocks[#blocks].count do
			local last = table.remove(blocks)
			blocks[#blocks].sum = blocks[#blocks].sum + last.sum
			blocks[#blocks].count = blocks[#blocks].count + last.count
		end
	end
	local t = 1
	local placed = {}
	for _, blk in ipairs(blocks) do
		local q = blk.sum / blk.count
		for _ = 1, blk.count do
			placed[t] = q + (t - 1) * sep
			t = t + 1
		end
	end
	if 360 - (placed[n] - placed[1]) < sep - 1e-9 then
		local mean = 0
		for k = 1, n do mean = mean + (placed[k] - (k - 1) * 360 / n) end
		mean = mean / n
		for k = 1, n do placed[k] = mean + (k - 1) * 360 / n end
	end
	for k = 1, n do out[line[k].it.i] = wrap(placed[k]) end
	return out
end

return CompassLayout
