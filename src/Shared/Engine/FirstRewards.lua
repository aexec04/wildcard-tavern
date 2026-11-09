--[[
	FirstRewards.lua
	The one-time rewards of the first 5 minutes and the one-time follow prompt. Pure Lua, no Roblox APIs.

	  tutorial(profile)   finishing the tutorial (not skipping it): the Closing Lantern card back and the Newcomer
	                      title (Achievements "first_steps" opens once profile.tutorialRewardClaimed is true).
	  firstWin(profile)   the first run ever won: a bigger reward, the Ember Hours card back and 10 Tips banked
	                      for the next run (the Tavern Keeper title already comes from the Grand Finale achievement).
	  followDue(profile)  true exactly once, right after the first win, to offer Roblox experience notifications.

	Each returns a notice { icon, text } for the toast, or nil when it was already given.
]]

local TavernRank = require(script.Parent.TavernRank)

local FirstRewards = {}

FirstRewards.TUTORIAL_CARD_BACK = "closing_lantern"
FirstRewards.FIRST_WIN_CARD_BACK = "ember_hours"
FirstRewards.FIRST_WIN_TIPS = 10

function FirstRewards.tutorial(profile)
	if profile.tutorialRewardClaimed then
		return nil
	end
	profile.tutorialRewardClaimed = true
	profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
	profile.unlockedCardBackIds[FirstRewards.TUTORIAL_CARD_BACK] = true
	return { icon = "🎓", text = "Tutorial complete! Card back: Closing Lantern. Title: Newcomer" }
end

function FirstRewards.firstWin(profile)
	if profile.firstWinRewardClaimed then
		return nil
	end
	profile.firstWinRewardClaimed = true
	profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
	profile.unlockedCardBackIds[FirstRewards.FIRST_WIN_CARD_BACK] = true
	profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + FirstRewards.FIRST_WIN_TIPS)
	return { icon = "🏆", text = "First win! Card back: Ember Hours. +10 Tips next run" }
end

function FirstRewards.followDue(profile)
	if profile.followPrompted then
		return false
	end
	profile.followPrompted = true
	return true
end

return FirstRewards
