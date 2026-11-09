--[[
	Engine/PanelLayout.lua
	Shared numbers for the account panel tab strip (Client/PanelTabs.lua) and the Expand button (Client/ExpandToggle.lua),
	so a corner control can never sit under the strip. Pure Lua, no Roblox APIs.
	The strip covers y 3 to 37. Centered panels are nudged down STRIP_NUDGE once while a tab strip is attached.
]]

local PanelLayout = {}

PanelLayout.STRIP_BOTTOM = 37
PanelLayout.STRIP_NUDGE = 24
PanelLayout.EXPANDED_MARGIN = 96 -- an expanded panel is (screen height - this) tall, so it is 48px off the top before the nudge
PanelLayout.TOGGLE_INSET = 8 -- toggle sits this far below the panel top
PanelLayout.TOGGLE_SIZE = 30

-- Where the Expand button's top edge lands on screen for a centered panel of the given height.
function PanelLayout.toggleTop(screenH, panelH, nudged)
	local panelTop = (screenH - panelH) / 2 + (nudged and PanelLayout.STRIP_NUDGE or 0)
	return panelTop + PanelLayout.TOGGLE_INSET
end

function PanelLayout.expandedHeight(screenH)
	return screenH - PanelLayout.EXPANDED_MARGIN
end

-- True when a control with the given top edge and height overlaps the tab strip band (y 3 to 37).
function PanelLayout.hitsStrip(y, h)
	return y < PanelLayout.STRIP_BOTTOM and (y + h) > 3
end

return PanelLayout
