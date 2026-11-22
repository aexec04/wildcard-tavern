--[[
	Engine/Gameplay2Synergy.lua
	Gameplay v2 synergy hints, pure and tested. Client/Gameplay2SynergyFX draws them.

	  links(ownedIds)            -> list of { a, b, tag, icon, word } for every pair of NEIGHBOURING seats (a, a + 1) that share a
	                               theme tag (Synergy tags, "flat" never counts); one link per pair, the first shared tag
	  thread(rects, link)        -> { x, y, w, h, label = { x, y, w, h } or nil }  a thin gold line across the gap between the two
	                               cards at mid height; the small tag label only when the gap is at least 26 px wide (no clutter on
	                               small screens, the tooltip already names the tag)
	  completes(tags)            -> true when an offer's synergy tags (Synergy.tagsFor) include one that works with an owned Patron
	  THREAD_ALPHA               0.55 gold opacity
	  hint(ownedIds)             -> nil | { text, kind = "set" | "pair", a, b }  one short line for the chip under the Patron row: a formed set
	                               bonus ("Rare Court: x1.2 Mult") first, else the first neighbouring pair that shares a tag ("Pair: Tips Patrons team up")
	  hintRect(rects, w, h)      -> { x, y, w, h = 22, size = 16 } | nil  the chip place under the Patron row (the Boss rule plate place), nil without room
]]

local PatronTips = require(script.Parent:WaitForChild("PatronTips"))
local SetBonuses = require(script.Parent:WaitForChild("SetBonuses"))

local M = {}

M.THREAD_ALPHA = 0.55
M.THREAD_H = 3
M.THREAD_H_NARROW = 6
M.THREAD_ALPHA_NARROW = 0.9
M.LABEL_MIN_GAP = 26
M.LABEL = 22

function M.links(ownedIds)
	local out = {}
	for a = 1, math.min(#ownedIds, 7) do
		local b = a + 1
		if ownedIds[a] and ownedIds[b] then
			local mine = {}
			for _, t in ipairs(PatronTips.tagsOf(ownedIds[a])) do mine[t.tag] = t end
			for _, t in ipairs(PatronTips.tagsOf(ownedIds[b])) do
				if mine[t.tag] then
					out[#out + 1] = { a = a, b = b, tag = t.tag, icon = t.icon, word = t.word }
					break
				end
			end
		end
	end
	return out
end

function M.thread(rects, link)
	local ca, cb = rects.slots[link.a], rects.slots[link.b]
	if not ca or not cb then return nil end
	local left, right = ca.card, cb.card
	local x0 = left.x + left.w
	local gap = right.x - x0
	if gap < 6 then return nil end
	local y = left.y + math.floor(left.h / 2)
	-- a narrow gap (1280x720, phones) has no tag label, so the thread itself is thicker and brighter to stay visible
	local th = gap >= M.LABEL_MIN_GAP and M.THREAD_H or M.THREAD_H_NARROW
	local out = { x = x0, y = y - math.floor(th / 2), w = gap, h = th, alpha = gap >= M.LABEL_MIN_GAP and M.THREAD_ALPHA or M.THREAD_ALPHA_NARROW }
	if gap >= M.LABEL_MIN_GAP then
		out.label = { x = x0 + math.floor((gap - M.LABEL) / 2), y = y - math.floor(M.LABEL / 2), w = M.LABEL, h = M.LABEL }
	end
	return out
end

M.HINT_SIZE, M.HINT_H = 16, 24

function M.hint(ownedIds)
	local ids = ownedIds or {}
	local sets = SetBonuses.formed(ids)
	if sets[1] then
		local m = { sets[1].members[1], sets[1].members[2], sets[1].members[3] }
		table.sort(m)
		return { text = SetBonuses.lineOf(sets[1]), kind = "set", a = m[1], b = m[3] }
	end
	local link = M.links(ids)[1]
	if link then return { text = "Pair: " .. tostring(link.word) .. " Patrons team up", kind = "pair", a = link.a, b = link.b } end
	return nil
end

function M.hintRect(r, w, h)
	local pr = require(script.Parent:WaitForChild("Gameplay2Moments")).rulePlate(r)
	if not pr or pr.h < M.HINT_H then return nil end
	return { x = pr.x, y = pr.y, w = pr.w, h = M.HINT_H, size = M.HINT_SIZE }
end

function M.completes(tags)
	for _, t in ipairs(tags or {}) do
		if type(t.reason) == "string" and t.reason:find("^Works with") then return true end
	end
	return false
end

return M
