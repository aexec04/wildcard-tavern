--[[
	Client/RoundRewardPopup.lua
	A visual callout ("+$X Tips") for how much you just earned when a round
	is won, plus a cash sound distinct from the shop Buy sound. render()
	calls showRoundReward(amount) once, right on the transition into the
	shop phase.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Parented to screenGui directly (no
	backdrop), same as UnlockPopup.lua -- see that module's comment for why
	addSoftShadow is deliberately skipped here too.

	deps fields:
		screenGui   -- ScreenGui, this popup's parent (no backdrop)
		polishPanel  -- function(instance, radius)
		tweenTo      -- function(instance, props, duration, easingStyle?, easingDirection?)
		playSfx      -- function(soundId, volume?, maxLength?)
		SOUND_IDS    -- table, for SOUND_IDS.roundReward

	Returns:
		{
			showRoundReward = function(amount, titleOverride?),
		}

	`titleOverride` (optional): GENRE PARITY -- lets a caller swap the
	default "Round Complete!" headline for something more momentous, used
	exactly once per run for the Ante-cap win moment (clearing the Boss
	Round of Night `nightCap` -- see init.client.lua's render()).
]]

return function(deps)
	-- The popup is now a plate in Client/OverlayQueue (one at a time, first in the order).
	local function showRoundReward(amount, titleOverride, interest)
		local OverlayQueue = require(script.Parent.OverlayQueue)
		local Payout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RoundPayout"))
		OverlayQueue.newRound()
		-- Tag rewards (Tip Jar) pass no interest and keep the one-line text.
		local rows = interest ~= nil and Payout.breakdown(amount, interest).lines or nil
		OverlayQueue.enqueue({
			id = "roundComplete",
			plate = true, -- a real result: it stays the big plate (everything smaller is a corner toast)
			priority = OverlayQueue.rules.PRIORITY.roundComplete,
			icon = "💰",
			title = titleOverride or "Round Complete!",
			text = rows == nil and string.format("+$%d Tips", math.floor(amount)) or nil,
			rows = rows,
			stagger = rows and Payout.STAGGER or nil,
			button = "Continue",
			sound = "coin",
		})
	end

	return {
		showRoundReward = showRoundReward,
	}
end
