--[[
	Shared/Engine/RunAbandon.lua
	Server-side rule for Settings > Restart Run (tested). The server validates; the client only asks.

	  canAbandon(session) -> ok, reason   a run is abandonable while it is in progress (not Game Over, not
	                                      already won and sitting on the victory screen is fine too)
	  abandon(session, profile, PlayerProfile) -> ok, reason
	                                      counts the run as abandoned (stats.runsAbandoned) and grants nothing:
	                                      no rewards, no leaderboard submission, no win.
	The caller then starts a fresh session exactly like New Run (startNewSession) and the client returns
	to the main menu.
]]

local RunAbandon = {}

local ABANDONABLE = { roundSelect = true, playing = true, shop = true, nightVictory = true }

function RunAbandon.canAbandon(session)
	if type(session) ~= "table" or type(session.state) ~= "table" then
		return false, "no run"
	end
	local phase = session.phase or session.state.phase -- the server keeps the phase on the session
	if not ABANDONABLE[phase] then
		return false, "run is not in progress"
	end
	return true
end

function RunAbandon.abandon(session, profile, PlayerProfile)
	local ok, reason = RunAbandon.canAbandon(session)
	if not ok then return false, reason end
	-- a run already won (Night 8 boss cleared, win recorded by the server sync) is quit, not abandoned
	if profile and not (type(session.state) == "table" and session.state.wonRun == true) then
		PlayerProfile.recordRunAbandoned(profile)
	end
	return true
end

return RunAbandon
