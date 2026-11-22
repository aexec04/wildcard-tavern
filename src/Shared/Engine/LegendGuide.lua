--[[
	Shared/Engine/LegendGuide.lua
	The "Marks and boons" guide on the Tome Legend tab: a Guide plate beside Close opens the shared popup (Client/BoonsPage.openView) with one short,
	kind entry for the card Marks and one for the Night boons, each with a drawn icon. Words only, no numbers that can drift: the exact
	numbers live on the Marks page and the boon cards.
	  LegendGuide.view()                -> { title, count, rows = { { id, name, icon, line, seen = true, art, artKey } }, seen, total }
	  LegendGuide.footer(panelW, panelH) -> { close = rect, guide = rect } in panel pixels, both 44 px tall, side by side, never overlapping
	Every line is 60 characters or less and every text is 16 px or more.
]]

local LegendGuide = {}

LegendGuide.TITLE = "Marks and Night boons"
LegendGuide.SUB = "Two small helpers that start at Night 2."
LegendGuide.BUTTON = "Marks and boons"
LegendGuide.TEXT_SIZE = 16
LegendGuide.BUTTON_H = 44

LegendGuide.ENTRIES = {
	-- the Mark icon is a drawn tag (emoji); the boon uses the painted boon art
	{ id = "guide_marks", name = "Marks", icon = "🔖", line = "Buy one at the Counter. That card scores a bit more." },
	{ id = "guide_boons", name = "Night boons", icon = "✨", line = "Pick one gift each Night. It helps all run long.", art = "boon_icons", artKey = "extra_hand" },
}

function LegendGuide.view()
	local rows = {}
	for _, e in ipairs(LegendGuide.ENTRIES) do
		rows[#rows + 1] = { id = e.id, name = e.name, icon = e.icon, line = e.line, seen = true, art = e.art, artKey = e.artKey }
	end
	return { title = LegendGuide.TITLE, count = LegendGuide.SUB, rows = rows, seen = #rows, total = #rows }
end

-- Close stays centred under the scene; the guide plate sits to its right, 12 px apart. Both 44 px tall, 10 px above the panel bottom.
LegendGuide.CLOSE_W, LegendGuide.GUIDE_W, LegendGuide.GAP, LegendGuide.BOTTOM_GAP = 120, 200, 12, 10
function LegendGuide.footer(panelW, panelH)
	local h = LegendGuide.BUTTON_H
	local y = panelH - LegendGuide.BOTTOM_GAP - h
	local close = { x = math.floor((panelW - LegendGuide.CLOSE_W) / 2), y = y, w = LegendGuide.CLOSE_W, h = h }
	local guide = { x = close.x + close.w + LegendGuide.GAP, y = y, w = LegendGuide.GUIDE_W, h = h }
	return { close = close, guide = guide }
end

return LegendGuide
