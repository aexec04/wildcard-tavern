--[[
	Shared/Engine/Haggle.lua
	Haggle with the Peddler: once per shop visit the player picks one Patron or Pack offer and stops a needle
	inside a green zone. Hit: that item costs 1 Tip less (never below 1, never free). Miss or timeout: it costs 1 more
	for this visit only (the penalty is capped at +1 because only one item is ever haggled).

	Pure and deterministic: the result comes only from the server clock position of the needle, nothing is rolled.
	Refused on ranked boards (Daily, Weekly, Seed; ctx.ranked) and in the tutorial (ctx.tutorial), like map tokens.

	State lives in state.haggle = { used = bool, open = { kind, id, startedAt }|nil, kind, id, delta }.
	RunState.patronPrice and packPrice add Haggle.delta(state, kind, id) before their 1 Tip floor.
]]

local Haggle = {}

Haggle.DURATION = 3 -- seconds the timing bar stays open
Haggle.SPEED = 240 -- degrees per second (a full sweep takes 1.5 seconds)
Haggle.CENTER = 180 -- the green zone sits in the middle of the bar
Haggle.WIDTH = 70 -- degrees
Haggle.Kinds = { patron = true, pack = true }

-- Needle angle at `t` seconds: back and forth over 0..360.
function Haggle.needleAt(t)
	local span = 360
	local p = (t * Haggle.SPEED) % (2 * span)
	return p <= span and p or (2 * span - p)
end

function Haggle.inZone(angle)
	return math.abs(angle - Haggle.CENTER) <= Haggle.WIDTH / 2
end

-- Can a haggle be started right now? Returns ok, reason.
function Haggle.canStart(state, ctx, phase)
	ctx = ctx or {}
	if phase ~= "shop" then return false, "wrong_phase" end
	if ctx.ranked then return false, "ranked" end
	if ctx.tutorial then return false, "tutorial" end
	if state.pendingPack then return false, "pack_open" end
	local h = state.haggle
	if h and (h.used or h.open) then return false, "used" end
	return true
end

-- Opens the bar for one offer (the caller has already checked the offer is really on sale).
function Haggle.start(state, ctx, phase, now, kind, id)
	if not Haggle.Kinds[kind] or type(id) ~= "string" then return false, "bad_item" end
	local ok, reason = Haggle.canStart(state, ctx, phase)
	if not ok then return false, reason end
	state.haggle = { used = false, open = { kind = kind, id = id, startedAt = now } }
	return true
end

-- Stops the needle (or the bar timed out). Reads the needle from the server clock; any client angle is ignored.
-- Returns ok, { hit, angle, delta, kind, id }.
function Haggle.stop(state, now)
	local h = state.haggle
	if not (h and h.open) then return false, "not_open" end
	local o = h.open
	local elapsed = math.max(0, now - o.startedAt)
	local angle = Haggle.needleAt(elapsed)
	local hit = elapsed <= Haggle.DURATION and Haggle.inZone(angle)
	h.open = nil
	h.used = true
	h.kind, h.id = o.kind, o.id
	h.delta = hit and -1 or 1
	return true, { hit = hit, angle = angle, delta = h.delta, kind = o.kind, id = o.id, timedOut = elapsed > Haggle.DURATION }
end

-- Price change for one offer this visit: -1, +1 or 0.
function Haggle.delta(state, kind, id)
	local h = state.haggle
	if h and h.used and h.kind == kind and h.id == id then
		return h.delta or 0
	end
	return 0
end

-- A bar left open past its time closes as a miss (the client normally sends the stop itself).
function Haggle.expire(state, now)
	local h = state.haggle
	if h and h.open and now - h.open.startedAt > Haggle.DURATION then
		return Haggle.stop(state, now)
	end
	return false
end

-- The ranked and tutorial flags for a server session (Daily, Weekly, Seed and fixed-route runs are ranked).
function Haggle.ctxFor(session)
	local state = session.state or {}
	return {
		ranked = session.isDaily == true or session.isWeekly == true or session.isSeeded == true or state.worldPlan ~= nil,
		tutorial = session.isTutorial == true,
	}
end

-- A new shop visit: one haggle again.
function Haggle.reset(state)
	state.haggle = nil
end

-- What the client may see: whether it can haggle, the open bar (item and start time) or the last result.
function Haggle.view(state, ctx, phase)
	local h = state.haggle
	local canStart = Haggle.canStart(state, ctx, phase)
	return {
		available = canStart,
		open = h and h.open and { kind = h.open.kind, id = h.open.id } or nil,
		used = h and h.used or false,
		kind = h and h.kind, id = h and h.id, delta = h and h.delta,
		speed = Haggle.SPEED, center = Haggle.CENTER, width = Haggle.WIDTH, duration = Haggle.DURATION,
	}
end

return Haggle
