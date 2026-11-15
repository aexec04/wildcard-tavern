--[[
	Engine/DockRules.lua
	Pure rule for the top right corner icon dock (the five round buttons and the daily chest, Client/CornerDock.lua): whether the dock is
	shown is a function of the CURRENT state, never of a remembered boolean, so no open and close order can leave it hidden for good.

	visible(flags) -> bool    flags = { panelOpen = a registered full screen / account page backdrop is visible,
	                                    roundSelect = Round Select is up (its own modal hides the dock),
	                                    counter = the Counter is open (a full screen scene drawn over the dock) }
	The Counter's art covers the dock, but covered is not hidden: the icons under it still took the pointer (their
	tooltips came up over the Tips plate, a tap there opened the Tavern Map, and the mute slash showed through).
	The daily chest inside the dock has its own rule (Engine/DailyPopup.canOffer) and does not change this.
]]

local M = {}

function M.visible(flags)
	flags = flags or {}
	return not (flags.panelOpen == true or flags.roundSelect == true or flags.counter == true)
end

return M
