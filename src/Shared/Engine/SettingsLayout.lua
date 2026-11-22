--[[
	Shared/Engine/SettingsLayout.lua
	Pure numbers for the Settings board (Client/Settings.lua): the order of its sections, the painted switch (clear On and Off fill plus
	the word), the 44 px touch sizes and the one primary Close button. Calm mode and Reduce Motion are always the first two rows.

	M.SECTIONS          list of { id, title, rows = { rowId, ... } } in display order
	M.rowOrder()        flat list of row ids in display order
	M.SWITCH            { w, h, onFill, offFill, onText, offText } (colours are {r, g, b})
	M.CLOSE             { w, h } the primary Close button
	M.contrast(a, b)    WCAG contrast of two {r, g, b}
	M.calmValue(vals)   true when every calm key is on (the Calm mode switch shows On)
	M.calmWrites(on)    what the Calm mode switch sets: reduceMotion, reduceFlashing and reduceShake
]]

local M = {}

M.SECTIONS = {
	{ id = "comfort", title = "Comfort", rows = { "calmMode", "reduceMotion", "reduceFlashing", "reduceShake", "largerText", "colorblindSuits" } },
	{ id = "sound", title = "Sound", rows = { "volume" } },
	{ id = "help", title = "Help", rows = { "replayTutorial", "replayHints" } },
	{ id = "display", title = "Display", rows = { "animSpeed", "performanceMode" } },
	{ id = "gameplay", title = "Gameplay", rows = { "roundHints", "confirmDiscard", "allowSpectators", "holdConfirmSeconds" } },
}

function M.rowOrder()
	local out = {}
	for _, s in ipairs(M.SECTIONS) do
		for _, r in ipairs(s.rows) do out[#out + 1] = r end
	end
	return out
end

M.MIN_TOUCH = 44
M.SWITCH = {
	w = 104, h = 44,
	onFill = { 46, 112, 56 }, offFill = { 74, 52, 34 },
	onText = { 255, 255, 255 }, offText = { 244, 232, 208 },
}
M.CLOSE = { w = 160, h = 48 }
-- Pause look (Settings doubles as the pause screen): Close reads Resume, Main Menu reads Quit to Tavern, every plate is 44 px or more,
-- the panel is dark wood with a gold edge and cream text; the On/Off state is the word and the fill, never colour alone.
M.PAUSE = {
	resumeText = "Resume", quitText = "Quit to Tavern", plateH = 44,
	panelFill = { 40, 30, 22 }, edge = { 200, 165, 90 }, text = { 250, 240, 220 }, plateFill = { 90, 60, 30 },
}
-- Panel geometry as Client/Settings.lua builds it (panel 0.5 x 0.8 of the screen, scroll 20 px in from each side, 48 px
-- title strip above and 62 px below), so tests can check phone and tablet sizes without Roblox.
-- The panel sits between y 110 and y 850 at 957 px tall (fy 0.115, fh 0.773) so it clears the Night plate and the table's
-- Play Hand and Discard buttons. The Resume button is retired (the X closes), so the scroll ends 16 px above the panel bottom.
M.PANEL = { fw = 0.5, fy = 0.115, fh = 0.773, sidePad = 20, top = 48, bottomReserve = 16, rowH = 62, textGutter = 130, replayW = 110, replayH = 44 }
-- Account plates: painted serif plates 56 px tall, three in the first row, two (Daily Rewards, Tavern Map) in the second.
M.ACCOUNT = { plateH = 56, gap = 10, textSize = 18, perRow = 3, secondRow = 2 }

-- Rects of the five Account plates relative to the scroll canvas (x from its left edge, y from the top of the first Account row).
-- Client/Settings.lua sizes the rows and plates from the same numbers, so the test and the live layout cannot drift apart.
-- Row one holds three plates, row two holds two (Daily Rewards, Tavern Map); both rows share the full scroll width.
function M.accountRects(scrollW)
	local A = M.ACCOUNT
	local rects = {}
	local function row(count, y)
		local w = math.floor((scrollW - A.gap * (count - 1)) / count)
		for i = 1, count do
			rects[#rects + 1] = { x = (i - 1) * (w + A.gap), y = y, w = w, h = A.plateH }
		end
	end
	row(A.perRow, 0)
	row(A.secondRow, A.plateH + 8)
	return rects, 2 * A.plateH + 8
end

function M.panelRects(W, H)
	local P = M.PANEL
	local pw, ph = math.floor(W * P.fw), math.floor(H * P.fh)
	local sw, sh = pw - P.sidePad * 2, ph - P.top - P.bottomReserve
	return {
		panel = { x = math.floor(W * (1 - P.fw) / 2), y = math.floor(H * P.fy), w = pw, h = ph },
		scroll = { x = P.sidePad, y = P.top, w = sw, h = sh },
		textW = sw - P.textGutter,
	}
end

M.SLIDER_THUMB = 44 -- touch target around the slider knob (Client/VisualHelpers KnobHit)

local function lum(c)
	local function f(v)
		v = v / 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
end

function M.contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

function M.calmValue(vals)
	return vals.reduceMotion == true and vals.reduceFlashing == true and vals.reduceShake == true
end

function M.calmWrites(on)
	return { reduceMotion = on, reduceFlashing = on, reduceShake = on }
end

return M
