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

-- Patron and Night boon pairs that work well together: a seated Patron id (or a Synergy tag) and the active boon id, with
-- one kind line of 60 characters or less. Data only; the first match in the order of the seats wins.
M.BOON_LINKS = {
	{ boon = "extra_hand", patron = "final_bow", text = "Spare Hand + Final Bow: one more last hand" },
	{ boon = "extra_discard", patron = "spare_shuffle", text = "Spare Discard + Spare Shuffle: more Mult" },
	{ boon = "extra_discard", patron = "discard_special", text = "Spare Discard feeds your Discard Patron" },
	{ boon = "wider_grip", tag = "flush", text = "Wider Grip helps your Flush Patrons" },
	{ boon = "wider_grip", tag = "straight", text = "Wider Grip helps your Straight Patrons" },
	{ boon = "pocket_change", tag = "economy", text = "Pocket Change tops up your Tips Patrons" },
	{ boon = "patron_discount", tag = "scaling", text = "Friendly Prices: grow a scaling Patron cheaper" },
	{ boon = "extra_hand", patron = "early_bird", text = "Spare Hand + Early Bird: more Hands left to cheer" },
}
-- Any boon pairs with Boon Keeper, which counts every boon you picked.
M.BOON_KEEPER_TEXT = "Boon Keeper loves every boon you pick"

-- nil, or { text, kind = "boon", a = seat }: the first seated Patron that works with the active Night boon `boonId`.
function M.boonHint(ownedIds, boonId)
	if type(boonId) ~= "string" then return nil end
	for seat, id in ipairs(ownedIds or {}) do
		if id == "boon_keeper" then return { text = M.BOON_KEEPER_TEXT, kind = "boon", a = seat, b = seat } end
		local tags
		for _, link in ipairs(M.BOON_LINKS) do
			if link.boon == boonId then
				if link.patron == id then return { text = link.text, kind = "boon", a = seat, b = seat } end
				if link.tag then
					tags = tags or PatronTips.tagsOf(id)
					for _, t in ipairs(tags) do
						if t.tag == link.tag then return { text = link.text, kind = "boon", a = seat, b = seat } end
					end
				end
			end
		end
	end
	return nil
end

-- `boonId` (optional): the active Night boon. Order: a formed set, then a Patron that works with the boon, then a pair.
function M.hint(ownedIds, boonId)
	local ids = ownedIds or {}
	local sets = SetBonuses.formed(ids)
	if sets[1] then
		local m = { sets[1].members[1], sets[1].members[2], sets[1].members[3] }
		table.sort(m)
		return { text = SetBonuses.lineOf(sets[1]), kind = "set", a = m[1], b = m[3] }
	end
	local boon = M.boonHint(ids, boonId)
	if boon then return boon end
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
