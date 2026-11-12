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
		return { color = { 150, 190, 235 }, poolTransparency = 0.88, edgeTransparency = 0.72 }
	end
	return { color = { 255, 206, 140 }, poolTransparency = 0.86, edgeTransparency = 0.72 }
end

-- pool rect over the hand: a wide ellipse centred on the felt at the hand row
function PlayMotion.poolRect(screenW, screenH, handY, handH)
	local w = math.floor(screenW * 0.62)
	local h = math.floor(math.max(handH * 2.2, screenH * 0.3))
	return math.floor(screenW / 2 - w / 2), math.floor(handY + handH / 2 - h / 2), w, h
end

-- depth: the hand lies on the felt in a very gentle arc. Position 1..count; returns degrees (1 to 3 in size, edges lean
-- outward) and a scale (centre 1.0, far edge cards about 4 percent smaller, as if farther from the seat)
function PlayMotion.cardTilt(pos, count)
	count = math.max(1, count or 1)
	local t = count > 1 and ((pos - 1) / (count - 1)) * 2 - 1 or 0
	local jitter = (pos % 2 == 0) and 0.7 or -0.7
	local deg = PlayMotion.clamp(t * 2.2 + jitter, -3, 3)
	if math.abs(deg) < 1 then deg = deg < 0 and -1 or 1 end
	return deg
end

function PlayMotion.cardScale(pos, count)
	count = math.max(1, count or 1)
	local t = count > 1 and ((pos - 1) / (count - 1)) * 2 - 1 or 0
	return 1 - 0.04 * t * t
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
