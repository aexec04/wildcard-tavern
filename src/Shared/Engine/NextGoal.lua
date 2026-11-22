--[[
	NextGoal.lua
	The one goal shown on the main menu: a short line and a progress bar for the nearest meaningful thing to do.
	Pure Lua, no Roblox APIs; the server computes it and ships it as state.nextGoal.

	Priority (first that applies), every line 40 characters or fewer:
	  1 tutorial   the walkthrough was never finished or skipped
	  2 night1     Night 1 not cleared yet
	  3 chest      today's Daily chest is waiting
	  4 hire       a first run that never reached a shop
	  5 cardset    still on the starter look and no Card Set owned
	  6 quest      an unfinished daily quest (progress = its own bar)
	  7 firstWin   no run won yet (progress = best Night out of 8)
	  8 unlock     the closed Patron or Recipe closest to opening (Engine/Unlocks.closest)
	  9 rank       the next Tavern Rank
	  10 daily     the Daily Challenge, always available
	Every step is state based, so a finished one never comes back.

	NextGoal.compute(profile, day, names) -> { kind, icon, text, ratio }
	  names = { unlock = function(kind, id) -> display name | nil }
]]

local Quests = require(script.Parent.Quests)
local TavernRank = require(script.Parent.TavernRank)
local Unlocks = require(script.Parent.Unlocks)
local LoginStreak = require(script.Parent.LoginStreak)
local CosmeticSets = require(script.Parent.CosmeticSets)

local NextGoal = {}

NextGoal.NIGHT_CAP = 8
NextGoal.MAX_CHARS = 40 -- every goal line fits one short banner line

local function clip(text)
	if #text <= NextGoal.MAX_CHARS then
		return text
	end
	return text:sub(1, NextGoal.MAX_CHARS - 3) .. "..."
end

-- A quest description kept inside MAX_CHARS once "Quest: " and "(n/m)" are added.
local function shortQuest(desc)
	local d = desc:gsub("%.$", "")
	local room = NextGoal.MAX_CHARS - #"Quest:  (99/99)"
	if #d > room then
		d = d:sub(1, room - 3) .. "..."
	end
	return d
end

function NextGoal.compute(profile, day, names)
	names = names or {}
	if not profile.hasSeenTutorial then
		return { kind = "tutorial", icon = "📖", text = "Next goal: finish the tutorial", ratio = 0 }
	end
	local stats = profile.stats or {}
	local best = stats.bestNightReached or 0
	-- 1. Night 1: the first thing a new player can finish in a few minutes
	if best < 2 and (stats.runsWon or 0) == 0 then
		return { kind = "night1", icon = "🌙", text = "Next goal: clear Night 1", ratio = 0 }
	end
	-- 2. the Daily chest, while today's reward is waiting
	local streak = profile.loginStreak or 0
	if streak >= 1 and LoginStreak.canClaim(profile, LoginStreak.slotFor(streak)) then
		return { kind = "chest", icon = "🎁", text = "Next goal: claim your Daily chest", ratio = 0 }
	end
	-- 3. hire a Patron: a first run that ended early never saw the shop
	if (stats.runsStarted or 0) <= 1 and (stats.handsPlayedTotal or 0) < 12 then
		return { kind = "hire", icon = "🧑", text = "Next goal: hire a Patron", ratio = 0 }
	end
	-- 4. try a Card Set: only while the player still uses the starter look and owns no other
	if profile.equippedSetId == CosmeticSets.DefaultId and next(profile.ownedSetIds or {}) == nil then
		return { kind = "cardset", icon = "🎴", text = "Next goal: try a Card Set", ratio = 0 }
	end
	-- 5. an unfinished daily quest, with its own bar
	if type(day) == "number" then
		local view = Quests.view(profile, day)
		for _, row in ipairs(view.quests) do
			if not row.done then
				return {
					kind = "quest", icon = row.icon,
					text = string.format("Quest: %s (%d/%d)", shortQuest(row.desc), row.progress, row.goal),
					ratio = row.progress / math.max(1, row.goal),
				}
			end
		end
	end
	-- 6. the first win, then the closest unlock, the next rank, and the Daily Challenge as the evergreen step
	if (stats.runsWon or 0) == 0 then
		local night = math.max(0, math.min(NextGoal.NIGHT_CAP, best))
		return {
			kind = "firstWin", icon = "🏆",
			text = string.format("Next goal: win a run (Night %d/%d)", night, NextGoal.NIGHT_CAP),
			ratio = night / NextGoal.NIGHT_CAP,
		}
	end
	local closest = Unlocks.closest(profile)
	if closest then
		local name = names.unlock and names.unlock(closest.kind, closest.id) or "something new"
		return {
			kind = "unlock", icon = "🔓",
			text = clip(string.format("Next unlock: %s", name)),
			ratio = closest.ratio,
		}
	end
	local rank = TavernRank.view(profile)
	if not rank.maxed then
		return {
			kind = "rank", icon = "🏅",
			text = string.format("Next rank: %d (%d/%d XP)", rank.nextRank, rank.into, rank.need),
			ratio = rank.need > 0 and rank.into / rank.need or 0,
		}
	end
	return { kind = "daily", icon = "📅", text = "Next goal: play the Daily Challenge", ratio = 0 }
end

return NextGoal
