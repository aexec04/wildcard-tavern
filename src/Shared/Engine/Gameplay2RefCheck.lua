--[[
	Engine/Gameplay2RefCheck.lua
	Compares the table's live rects with the reference mockup (claude/reference/concept-table-reference.png, 1672 x 941).
	REF holds the 14 pieces measured off the picture; compare(live, w, h) scales the reference to the screen (x by w / 1672,
	y by h / 941) and reports every piece whose centre is more than CENTRE_PX off or whose size is more than SIZE_PCT off.
	Used by the Studio only [RefCheck] warn in Client/Gameplay2 and by tools/ref_check_report.lua.

	live = { name = {x, y, w, h} } using the names in REF.
]]

local M = {}

M.REF_W, M.REF_H = 1672, 941
M.CENTRE_PX = 12
M.SIZE_PCT = 12

-- name = { x, y, w, h } in reference pixels
M.REF = {
	speaker = { 52, 12, 96, 96 },
	pause = { 165, 12, 96, 96 },
	target = { 543, 18, 300, 80 },
	scroll = { 855, 12, 408, 90 },
	patronRow = { 410, 122, 847, 207 },
	scorePlate = { 678, 366, 320, 92 },
	sortRank = { 24, 814, 160, 80 },
	sortSuit = { 203, 814, 156, 80 },
	handsPill = { 618, 773, 165, 34 },
	discardsPill = { 913, 773, 177, 34 },
	play = { 528, 808, 312, 96 },
	discard = { 862, 808, 310, 96 },
	deckPlate = { 1428, 832, 222, 70 },
}

M.ORDER = { "speaker", "pause", "target", "scroll", "patronRow", "scorePlate", "sortRank", "sortSuit",
	"handsPill", "discardsPill", "play", "discard", "deckPlate" }

-- The reference rect scaled to a w x h screen.
function M.scaled(name, w, h)
	local r = M.REF[name]
	if not r then return nil end
	local sx, sy = w / M.REF_W, h / M.REF_H
	return { x = r[1] * sx, y = r[2] * sy, w = r[3] * sx, h = r[4] * sy }
end

M.QUICK_Y_FREE = { speaker = true, pause = true } -- also free in size and x: the three round icons shrink to clear the painted banner (GearMenu.quickSize)

-- One row per piece present in live: { name, dx, dy, sizePct, bad }
function M.compare(live, w, h)
	local rows = {}
	for _, name in ipairs(M.ORDER) do
		local a, b = live[name], M.scaled(name, w, h)
		if a and b then
			local dx = (a.x + a.w / 2) - (b.x + b.w / 2)
			local dy = (a.y + a.h / 2) - (b.y + b.h / 2)
			if M.QUICK_Y_FREE[name] then dy = 0; dx = 0 end -- the round buttons sit below Roblox's core buttons (GearMenu.CORE_CLEAR_Y), not at the mockup height
			local sw = math.abs(a.w - b.w) / b.w * 100
			local sh = math.abs(a.h - b.h) / b.h * 100
			local pct = M.QUICK_Y_FREE[name] and 0 or math.max(sw, sh)
			rows[#rows + 1] = { name = name, dx = dx, dy = dy, sizePct = pct,
				bad = math.abs(dx) > M.CENTRE_PX or math.abs(dy) > M.CENTRE_PX or pct > M.SIZE_PCT }
		end
	end
	return rows
end

function M.badCount(rows)
	local n = 0
	for _, r in ipairs(rows) do if r.bad then n = n + 1 end end
	return n
end

-- The 13 live rects from the layout (rects = Gameplay2Layout.rects, quick = GearMenu.quickRects, plate = idle Score plate rect or nil)
function M.liveFrom(rects, quick, plate)
	local s1, s5 = rects.slots[1].card, rects.slots[#rects.slots].card
	local live = {
		target = rects.target, scroll = rects.round,
		patronRow = { x = s1.x, y = s1.y, w = s5.x + s5.w - s1.x, h = s1.h },
		sortRank = rects.sortRank, sortSuit = rects.sortSuit,
		handsPill = rects.playCount, discardsPill = rects.discardCount,
		play = rects.play, discard = rects.discard, deckPlate = rects.deckCount,
		scorePlate = plate,
	}
	if quick then live.speaker, live.pause = quick.speaker, quick.pause end
	return live
end

return M
