--[[
	Engine/PlayMotion.lua
	Pure numbers for the calm motion on the Play screen (Client/PlayMotion.lua draws it): layer parallax, the deal arc,
	the play/discard slide targets and the per-set light pool. No Roblox types, so it is unit tested.
]]

local PlayMotion = {}

-- px a layer may move at full cursor deflection (backdrop least, rail most), 6 to 14 as asked
PlayMotion.LAYER_PX = { backdrop = 6, table = 9, rail = 14 }

function PlayMotion.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- cursor (nx, ny in -1..1) -> pixel offset opposite the cursor, capped at px per axis; calm or modal = no motion
function PlayMotion.parallax(nx, ny, px, calm, modalOpen)
	if calm or modalOpen then return 0, 0 end
	px = PlayMotion.clamp(px, 0, 14)
	return -PlayMotion.clamp(nx, -1, 1) * px, -PlayMotion.clamp(ny, -1, 1) * px * 0.6
end

-- eased follow: fraction of the gap to close this frame (frame-rate independent, capped at 4 frames of catch-up)
function PlayMotion.follow(dt, rate)
	return 1 - (1 - (rate or 0.12)) ^ math.min(4, dt * 60)
end

-- quadratic bezier point at t (0..1) from a to b through a control point lifted `arc` px above the straight line
function PlayMotion.arc(ax, ay, bx, by, t, arc)
	t = PlayMotion.clamp(t, 0, 1)
	local cx, cy = (ax + bx) / 2, (ay + by) / 2 - (arc or 0)
	local u = 1 - t
	return u * u * ax + 2 * u * t * cx + t * t * bx, u * u * ay + 2 * u * t * cy + t * t * by
end

-- deal timing: 0.25 to 0.35 s per card, 0.04 s stagger, slightly longer for the later cards
function PlayMotion.dealTiming(order, count)
	count = math.max(1, count or 1)
	local k = count > 1 and (order - 1) / (count - 1) or 0
	return (order - 1) * 0.04, 0.25 + 0.10 * PlayMotion.clamp(k, 0, 1)
end

