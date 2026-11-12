--[[
	Engine/PanelLayout.lua
	Shared numbers for the account panel tab strip (Client/PanelTabs.lua) and the Expand button (Client/ExpandToggle.lua),
	so a corner control can never sit under the strip. Pure Lua, no Roblox APIs.
	The strip covers y 3 to 63. Centered panels are nudged down STRIP_NUDGE once while a tab strip is attached.
]]

local PanelLayout = {}

PanelLayout.STRIP_BOTTOM = 63 -- group tabs (y 3 to 37) plus the hanging bookmark ribbons (y 39 to 63)
PanelLayout.STRIP_NUDGE = 40
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

-- Where a centered panel of height panelH lands on a screen of height screenH once the strip has nudged it down: its top and bottom edge
-- and whether it stays on screen (top below the strip, bottom inside the window). The [PanelFit] Studio lines print this.
function PanelLayout.fit(screenH, panelH, nudged)
	local top = (screenH - panelH) / 2 + (nudged ~= false and PanelLayout.STRIP_NUDGE or 0)
	local bottom = top + panelH
	return { top = top, bottom = bottom, fits = top >= PanelLayout.STRIP_BOTTOM - PanelLayout.STRIP_NUDGE and bottom <= screenH }
end

-- True when a control with the given top edge and height overlaps the tab strip band (y 3 to 63).
function PanelLayout.hitsStrip(y, h)
	return y < PanelLayout.STRIP_BOTTOM and (y + h) > 3
end

-- The account pages in FULL_SCREEN open as full-screen scenes like the Tavern Map: the panel fills the screen below the tab strip (no margins,
-- no outer border), the strip stays at the top, the corner dock is hidden (PanelTabs).
PanelLayout.FULL_SCREEN = { collection = true, cosmeticSets = true, badges = true, legend = true, flair = true, stats = true }
function PanelLayout.fullScreenRect(screenW, screenH)
	local top = PanelLayout.STRIP_BOTTOM + 2
	return { x = 0, y = top, w = screenW, h = screenH - top }
end

return PanelLayout
