--[[
	Shared/Engine/MenuGate.lua
	Pure rules for "the Main Menu stays up and usable until Play is pressed" (tested; applied by Client/MenuGate.lua).
	After Restart Run, Settings > Main Menu, a Daily confirm or Run Over > Main Menu, the server pushes the new run's state. That state
	must not bring the table (GameRoot) or a run modal (the opening blessing, a road choice, a Night Victory ...) over the Menu: those
	wait until Play, which hides the Menu first and then shows GameRoot.

	MenuGate.RUN_MODALS               names of the full-screen run modals that never show over the Menu
	MenuGate.mustHide(name, menuOpen) true when this modal is visible while the Menu is open
	MenuGate.rootAllowed(menuOpen)    the table may be visible only while the Menu is closed
	MenuGate.sinks(list, menuName)    names of visible, click-sinking top-level objects other than the Menu (debug report)
]]

local MenuGate = {}

MenuGate.RUN_MODALS = {
	ChoiceBackdrop = true, RoadChoiceBackdrop = true, NightVictoryBackdrop = true, RunSummaryBackdrop = true, VictoryBackdrop = true,
	OverlayQueueBackdrop = true, WinCardBackdrop = true, BossFlashOverlay = true,
}

function MenuGate.mustHide(name, menuOpen)
	return menuOpen == true and MenuGate.RUN_MODALS[name] == true
end

function MenuGate.rootAllowed(menuOpen)
	return menuOpen ~= true
end

-- list = { { name, visible, active }, ... } of the ScreenGui's children; the names that can swallow a click over the Menu
function MenuGate.sinks(list, menuName)
	local out = {}
	for _, e in ipairs(list or {}) do
		if e.name ~= menuName and e.visible and e.active then table.insert(out, e.name) end
	end
	return out
end

return MenuGate
