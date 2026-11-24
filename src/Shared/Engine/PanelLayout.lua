--[[
	Engine/PanelLayout.lua
	Shared numbers for the account panel tab strip (Client/PanelTabs.lua) and the Expand button (Client/ExpandToggle.lua),
	so a corner control can never sit under the strip. Pure Lua, no Roblox APIs.
	The strip covers y 3 to 81. Centered panels are nudged down STRIP_NUDGE once while a tab strip is attached.
]]

local PanelLayout = {}

PanelLayout.TAB_H = 44 -- Back and the page tabs are 44 px touch targets (the wide group tabs above them stay 34 px to keep the page body tall)
PanelLayout.GROUP_H = 34
PanelLayout.STRIP_BOTTOM = 3 + 34 + 44 -- group tabs (y 3 to 37) plus the page tab ribbons (y 37 to 81)
PanelLayout.STRIP_NUDGE = 40
PanelLayout.BACK_W, PanelLayout.BACK_H = 84, 44 -- the "< Back" plate at the strip's left edge, as tall as the tabs; the tab rows start at BACK_ROW_X
PanelLayout.BACK_ROW_X = 92
PanelLayout.EXPANDED_MARGIN = 100 -- an expanded panel is (screen height - this) tall, so it is 50px off the top before the nudge
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

-- Same report for a FULL_SCREEN page: it is not centered or nudged, it sits at y STRIP_BOTTOM + 2 and is (screen height - that) tall, so its
-- bottom edge lands exactly on the bottom of the window. fits = on screen and below the strip.
function PanelLayout.fitFullScreen(screenH, panelH)
	local top = PanelLayout.STRIP_BOTTOM + 2
	local bottom = top + (panelH or (screenH - top))
	return { top = top, bottom = bottom, fits = bottom <= screenH and top >= PanelLayout.STRIP_BOTTOM }
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

-- Extra height (offset pixels, 0 to 200) a full screen panel needs so its bottom edge reaches the bottom of the ScreenGui: the panel's
-- absolute top (panelY) plus its height (panelH) can stop short of the GUI height (guiH) when the backdrop sits above the GUI origin.
function PanelLayout.fullScreenGap(guiH, panelY, panelH)
	local gap = (guiH or 0) - ((panelY or 0) + (panelH or 0))
	if gap <= 2 then return 0 end
	return math.min(200, math.floor(gap + 0.5))
end

return PanelLayout
