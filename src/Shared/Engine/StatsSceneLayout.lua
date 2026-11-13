--[[
	Shared/Engine/StatsSceneLayout.lua
	The painted Stats ledger desk (art `panel_scene`, key stats_room_a, 1024x1024; Client/StatsRoom.lua, used by Client/StatsPanel.lua).
	Slots were read off the PNG (art-wip/panel_scene/stats_room_slots.py draws them on debug_stats_room_a.png), in the picture's own
	pixels; geometry is in Engine/PanelSceneLayout.lua. Also the pure data for what goes in them (StatsSceneLayout.content).

	place(areaW, areaH) -> { ok, scale, image, plaques = { rect x3 }, pages = { rect x2 } (left, right), shelves = { rect x6 } }
	panel(vpX, vpY) -> { x, y, w, h } of the desk in the scene (centred in the space right of the HUD sidebar, as wide as the picture needs)
	content(stats, login, titleName, patronName) -> {
	    headline = { { value, caption } x3 },        the three brass plaques
	    rows     = { { label, value } ... },          the left page: lifetime ledger lines
	    runs     = { { text, won } ... },             the right page: newest runs (up to RUNS_SHOWN)
	    shelves  = { { title, value } x6 } }          streak, best runs, favourite Patron, Quick Run best
	rowsFit(pageH, rowH) -> how many rows fit
]]

local PS = require(script.Parent.PanelSceneLayout)
local Pages = require(script.Parent.LedgerPages)

local M = {}

M.ART_KEY = "stats_room_a"
M.DEF = {
	w = 1024, h = 1024, margin = 8, pad = 14,
	groups = {
		plaques = { { 202, 160, 174, 122 }, { 424, 160, 170, 122 }, { 647, 160, 180, 122 } },
		pages = { { 224, 372, 276, 262 }, { 540, 368, 256, 266 } },
		shelves = {
			{ 48, 810, 128, 132 }, { 208, 810, 132, 132 }, { 374, 810, 128, 132 },
			{ 534, 810, 124, 132 }, { 698, 810, 126, 132 }, { 858, 810, 122, 132 },
		},
	},
	-- smallest sizes (px) at which text stays readable (nothing under 14)
	min = { plaques = { 100, 68 }, pages = { 150, 150 }, shelves = { 76, 76 } },
}
M.TOP, M.BOTTOM = 54, 48 -- title above, footer below the body (the painting runs under the footer to the panel bottom)
M.RUNS_SHOWN = 8
M.ROW_H = 26

-- areaH is the whole height from the title strip to the panel bottom (body plus footer): the picture fills it, no flat band under the shelves
function M.place(areaW, areaH)
	local p = PS.place(M.DEF, areaW, areaH)
	p.plaques, p.pages, p.shelves = p.groups.plaques, p.groups.pages, p.groups.shelves
	return p
end

-- The desk: the picture is square, so the panel is only as wide as it needs (about 1.3 times the body height) and sits centred in the
-- space right of the HUD sidebar (Engine/LedgerPages.panelRect); the dim backdrop shows at the sides.
function M.panel(vpX, vpY)
	local r = Pages.panelRect(vpX, vpY)
	-- the whole height the tab strip allows (screen height minus 96: the strip nudges a centred panel 40 px down), so Close stays on screen
	local h = require(script.Parent.PanelLayout).expandedHeight(vpY)
	local bodyH = h - M.TOP - M.BOTTOM
	local w = math.min(r.w, math.floor(bodyH * 1.3))
	-- centred on the screen so both sides show the same backdrop, but never under the HUD sidebar
	local x = math.max(r.x, math.floor((vpX - w) / 2))
	x = math.min(x, r.x + r.w - w)
	return { x = x, y = math.floor((vpY - h) / 2), w = w, h = h }
end

-- ink goes this far in from the paper edge of a page (about 24 px on a big page, 14 on a small one) so no row starts at the very edge
function M.inset(pageW)
	return math.max(14, math.min(24, math.floor(pageW * 0.09 + 0.5)))