-- a played card slides toward the table centre, a discarded one toward the deck pile (offsets from the card's slot)
function PlayMotion.slideTarget(kind, slotX, slotY, centreX, centreY, deckX, deckY)
	if kind == "discard" then return deckX - slotX, deckY - slotY end
	return (centreX - slotX) * 0.8, (centreY - slotY) * 0.8
end

-- light pool: warm for Classic Tavern, cool for the night and winter sets; transparencies are high (low contrast)
PlayMotion.COOL_SETS = { festival_night = true, winter_evening = true }
function PlayMotion.lightFor(setId)
	if PlayMotion.COOL_SETS[setId] then
		return { color = { 150, 190, 235 }, poolTransparency = 0.70, edgeTransparency = 0.72 }
	end
	return { color = { 255, 206, 140 }, poolTransparency = 0.68, edgeTransparency = 0.72 }
end

-- felt shading: the pool lightens the felt over the hand by about 12 to 18 percent, four dark corner glows take about 10 percent
-- off the far corners, and a seamless grain texture lies over the felt rect at 8 to 12 percent. All of it is still (calm mode too).
PlayMotion.FELT = { cornerPeak = 0.30, cornerSize = 0.55, grainOpacity = 0.10, grainTile = 256 }
-- corner glows for a felt rect (x, y, w, h): { { centreX, centreY, size }, ... } centred on the four corners
function PlayMotion.cornerGlows(x, y, w, h)
	local size = math.floor(math.max(w, h) * PlayMotion.FELT.cornerSize)
	return { { x, y, size }, { x + w, y, size }, { x, y + h, size }, { x + w, y + h, size } }
end

-- edge vignette: four soft dark glows centred on the middle of each felt edge (they join the corner glows into one soft ring)
PlayMotion.FELT.edgePeak = 0.18
PlayMotion.FELT.edgeSize = 0.5
function PlayMotion.edgeGlows(x, y, w, h)
	local size = math.floor(math.max(w, h) * PlayMotion.FELT.edgeSize)
	return { { x + w / 2, y, size }, { x + w / 2, y + h, size }, { x, y + h / 2, size }, { x + w, y + h / 2, size } }
end

-- resting stack of played cards at the felt centre: 4 card-backs with fixed small rotations and offsets (no randomness at runtime,
-- so layouts are stable). Returns { { cx, cy, w, h, rot }, ... } for a felt rect of size w x h, centred on it, kept inside it.
PlayMotion.REST_STACK = {
	{ dx = -6, dy = 3, rot = -9 }, { dx = 5, dy = -2, rot = 6 }, { dx = -2, dy = -5, rot = -3 }, { dx = 3, dy = 1, rot = 8 },
}
function PlayMotion.restStack(w, h)
	local cw = PlayMotion.clamp(math.floor(h * 0.16), 36, 84)
	local ch = math.floor(cw * 1.4)
	local out = {}
	for i, s in ipairs(PlayMotion.REST_STACK) do
		out[i] = { w / 2 + s.dx * cw / 40, h / 2 + s.dy * cw / 40, cw, ch, s.rot }
	end
	return out
end

-- pool rect over the hand: a wide ellipse centred on the felt at the hand row
function PlayMotion.poolRect(screenW, screenH, handY, handH)
	local w = math.floor(screenW * 0.7)
	local h = math.floor(math.max(handH * 2.6, screenH * 0.42))
	return math.floor(screenW / 2 - w / 2), math.floor(handY + handH / 2 - h / 2), w, h
end

-- depth: the hand lies on the felt in a visible fan. Position 1..count, t runs -1 (far left) to 1 (far right).
-- Ends lean outward up to 5 degrees, dip 17 px, tuck 8 px toward the middle (so neighbours overlap a little) and are 0.92 the
-- size of the centre cards, which sit highest, largest and level.
PlayMotion.FAN = { deg = 5, dip = 17, tuck = 8, endScale = 0.92 }
local function fanT(pos, count)
	count = math.max(1, count or 1)
	return count > 1 and ((pos - 1) / (count - 1)) * 2 - 1 or 0
end
function PlayMotion.cardTilt(pos, count)
	return fanT(pos, count) * PlayMotion.FAN.deg
end
function PlayMotion.cardScale(pos, count)
	local t = fanT(pos, count)
	return 1 - (1 - PlayMotion.FAN.endScale) * t * t
end
-- pixel offset from the slot centre: x tucks toward the middle, y dips down toward the ends
function PlayMotion.cardOffset(pos, count)
	local t = fanT(pos, count)
	return -t * PlayMotion.FAN.tuck, PlayMotion.FAN.dip * t * t
end

-- played hand: card i of n lands in a small tilted overlapping group on the felt centre (offsets from the centre, degrees)
function PlayMotion.stackSpec(i, n)
	n = math.max(1, n or 1)
	local t = n > 1 and ((i - 1) / (n - 1)) * 2 - 1 or 0
	return t * 26, ((i % 2 == 0) and -4 or 4), t * 9 + ((i % 2 == 0) and -2 or 2)
end

-- contact shadow under a hand card: (transparency, width fraction) at rest and with the card lifted
function PlayMotion.shadowFor(lifted)
	if lifted then return 0.86, 0.7 end
	return 0.7, 0.9
end

-- camera lean: 0 at rest, 0.6 with a card selected, 1 while a hand plays; a plate or calm mode returns to rest
PlayMotion.LEAN_PX = { table = 8, rail = 16 }
PlayMotion.LEAN_SCALE = 0.02
function PlayMotion.leanTarget(selectedCount, playing, modalOpen, calm)
	if modalOpen or calm then return 0 end
	if playing then return 1 end
	return (selectedCount or 0) > 0 and 0.6 or 0
end
-- offset (px down toward the hand) and scale of a layer at lean amount a (0..1)
function PlayMotion.leanOffset(a, px)
	a = PlayMotion.clamp(a, 0, 1)
	return a * px, 1 + PlayMotion.LEAN_SCALE * a
end

return PlayMotion
