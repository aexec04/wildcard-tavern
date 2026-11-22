--[[
	SaveLock.lua
	A lease stored inside the saved profile so two servers never overwrite each other's progress, plus the
	retry schedule for loading. Pure Lua, no Roblox APIs (the server passes game.JobId and os.time()).

	  * A server claims a profile on load (UpdateAsync writes `sessionLock = { jobId, t }`).
	  * Every save is also an UpdateAsync that refuses to write when another LIVE lock is on the stored copy.
	  * A lock older than LEASE seconds is stale (the server crashed) and may be taken over.
	  * The final save on leave writes `sessionLock = nil` so the next server can claim at once.
]]

local SaveLock = {}

SaveLock.LEASE = 300 -- seconds; autosave runs every 120s, so a live server always renews well inside this
SaveLock.RETRY_DELAYS = { 1, 2, 4 } -- seconds to wait before attempts 2, 3 and 4 of a load
SaveLock.SAVE_RETRY_DELAYS = { 1, 2 } -- seconds to wait before attempts 2 and 3 of the final save on leave or shutdown

-- May this server read-and-claim the stored profile? `stored` is whatever the DataStore returned (nil for a new player).
function SaveLock.canClaim(stored, jobId, now)
	if type(stored) ~= "table" then
		return true
	end
	local lock = stored.sessionLock
	if type(lock) ~= "table" then
		return true
	end
	if lock.jobId == jobId then
		return true
	end
	if type(lock.t) ~= "number" or now - lock.t > SaveLock.LEASE then
		return true
	end
	return false
end

-- A shallow copy of `profile` ready to write, holding the lock (or no lock when `release` is true).
function SaveLock.stamp(profile, jobId, now, release)
	local out = {}
	for k, v in pairs(profile) do
		out[k] = v
	end
	if release then
		out.sessionLock = nil
	else
		out.sessionLock = { jobId = jobId, t = now }
	end
	return out
end

return SaveLock
