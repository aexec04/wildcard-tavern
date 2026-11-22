--[[
	Shared/Engine/BoonsPage.lua
	The Boons page of the Collection (Client/BoonsPage.lua): all 12 Night boons from Engine/NightBoons as rows, each seen or not seen yet,
	a "Seen N of 12" line, and the panel numbers at any window size. A boon is seen once it has been offered on a pick card
	(profile.seenBoonIds, sent as state.collection.boonsSeen). Boons are not part of the Collection percent, like Bonds.
	  BoonsPage.view(seenIds)   -> { title, count, rows = { { id, name, icon, line, seen } }, seen, total }
	  BoonsPage.layout(w, h)    -> { panel, header, list, close, rowH, rowsFit }  rects { x, y, w, h } in window pixels
	Text is 16 px or more, rows and the Close plate are 44 px or more, every line is 60 characters or less.
]]

local NightBoons = require(script.Parent.NightBoons)

local BoonsPage = {}

BoonsPage.TITLE = "Night boons"
BoonsPage.UNSEEN_LINE = "Not seen yet. Boons start at Night 2."
BoonsPage.EMPTY_LINE = "No boons seen yet. They start at Night 2."
BoonsPage.TEXT_SIZE = 16
BoonsPage.ROW_H = 64
BoonsPage.CLOSE_H = 48
BoonsPage.HEADER_H = 64
BoonsPage.PANEL_MAX_W, BoonsPage.PANEL_MAX_H = 640, 640

function BoonsPage.view(seenIds)
	local seenSet = {}
	for _, id in ipairs(seenIds or {}) do seenSet[id] = true end
	local rows, seen = {}, 0
	for _, def in ipairs(NightBoons.Definitions) do
		local isSeen = seenSet[def.id] == true
		if isSeen then seen = seen + 1 end
		rows[#rows + 1] = { id = def.id, name = def.name, icon = def.icon, line = isSeen and def.text or BoonsPage.UNSEEN_LINE, seen = isSeen }
	end
	local total = #rows
	return {
		title = BoonsPage.TITLE,
		count = seen == 0 and BoonsPage.EMPTY_LINE or ("Seen " .. seen .. " of " .. total),
		rows = rows, seen = seen, total = total,
	}
end

function BoonsPage.layout(w, h)
	local pw = math.min(BoonsPage.PANEL_MAX_W, math.floor(w * 0.94))
	local ph = math.min(BoonsPage.PANEL_MAX_H, math.floor(h * 0.92))
	local px, py = math.floor((w - pw) / 2), math.floor((h - ph) / 2)
	local r = { panel = { x = px, y = py, w = pw, h = ph } }
	r.header = { x = px + 16, y = py + 8, w = pw - 32, h = BoonsPage.HEADER_H }
	r.close = { x = px + math.floor((pw - 200) / 2), y = py + ph - BoonsPage.CLOSE_H - 10, w = 200, h = BoonsPage.CLOSE_H }
	local top = r.header.y + r.header.h + 4
	r.list = { x = px + 16, y = top, w = pw - 32, h = r.close.y - 8 - top }
	r.rowH = BoonsPage.ROW_H
	r.rowsFit = math.floor(r.list.h / BoonsPage.ROW_H) -- the rest scrolls; the last row is always reachable
	return r
end

return BoonsPage
