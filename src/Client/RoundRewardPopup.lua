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
		-- A normal Round Complete is a non-blocking banner that counts up, holds about 2.2 s and fades on its own (Client/RoundRewardBanner,
		-- timing in Engine/RewardBanner): no Continue click and the Counter is usable at once. The one-time Night-cleared headline
		-- (titleOverride) and Tag rewards (no interest, one line of text) are momentous or different results and keep the plate.
		if interest ~= nil and titleOverride == nil then
			-- one message at a time in the centre: the banner goes through the Announcer (Client/Announcer), which also merges the Counter's
			-- flavor line (Big spender today!) into it as one small line under the Total
			local Banner = require(script.Parent.RoundRewardBanner)
			require(script.Parent.Announcer).submit({
				id = "round_complete", kind = "round_complete", priority = 3, duration = 2.6,
				show = function(done, msg)
					Banner.show({ screenGui = deps.screenGui, title = "Round Complete!", amount = amount, interest = interest, flavor = msg and msg.flavor, onClose = done })
				end,
				hide = function() Banner.close() end,
			})
			return
		end
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
