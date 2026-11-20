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
M.WATCH = { "shop", "patrons", "recipes", "passes", "packs", "reroll", "next round", "next boss", "boss", "deal me in", "rank", "level" }

function M.isWatched(text)
	local t = string.lower(tostring(text or ""))
	if t == "" then return false end
	for _, w in ipairs(M.WATCH) do
		if t:find(w, 1, true) then return true end
	end
	return false
end

-- Menu pieces that must be on screen: { label, how to find it } (Client/ScreenCheck matches by Name or by text)
M.MENU_PIECES = {
	{ label = "Title", names = { "WordmarkImage", "MenuTitle" } },
	{ label = "Deal Me In", text = "deal me in" },
	{ label = "New Run", text = "new run" },
	{ label = "All actions", names = { "AllActionsButton" } },
	{ label = "Tip bar", names = { "MenuTip" } },
	{ label = "Notice Board", names = { "NoticeBoard" } },
}

-- pieces = { { label, w, h, visible } } (a missing piece has w = 0); returns lines, warns. A piece with width or height 0, or not
-- visible, is a WARN: that is how a blank or 0x0 Menu piece gets caught.
function M.menuCheck(pieces)
	local lines, warns = {}, {}
	for _, p in ipairs(pieces or {}) do
		local w, h = tonumber(p.w) or 0, tonumber(p.h) or 0
		lines[#lines + 1] = string.format("%s %dx%d%s", tostring(p.label), math.floor(w), math.floor(h), p.visible and "" or " hidden")
		if w <= 0 or h <= 0 or not p.visible then
			warns[#warns + 1] = string.format("WARN %s is blank: %dx%d, visible=%s", tostring(p.label), math.floor(w), math.floor(h), tostring(p.visible and true or false))
		end
	end
	return lines, warns
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

-- Boss round: the boss banner pieces (medallion, name plate) against the table pieces they must stay clear of (Target, Score plate,
-- Patron row). No reference picture exists for the banner, so this prints rects and warns only for overlap (more than TOLERANCE px
-- both ways) and for text under MIN_TEXT. banner = { { label, rect, size? } }, table = { { label, rect } }; rects { x, y, w, h }.
function M.bossCheck(banner, tablePieces)
	local lines, warns = {}, {}
	for _, b in ipairs(banner or {}) do
		local r = b.rect
		lines[#lines + 1] = string.format("%s x%d y%d %dx%d", tostring(b.label), math.floor(r.x), math.floor(r.y), math.floor(r.w), math.floor(r.h))
		if b.size and M.small(b.size) then warns[#warns + 1] = string.format("%s text is %d px, under %d", tostring(b.label), math.floor(b.size), M.MIN_TEXT) end
		for _, t in ipairs(tablePieces or {}) do
			local w, h = extent(r, t.rect)
			if w > M.TOLERANCE and h > M.TOLERANCE then
				warns[#warns + 1] = string.format("%s overlaps %s by %dx%d", tostring(b.label), tostring(t.label), math.floor(w), math.floor(h))
			end
		end
	end
	return lines, warns
end

return M
