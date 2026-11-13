--[[
	Engine/PatronRowRules.lua
	Pure rule (tested) for whether the Patron Row stands on screen. Client/PatronRow is the only writer of its visibility and asks this
	every time anything changes, so no screen order can leave the row floating over the Counter or a panel.

	visible(flags) -> bool    flags = { phase = state.phase, rootVisible, handVisible, panelOpen (a full screen page is up),
	                                    seats = number of Patron seats }
	The row exists only on the play table: phase "playing", the hand shown, no page over it, at least one seat.
	Shop, Round Select, Game Over and the Menu (root hidden) all hide it.
]]

local M = {}

function M.visible(flags)
	flags = flags or {}
	if flags.phase ~= "playing" then return false end
	if flags.rootVisible == false or flags.handVisible ~= true then return false end
	if flags.panelOpen == true then return false end
	return (flags.seats or 0) > 0
end

return M
