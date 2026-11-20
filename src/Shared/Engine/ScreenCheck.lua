--[[
	Shared/Engine/ScreenCheck.lua
	Pure rules for the Studio only Counter and Menu check (DebugGoto "screencheck", Client/ScreenCheck). Reads only.
	ScreenCheck.WATCH            words (lower case) of the pieces whose rects are printed: the Counter tabs, Next Round, the boss strip,
	                             Deal Me In and the Menu Rank plate
	ScreenCheck.isWatched(text)  -> bool
	ScreenCheck.overlap(a, b)    -> overlap area (0 when apart); rects are { x, y, w, h }
	ScreenCheck.small(size)      -> bool   under MIN_TEXT
	ScreenCheck.report(items)    -> lines, warns   items = { { name, text, size, rect, watched, group } }: one line per item, a warning
	                             for text under MIN_TEXT and for watched pieces of different groups that overlap by more than 4 px both ways
]]
local M = {}

M.MIN_TEXT = 18
M.TOLERANCE = 4
M.WATCH = { "shop", "patrons", "recipes", "passes", "packs", "next round", "next boss", "boss", "deal me in", "rank", "level" }

function M.isWatched(text)
	local t = string.lower(tostring(text or ""))
	if t == "" then return false end
	for _, w in ipairs(M.WATCH) do
		if t:find(w, 1, true) then return true end
	end
	return false
end

function M.small(size) return (tonumber(size) or 0) < M.MIN_TEXT end

local function extent(a, b)
	return math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x), math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
end

function M.overlap(a, b)
	local w, h = extent(a, b)
	if w <= 0 or h <= 0 then return 0 end
	return w * h
end

function M.report(items)
	items = items or {}
	local lines, warns = {}, {}
	for _, it in ipairs(items) do
		local r = it.rect
		local size = math.floor(tonumber(it.size) or 0)
		lines[#lines + 1] = string.format("%s '%s' x%d y%d %dx%d text %d", it.name, it.text, math.floor(r.x), math.floor(r.y), math.floor(r.w), math.floor(r.h), size)
		if M.small(it.size) then warns[#warns + 1] = string.format("%s '%s' text is %d px, under %d", it.name, it.text, size, M.MIN_TEXT) end
	end
	for i = 1, #items do
		for j = i + 1, #items do
			local a, b = items[i], items[j]
			if a.watched and b.watched and a.group ~= b.group then
				local w, h = extent(a.rect, b.rect)
				if w > M.TOLERANCE and h > M.TOLERANCE then
					warns[#warns + 1] = string.format("%s '%s' overlaps %s '%s'", a.name, a.text, b.name, b.text)
				end
			end
		end
	end
	return lines, warns
end

return M
