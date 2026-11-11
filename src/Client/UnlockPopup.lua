--[[
	Client/UnlockPopup.lua
	FEATURE 12: a quick celebratory card shown whenever a NEW Patron or Theme
	appears in the state compared to the previous render() -- render() does
	the "is this actually new" diff check and calls showUnlockPopup() when
	it finds one.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files.

	NOTE: deliberately NOT using addSoftShadow() here, unlike most other
	overlays. addSoftShadow() parents its shadow Frame into panel.Parent and
	sizes it to 100% of that parent -- every backdrop-based overlay's panel
	lives inside a full-screen "xBackdrop" Frame whose Visible=false cascades
	down to hide the shadow too. This popup is a small floating card parented
	directly to screenGui (no backdrop), so that shadow would default to
	Visible=true and sit as a permanent ~full-screen 55%-opaque black layer
	over everything -- this was root-caused as the cause of a "dark right
	away" regression once already. Skipping the shadow avoids it entirely;
	the rounded corners from polishPanel are enough polish.

	deps fields:
		screenGui   -- ScreenGui, this popup's parent (no backdrop)
		polishPanel  -- function(instance, radius)
		tweenTo      -- function(instance, props, duration, easingStyle?, easingDirection?)

	Returns:
		{
			showUnlockPopup = function(name, description),
		}
]]

return function(deps)
	-- A corner toast now (Client/CornerToast, via OverlayQueue): "Unlocked: Straight Shooter", several merge into one. The effect text
	-- (the description) lives in the Collection, so the toast carries the name only.
	local function showUnlockPopup(name, _description)
		local OverlayQueue = require(script.Parent.OverlayQueue)
		OverlayQueue.enqueue({
			id = "unlockPatron:" .. tostring(name),
			priority = OverlayQueue.rules.PRIORITY.unlock,
			group = "unlock",
			title = "Unlocked!",
			rows = { name },
		})
	end

	return {
		showUnlockPopup = showUnlockPopup,
	}
end
