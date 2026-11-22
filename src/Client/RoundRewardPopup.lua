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
	local function showRoundReward(amount, titleOverride, interest, boss)
		local OverlayQueue = require(script.Parent.OverlayQueue)
		OverlayQueue.newRound()
		-- Every round result (normal, boss, Night cleared, Tag rewards) is the one line corner banner: no big plate, no Continue,
		-- never takes clicks, gone by itself. titleOverride is ignored (the Night victory scene carries that headline).
		local Banner = require(script.Parent.RoundRewardBanner)
		require(script.Parent.Announcer).submit({
			id = "round_complete", kind = "round_complete", priority = 3, duration = 1.9,
			show = function(done, msg)
				Banner.show({ screenGui = deps.screenGui, title = "Round Complete!", amount = amount, interest = interest or 0, boss = boss == true, flavor = msg and msg.flavor, onClose = done })
			end,
			hide = function() Banner.close() end,
		})
	end

	return {
		showRoundReward = showRoundReward,
	}
end
