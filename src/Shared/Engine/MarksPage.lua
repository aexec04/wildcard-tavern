--[[
	Shared/Engine/MarksPage.lua
	The Marks page of the Collection (opened by the Marks plate through Client/BoonsPage.openView): the three card Marks from Card.Marks and the four
	Legendary Patrons from Engine/Patrons, each row seen or not seen yet. A Mark is seen once the Counter has offered it in a Mark pack
	(profile.seenMarkIds, sent as state.collection.marksSeen). A Legendary Patron is seen once it is discovered (state.collection.discovered.patrons).
	Marks and Legendary Patrons are already counted by the Patrons tab, so this page adds nothing to the Collection percent.
	  MarksPage.view(markIds, patronIds) -> { title, count, rows = { { id, name, icon, line, seen, art } }, seen, total }
	  MarksPage.layout(w, h)             -> same rects as the Boons page (header, list, close), 44 px rows and Close plate
	Text is 16 px or more, rows and the Close plate are 44 px or more, every line is 60 characters or less.
]]

local Card = require(script.Parent.Card)
local Patrons = require(script.Parent.Patrons)
local BoonsPage = require(script.Parent.BoonsPage)

local MarksPage = {}

MarksPage.TITLE = "Marks and Legends"
MarksPage.UNSEEN_MARK = "Not seen yet. Marks show up at the Counter."
MarksPage.UNSEEN_LEGEND = "Not found yet. Keep playing to meet them."
MarksPage.EMPTY_LINE = "Nothing seen yet. Marks start at Night 2."
MarksPage.TEXT_SIZE = BoonsPage.TEXT_SIZE
MarksPage.ROW_H = BoonsPage.ROW_H
MarksPage.CLOSE_H = BoonsPage.CLOSE_H

local function set(ids)
	local s = {}
	for _, id in ipairs(ids or {}) do s[id] = true end
	return s
end

function MarksPage.legendaryPatrons()
	local out = {}
	for _, p in ipairs(Patrons.Definitions) do
		if p.rarity == "legendary" then out[#out + 1] = p end
	end
	return out
end

-- The three Marks first (Card.MarkOrder), then every Legendary Patron. `art` names the ContentArt category, if any.
function MarksPage.view(markIds, patronIds)
	local seenMarks, seenPatrons = set(markIds), set(patronIds)
	local rows, seen = {}, 0
	for _, id in ipairs(Card.MarkOrder) do
		local def = Card.Marks[id]
		local isSeen = seenMarks[id] == true
		if isSeen then seen = seen + 1 end
		rows[#rows + 1] = { id = "mark_" .. id, name = def.name .. " Mark", icon = def.icon, line = isSeen and def.description or MarksPage.UNSEEN_MARK, seen = isSeen }
	end
	for _, p in ipairs(MarksPage.legendaryPatrons()) do
		local isSeen = seenPatrons[p.id] == true
		if isSeen then seen = seen + 1 end
		rows[#rows + 1] = { id = p.id, name = p.name, icon = p.icon, line = isSeen and p.description or MarksPage.UNSEEN_LEGEND, seen = isSeen, art = "patrons" }
	end
	local total = #rows
	return {
		title = MarksPage.TITLE,
		count = seen == 0 and MarksPage.EMPTY_LINE or ("Seen " .. seen .. " of " .. total),
		rows = rows, seen = seen, total = total,
	}
end

MarksPage.layout = BoonsPage.layout

return MarksPage
