--[[
	Shared/Engine/BoonChipLayout.lua
	Pure numbers for the Night boon chip on the table HUD (Client/BoonChip.lua): the active Night boon as a small chip just right of the top bar,
	level with the Tips pill and clear of the settings gear, the Patron seats and every other table plate. Wide enough gives icon and name,
	narrow gives the icon alone (the tap tooltip always carries the full one-line text).
	  BoonChipLayout.rect(w, h)    -> { x, y, w, h, showName } or nil when no clear spot exists
	  BoonChipLayout.tooltip(view) -> the one-line tooltip text, 60 characters or less
]]

local Gameplay2Layout = require(script.Parent.Gameplay2Layout)

local M = {}

M.TEXT_SIZE = 16
M.MIN_SIZE = 44        -- tap target
M.NAME_MIN_W = 150     -- icon, a gap and a 16 px name
M.MAX_W = 190
M.GAP = 8

local function intersects(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function M.rect(w, h)
	local r = Gameplay2Layout.rects(w, h)
	local left = r.bar.x + r.bar.w + M.GAP
	local right = (r.gear and r.gear.x or w) - M.GAP
	local avail = right - left
	if avail < M.MIN_SIZE then return nil end
	local cw = math.min(M.MAX_W, avail)
	local ch = math.max(M.MIN_SIZE, math.min(r.tips.h, 56))
	local chip = { x = left, y = r.tips.y + math.floor((r.tips.h - ch) / 2), w = cw, h = ch, showName = cw >= M.NAME_MIN_W }
	if chip.y < 0 or chip.y + chip.h > h or chip.x + chip.w > w then return nil end
	for name, rect in pairs(Gameplay2Layout.flat(r)) do
		if type(rect) == "table" and rect.x and intersects(chip, rect) then return nil, name end
	end
	return chip
end

function M.tooltip(view)
	if type(view) ~= "table" then return nil end
	local text = tostring(view.name) .. ": " .. tostring(view.text)
	if #text > 60 then text = tostring(view.text) end
	return text
end

return M
