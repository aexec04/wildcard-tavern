--[[
	NextGoal.lua
	The one goal shown on the main menu: a short line and a progress bar for the nearest meaningful thing to do.
	Pure Lua, no Roblox APIs; the server computes it and ships it as state.nextGoal.

	Priority (first that applies):
	  1 tutorial   the walkthrough was never finished or skipped
	  2 firstWin   no run has been won yet (progress = best Night out of 8)
	  3 quest      an unfinished daily quest (progress = its own bar)
	  4 unlock     the closed Patron or Recipe closest to opening (Engine/Unlocks.closest)
	  5 rank       the next Tavern Rank
	  6 done       top rank reached

	NextGoal.compute(profile, day, names) -> { kind, icon, text, ratio }
	  names = { unlock = function(kind, id) -> display name | nil }
]]

local Quests = require(script.Parent.Quests)
local TavernRank = require(script.Parent.TavernRank)
local Unlocks = require(script.Parent.Unlocks)

local NextGoal = {}

NextGoal.NIGHT_CAP = 8

function NextGoal.compute(profile, day, names)
	names = names or {}
	if not profile.hasSeenTutorial then
		return { kind = "tutorial", icon = "📖", text = "Next goal: finish the tutorial", ratio = 0 }
	end
	local stats = profile.stats or {}
	if (stats.runsWon or 0) == 0 then
		local night = math.max(0, math.min(NextGoal.NIGHT_CAP, stats.bestNightReached or 0))
		return {
			kind = "firstWin", icon = "🏆",
			text = string.format("Next goal: win your first run (best Night %d of %d)", night, NextGoal.NIGHT_CAP),
			ratio = night / NextGoal.NIGHT_CAP,
		}
	end
	if type(day) == "number" then
		local view = Quests.view(profile, day)
		for _, row in ipairs(view.quests) do
			if not row.done then
				return {
					kind = "quest", icon = row.icon,
					text = string.format("Daily quest: %s (%d/%d)", row.desc:gsub("%.$", ""), row.progress, row.goal),
					ratio = row.progress / math.max(1, row.goal),
				}
			end
		end
	end
	local closest = Unlocks.closest(profile)
	if closest then
		local name = names.unlock and names.unlock(closest.kind, closest.id) or "something new"
		return {
			kind = "unlock", icon = "🔓",
			text = string.format("Next unlock: %s. %s", name, closest.hint),
			ratio = closest.ratio,
		}
	end
	local rank = TavernRank.view(profile)
	if not rank.maxed then
		return {
			kind = "rank", icon = "🏅",
			text = string.format("Next rank: %d (%d / %d XP)", rank.nextRank, rank.into, rank.need),
			ratio = rank.need > 0 and rank.into / rank.need or 0,
		}
	end
	return { kind = "done", icon = "👑", text = "You reached the top rank. Try a higher stake.", ratio = 1 }
end

return NextGoal
