--[[
	BossRush.lua
	Boss Rush: unlocked after the first run win. A run of back-to-back Boss Rounds with the Patrons the player picked
	at the start (three of six open ones); there is no shop. Each boss is a harder tier than the last (BossRounds.pick
	gates by Night, and every boss is a new "Night"), the targets climb with the Night, and the run ends at the first
	loss. The score is how many bosses were beaten, kept as a personal best. Pure Lua, no Roblox APIs.

	How it plugs into a run (Engine/RunState.lua):
	  * RunState.new({ rush = true }) calls BossRush.configure: one round per Night (every round is a boss) and a
	    Night cap so high the run is never "won": it only ends in a loss.
	  * The server (Server/init.server.lua) skips the shop after a cleared round and goes straight to the next boss.
	  * A Rush run never counts toward Night records, wins, stakes or unlocks (RunState.countsForRecords).
	Profile: bossRushBest (most bosses beaten in one run).
]]

local BossRush = {}

BossRush.PICKS = 3 -- Patrons the player takes along
BossRush.OFFERS = 6 -- open Patrons offered
BossRush.NIGHT_CAP = 999

function BossRush.isUnlocked(profile)
	return ((profile and profile.stats and profile.stats.runsWon) or 0) >= 1
end

-- Sets a fresh run up as a Rush before its first round is dealt.
function BossRush.configure(state)
	state.config.roundsPerNight = 1
	state.config.nightCap = BossRush.NIGHT_CAP
	state.rush = { started = true }
end

function BossRush.isRush(state)
	return state ~= nil and state.rush ~= nil
end

-- Bosses beaten so far in this run.
function BossRush.score(state)
	return state.bossesCleared or 0
end

-- Saves the run's score as the personal best when it is higher. Returns true for a new best.
function BossRush.record(profile, bosses)
	bosses = math.max(0, math.floor(bosses or 0))
	if bosses > (profile.bossRushBest or 0) then
		profile.bossRushBest = math.min(bosses, 9999)
		return true
	end
	return false
end

function BossRush.view(profile)
	return { unlocked = BossRush.isUnlocked(profile), best = profile.bossRushBest or 0 }
end

-- The line on the Run Setup Boss Rush card.
function BossRush.setupText(view)
	if view and view.unlocked then
		return "Boss after boss with 3 Patrons you pick. No shop. Best: " .. tostring(math.floor(view.best or 0))
	end
	return "Locked. Win a run first."
end

function BossRush.cleanSaved(raw)
	if type(raw) == "number" and raw == raw then
		return math.max(0, math.min(9999, math.floor(raw)))
	end
	return 0
end

return BossRush
