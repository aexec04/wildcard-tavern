--[[
	Engine/DockRules.lua
	Pure rule for the top right corner icon dock (the five round buttons and the daily chest, Client/CornerDock.lua): whether the dock is
	shown is a function of the CURRENT state, never of a remembered boolean, so no open and close order can leave it hidden for good.

	visible(flags) -> bool    flags = { panelOpen = a registered full screen / account page backdrop is visible,
	                                    roundSelect = Round Select is up (its own modal hides the dock) }
	The daily chest inside the dock has its own rule (Engine/DailyPopup.canOffer) and does not change this.
]]

local M = {}

function M.visible(flags)
	flags = flags or {}
	return not (flags.panelOpen == true or flags.roundSelect == true)
end

return M
