--[[
	Shared/Engine/TableCheck.lua
	Pure rules for the Studio only table rect self check (DebugGoto "tablecheck", Client/TableCheck). The reference picture is 1672 x 941;
	each live piece is converted to that scale and compared with its target rect. A target may leave y open (nil).

	TableCheck.TARGETS                    list of { key, x0, x1, y0, y1 } in reference pixels
	TableCheck.TOLERANCE                  25 px
	TableCheck.toReference(rect, guiW)    -> rect in reference pixels (x, y, w, h)
	TableCheck.compare(live, guiW)        live: key -> { x, y, w, h } in GUI pixels; returns lines, warnings
]]
local M = {}

M.REF_W, M.REF_H = 1672, 941
M.TOLERANCE = 25

M.TARGETS = {
	{ key = "TargetBox", x0 = 410, x1 = 700, y0 = 15, y1 = 100 },
	{ key = "RoundName", x0 = 722, x1 = 1130 }, -- the rule scroll
	{ key = "TipsPill", x0 = 1150, x1 = 1395, y0 = 15, y1 = 100 },
	{ key = "PatronSlots", x0 = 410, x1 = 1255, y0 = 125, y1 = 330 }, -- all seats together
	{ key = "ScorePlate", x0 = 680, x1 = 995, y0 = 365, y1 = 455 },
	{ key = "RoundHint", x0 = 18, x1 = 335, y0 = 345, y1 = 485 },
	{ key = "SortRank", x0 = 25, x1 = 185, y0 = 810, y1 = 900 },
	{ key = "SortSuit", x0 = 203, x1 = 358, y0 = 810, y1 = 900 },
	{ key = "PlayHand", x0 = 530, x1 = 840, y0 = 810, y1 = 900 },
	{ key = "Discard", x0 = 865, x1 = 1180, y0 = 810, y1 = 900 },
	{ key = "DeckCountPill", x0 = 1430, x1 = 1645 },
}

function M.scales(guiW, guiH)
	local w = math.max(1, tonumber(guiW) or M.REF_W)
	local h = math.max(1, tonumber(guiH) or (w * M.REF_H / M.REF_W))
	return M.REF_W / w, M.REF_H / h
end

-- The top inset the layout space has and AbsolutePosition leaves out. GetGuiInset can read 0 live, so fall back to the viewport height minus
-- the ScreenGui's height, then to how far above 0 the game root sits. Never negative.
function M.insetFrom(guiInset, viewportH, guiH, rootY)
	local a = tonumber(guiInset) or 0
	if a > 0 then return a end
	local v, g = tonumber(viewportH), tonumber(guiH)
	if v and g and v - g > 0 then return v - g end
	local r = tonumber(rootY) or 0
	if r < 0 then return -r end
	return 0
end

function M.toReference(rect, guiW, guiH, insetY)
	local kx, ky = M.scales(guiW, guiH)
	return { x = rect.x * kx, y = (rect.y + (tonumber(insetY) or 0)) * ky, w = rect.w * kx, h = rect.h * ky }
end

local function fmt(n) return string.format("%d", math.floor(n + 0.5)) end

-- How far each given edge is from its target, and the worst of them.
function M.diff(ref, t)
	local d = { x0 = ref.x - t.x0, x1 = ref.x + ref.w - t.x1 }
	if t.y0 then d.y0 = ref.y - t.y0 end
	if t.y1 then d.y1 = ref.y + ref.h - t.y1 end
	local worst = 0
	for _, v in pairs(d) do worst = math.max(worst, math.abs(v)) end
	return d, worst
end

-- Returns the report lines (one per target) and the warnings (pieces more than TOLERANCE off). A missing piece is a line, not a warning.
function M.compare(live, guiW, guiH, insetY)
	local lines, warns = {}, {}
	for _, t in ipairs(M.TARGETS) do
		local r = live[t.key]
		if not r then
			lines[#lines + 1] = string.format("%-14s not found on screen", t.key)
		else
			local ref = M.toReference(r, guiW, guiH, insetY)
			local d, worst = M.diff(ref, t)
			local ys = t.y0 and string.format(" y %s-%s", fmt(ref.y), fmt(ref.y + ref.h)) or ""
			local ty = t.y0 and string.format(" y %d-%d", t.y0, t.y1) or ""
			lines[#lines + 1] = string.format("%-14s x %s-%s%s  target x %d-%d%s  worst off %s px", t.key, fmt(ref.x), fmt(ref.x + ref.w), ys, t.x0, t.x1, ty, fmt(worst))
			if worst > M.TOLERANCE then
				local dy = d.y0 and string.format(", dy0 %s, dy1 %s", fmt(d.y0), fmt(d.y1)) or ""
				warns[#warns + 1] = string.format("%s is %s px from the reference (dx0 %s, dx1 %s%s)", t.key, fmt(worst), fmt(d.x0), fmt(d.x1), dy)
			end
		end
	end
	return lines, warns
end

return M