end

-- a page narrower than this uses the compact wording (see content)
M.COMPACT_PAGE_W = 220

-- Colours (rgb): the plaque numbers and captions are cream with a soft dark shadow (dark ink on the brass was brown on brown), the shelf
-- titles gold on the dark niche back, the frame behind header and footer dark wood like the other Tome panels.
M.COLORS = { plaqueInk = { 250, 236, 204 }, plaqueShadow = { 30, 18, 8 }, shelfTitle = { 236, 196, 112 }, shelfValue = { 250, 236, 204 },
	niche = { 28, 18, 12 }, frame = { 36, 24, 16 } }

function M.rowsFit(pageH, rowH)
	return math.max(0, math.floor(pageH / (rowH or M.ROW_H)))
end

local function whole(n)
	return math.max(0, math.floor(tonumber(n) or 0))
end

-- compact (a narrow page): "Won N8  5.0K" instead of "Won  Night 8  5000", so a row stays inside the paper
local function runLine(e, compact)
	if compact then return string.format("%s N%d  %s", e.won and "Won" or "Lost", whole(e.night), Pages.fmt(e.score)) end
	return string.format("%s  Night %d  %s", e.won and "Won" or "Lost", whole(e.night), Pages.fmt(e.score))
end
-- the same run on two short lines for a shelf slot (about 90 px wide)
local function runShelf(e)
	return string.format("%s, Night %d\n%s", e.won and "Won" or "Lost", whole(e.night), Pages.fmt(e.score))
end

-- compact = true when the pages are narrow: shorter ledger labels and run lines (the full wording is in the plain ledger book)
function M.content(stats, login, titleName, patronName, compact)
	stats = stats or {}
	local story = Pages.story(stats)
	local life = Pages.lifeLines(stats, titleName)
	local out = {
		headline = {
			{ value = Pages.fmt(story.wins), caption = "Runs won" },
			{ value = Pages.fmt(story.bestNight), caption = "Best Night" },
			{ value = Pages.fmt(stats.bestHandScore), caption = "Best hand" },
		},
		rows = {
			{ label = compact and "Runs" or "Runs started", value = Pages.fmt(story.runs) },
			{ label = "Win rate", value = string.format("%d%%", math.floor(story.winRate * 100 + 0.5)) },
			{ label = "Best Night", value = Pages.fmt(story.bestNight) },
			{ label = compact and "Hands" or life[2].label, value = life[2].value },
			{ label = compact and "Best hand" or life[3].label, value = life[3].value },
			{ label = compact and "Tips" or life[4].label, value = life[4].value },
			{ label = life[1].label, value = life[1].value },
		},
		runs = {},
		shelves = {},
	}
	local recent = stats.recent or {}
	for i = 1, math.min(M.RUNS_SHOWN, #recent) do
		out.runs[i] = { text = runLine(recent[i], compact), won = recent[i].won == true }
	end
	local streak = whole(login and login.streak)
	out.shelves[1] = { title = "Streak", value = string.format("%d day%s", streak, streak == 1 and "" or "s") }
	local bests = Pages.bests(recent, 3)
	local names = { "Best run", "2nd best", "3rd best" }
	for i = 1, 3 do
		local e = bests[i]
		out.shelves[1 + i] = { title = names[i], value = e and runShelf(e) or "None yet" }
	end
	local fav = Pages.hall(stats, titleName).favorite
	out.shelves[5] = { title = "Top Patron", value = fav and string.format("%s\n%d win%s", patronName or fav.id, fav.wins, fav.wins == 1 and "" or "s") or "None yet" }
	local q = stats.quickBest
	out.shelves[6] = { title = "Quick best", value = q and string.format("%s, Night %d", q.won and "Won" or "Lost", whole(q.night)) or "Not played" }
	return out
end

return M
