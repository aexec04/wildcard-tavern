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
	min = { plaques = { 110, 76 }, pages = { 180, 170 }, shelves = { 88, 90 } },
}
M.TOP, M.BOTTOM = 54, 48 -- title above, Close below the body
M.RUNS_SHOWN = 8
M.ROW_H = 26

function M.place(areaW, areaH)
	local p = PS.place(M.DEF, areaW, areaH)
	p.plaques, p.pages, p.shelves = p.groups.plaques, p.groups.pages, p.groups.shelves
	return p
end

-- The desk: the picture is square, so the panel is only as wide as it needs (about 1.3 times the body height) and sits centred in the
-- space right of the HUD sidebar (Engine/LedgerPages.panelRect); the dim backdrop shows at the sides.
function M.panel(vpX, vpY)
	local r = Pages.panelRect(vpX, vpY)
	local h = math.max(r.h, vpY - 16) -- the scene uses the whole height: its shelves are small
	local bodyH = h - M.TOP - M.BOTTOM
	local w = math.min(r.w, math.floor(bodyH * 1.3))
	return { x = r.x + math.floor((r.w - w) / 2), y = math.floor((vpY - h) / 2), w = w, h = h }
end

function M.rowsFit(pageH, rowH)
	return math.max(0, math.floor(pageH / (rowH or M.ROW_H)))
end

local function whole(n)
	return math.max(0, math.floor(tonumber(n) or 0))
end

local function runLine(e)
	return string.format("%s  Night %d  %s", e.won and "Won" or "Lost", whole(e.night), Pages.fmt(e.score))
end
-- the same run on two short lines for a shelf slot (about 90 px wide)
local function runShelf(e)
	return string.format("%s, Night %d\n%s", e.won and "Won" or "Lost", whole(e.night), Pages.fmt(e.score))
end

function M.content(stats, login, titleName, patronName)
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
			{ label = "Runs started", value = Pages.fmt(story.runs) },
			{ label = "Win rate", value = string.format("%d%%", math.floor(story.winRate * 100 + 0.5)) },
			{ label = "Best Night", value = Pages.fmt(story.bestNight) },
			{ label = life[2].label, value = life[2].value },
			{ label = life[3].label, value = life[3].value },
			{ label = life[4].label, value = life[4].value },
			{ label = life[1].label, value = life[1].value },
		},
		runs = {},
		shelves = {},
	}
	local recent = stats.recent or {}
	for i = 1, math.min(M.RUNS_SHOWN, #recent) do
		out.runs[i] = { text = runLine(recent[i]), won = recent[i].won == true }
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
