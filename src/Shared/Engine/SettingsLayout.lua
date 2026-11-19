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
	{ id = "display", title = "Display", rows = { "animSpeed" } },
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
