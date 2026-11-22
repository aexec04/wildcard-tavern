--[[
	Engine/HandLedger.lua
	Pure data and layout math for the Poker Hands ledger board (Client/PokerHandsReference.lua). No Roblox APIs.

	build(input) turns the run's hand stats into rows, weakest hand first:
	  input = { order, base, growth, handStats, handLevels, lastHand?, lifetimeHands? }
	  row   = { name, index, tier, level, leveled, chips, mult, baseChips, baseMult, played, notPlayed, points, isTop, justPlayed,
	            chipsFormula, multFormula, tip }
	  "points" is an estimate (plays x chips x mult at the current level): the run does not store points per hand.
	Strength tint runs wood -> brass -> gold -> legend (never red). layout(w, h) gives the panel, list and detail rectangles so a
	test can prove they fit and never overlap at desktop and phone sizes.
]]

local HandLedger = {}

HandLedger.TIER_COLORS = {
	wood = { 112, 84, 54 },
	brass = { 176, 134, 62 },
	gold = { 232, 188, 72 },
	legend = { 255, 226, 130 },
}

HandLedger.TIPS = {
	["High Card"] = "The fallback. Any five cards make it, so keep your best card.",
	["Pair"] = "Two cards of one rank. Cheap to make and easy to level up.",
	["Two Pair"] = "Two different pairs. A steady scorer on early Nights.",
	["Three of a Kind"] = "Three cards of one rank. The Mult jumps here.",
	["Straight"] = "Five ranks in a row. Watch for gaps and hold the middle.",
	["Flush"] = "Five cards of one suit. Keep your longest suit.",
	["Full House"] = "Three of a kind plus a pair. Big Chips and big Mult.",
	["Four of a Kind"] = "Four cards of one rank. A rare and mighty hand.",
	["Straight Flush"] = "A straight in one suit. The strongest hand in the tavern.",
}

-- Colour tier for the hand at `index` of `total` (1 is the weakest).
function HandLedger.tierFor(index, total)
	if total <= 1 then return "wood" end
	local f = (index - 1) / (total - 1)
	if f < 0.2 then return "wood" end
	if f < 0.45 then return "brass" end
	if f < 0.75 then return "gold" end
	return "legend"
end

function HandLedger.build(input)
	local order = input.order
	local total = #order
	local stats, levels = input.handStats or {}, input.handLevels or {}
	local rows = {}
	local topHand, topPoints = nil, 0
	for i, name in ipairs(order) do
		local base = input.base[name] or { chips = 0, mult = 0 }
		local growth = input.growth[name] or { chips = 0, mult = 0 }
		local level = math.floor(levels[name] or 0)
		local chips = math.floor(base.chips + growth.chips * level)
		local mult = math.floor(base.mult + growth.mult * level)
		local played = math.floor(stats[name] or 0)
		local points = played * chips * mult
		local row = {
			name = name, index = i, tier = HandLedger.tierFor(i, total),
			level = level, leveled = level > 0,
			chips = chips, mult = mult, baseChips = base.chips, baseMult = base.mult,
			played = played, notPlayed = played == 0, points = points,
			justPlayed = input.lastHand == name,
			tip = HandLedger.TIPS[name] or "",
		}
		if level > 0 then
			row.chipsFormula = string.format("Chips: %d base + %d x Lv %d = %d", base.chips, growth.chips, level, chips)
			row.multFormula = string.format("Mult: %d base + %d x Lv %d = %d", base.mult, growth.mult, level, mult)
		else
			row.chipsFormula = string.format("Chips: %d base", base.chips)
			row.multFormula = string.format("Mult: %d base", base.mult)
		end
		if points > 0 and points >= topPoints then -- ties go to the stronger hand
			topHand, topPoints = name, points
		end
		rows[i] = row
	end
	for _, row in ipairs(rows) do row.isTop = row.name == topHand end
	return { rows = rows, topHand = topHand, justPlayed = input.lastHand, lifetimeHands = math.floor(input.lifetimeHands or 0) }
end

-- Which hand the detail card shows first: the one the selected cards make, else the one just played, else the top earner, else the first.
-- Hands whose level rose since the panel was last open: prev = { [handName] = level } or nil (first open, nothing to flash).
-- Returns { [handName] = true } and the new snapshot, so the caller keeps it for the next open.
function HandLedger.levelUps(prev, rows)
	local ups, now = {}, {}
	for _, row in ipairs(rows or {}) do
		now[row.name] = row.level or 0
		if prev and (row.level or 0) > (prev[row.name] or 0) then ups[row.name] = true end
	end
	return ups, now
end

function HandLedger.defaultSelection(ledger, highlighted)
	local function has(name)
		for _, row in ipairs(ledger.rows) do
			if row.name == name then return true end
		end
		return false
	end
	if highlighted and has(highlighted) then return highlighted end
	if ledger.justPlayed and has(ledger.justPlayed) then return ledger.justPlayed end
	if ledger.topHand then return ledger.topHand end
	return ledger.rows[1] and ledger.rows[1].name or nil
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Panel, list and detail rectangles ({x, y, w, h} relative to the panel for list and detail). The list scrolls when its rows
-- do not fit; phones stack the detail under the list.
function HandLedger.layout(screenW, screenH, rowCount)
	rowCount = rowCount or 9
	local phone = screenW < 700
	local panelW = phone and (screenW - 8) or math.min(1000, math.floor(screenW * 0.92))
	local panelH = phone and (screenH - 8) or math.min(640, math.floor(screenH * 0.9))
	local top, pad = 52, 14
	local bodyH = panelH - top - pad
	local list, detail
	if phone then
		local listH = math.floor(bodyH * 0.5)
		list = { x = 8, y = top, w = panelW - 16, h = listH }
		detail = { x = 8, y = top + listH + 8, w = panelW - 16, h = bodyH - listH - 8 }
	else
		local inner = panelW - pad * 3
		local listW = math.floor(inner * 0.58)
		list = { x = pad, y = top, w = listW, h = bodyH }
		detail = { x = pad * 2 + listW, y = top, w = inner - listW, h = bodyH }
	end
	local rowH = clamp(math.floor(list.h / rowCount), phone and 40 or 44, 64)
	return { phone = phone, panel = { w = panelW, h = panelH }, list = list, detail = detail, rowH = rowH,
		scrolls = rowH * rowCount > list.h }
end

return HandLedger
