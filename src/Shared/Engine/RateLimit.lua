--[[
	RateLimit.lua
	A per-player, per-remote token bucket so a client cannot flood the server. Pure Lua; the caller passes the
	time (os.clock()). Normal play stays far below the limits; a spammer's extra calls are dropped silently.

	  RateLimit.allow(userId, name, now) -> true when the call may run.
	  RateLimit.forget(userId)           -> drop a player's buckets on leave.
]]

local RateLimit = {}

RateLimit.BURST = 30 -- calls available at once
RateLimit.PER_SECOND = 15 -- refill rate

local buckets = {} -- [userId][name] = { tokens, last }

function RateLimit.allow(userId, name, now)
	local mine = buckets[userId]
	if not mine then
		mine = {}
		buckets[userId] = mine
	end
	local bucket = mine[name]
	if not bucket then
		bucket = { tokens = RateLimit.BURST, last = now }
		mine[name] = bucket
	end
	local elapsed = math.max(0, now - bucket.last)
	bucket.last = now
	bucket.tokens = math.min(RateLimit.BURST, bucket.tokens + elapsed * RateLimit.PER_SECOND)
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens = bucket.tokens - 1
	return true
end

function RateLimit.forget(userId)
	buckets[userId] = nil
end

return RateLimit
