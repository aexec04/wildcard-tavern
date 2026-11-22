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

SaveLock.MIN_SAVE_GAP = 15 -- seconds; a timer or event save sooner than this after the last good one is skipped (the profile stays dirty)

-- Pure helper for the throttle: may a non-final save run now? `force` (store receipts) and `release` (leaving) always may.
function SaveLock.mayWrite(lastSaveAt, now, release, force)
	if release == true or force == true or type(lastSaveAt) ~= "number" then
		return true
	end
	return now - lastSaveAt >= SaveLock.MIN_SAVE_GAP or now < lastSaveAt
end

-- Claims the stored profile through `store:UpdateAsync` (anything with that method, so a fake works in tests).
-- Returns status, stored: "ok" (stored may be nil for a new player), "locked" (a live server holds it),
-- "corrupt" (an entry exists but is not a table: never overwritten) or "error" (every attempt threw).
-- `delays` are the waits before each retry, `wait` the sleep function.
function SaveLock.load(store, key, jobId, now, delays, wait)
	local status, stored = "locked", nil
	for attempt = 1, #delays + 1 do
		local claimed, corrupt, old0 = false, false, nil
		local ok = pcall(function()
			store:UpdateAsync(key, function(old)
				old0, corrupt = old, old ~= nil and type(old) ~= "table"
				if corrupt then
					return nil -- keep whatever is there; a blank profile must not replace it
				end
				if SaveLock.canClaim(old, jobId, now()) then
					claimed = true
					local out = {}
					if type(old) == "table" then
						for k, v in pairs(old) do out[k] = v end
					end
					out.sessionLock = { jobId = jobId, t = now() }
					return out
				end
				return nil
			end)
		end)
		if ok and claimed then
			return "ok", old0
		elseif ok and corrupt then
			return "corrupt", nil
		end
		status = ok and "locked" or "error"
		if attempt <= #delays then
			wait(delays[attempt])
		end
	end
	return status, stored
end

-- Writes `profile` (stamped with the lease, or released). Returns "ok", "locked" (another live server owns it:
-- nothing written) or "error" (every attempt threw, caller keeps the profile dirty).
function SaveLock.save(store, key, profile, jobId, now, release, delays, wait)
	local written, ok = false, false
	for attempt = 1, #delays + 1 do
		ok = pcall(function()
			store:UpdateAsync(key, function(old)
				if type(old) ~= "nil" and type(old) ~= "table" then
					return nil
				end
				if not SaveLock.canClaim(old, jobId, now()) then
					return nil
				end
				written = true
				return SaveLock.stamp(profile, jobId, now(), release == true)
			end)
		end)
		if ok or attempt > #delays then
			break
		end
		wait(delays[attempt])
	end
	if ok and written then
		return "ok"
	end
	return ok and "locked" or "error"
end

return SaveLock
