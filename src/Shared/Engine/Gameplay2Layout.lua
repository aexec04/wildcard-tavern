--[[
	Engine/Gameplay2Layout.lua
	Gameplay v2: ONE function computes every rect of the new table screen, in pixels of a w x h screen. The client draws each
	control as the real GuiButton or Frame at its rect, so a painted rect and a click rect cannot drift apart.

	rects(w, h) -> {
	  bar, round, target, tips            the slim top bar and its three parts (bar is at most 8 percent of the height, 30 px minimum)
	  slots[1..5] = { card, label, pill } Patron seats, every seat reserved even when empty
	  stage                               the play area where played cards land and the score builds (clear of Patrons and hand)
	  hand                                the fanned hand
	  sortRank, sortSuit                  the two halves of the Rank | Suit control, side by side left of the hand
	  play, discard, playCount, discardCount   the two action buttons and their remaining-count pills
	  deck, deckCount                     the draw pile at the right and its count plate
	  traySlot1, traySlot2, trayUse, traySell, trayPrompt   the consumables tray (trayPrompt only when a third row fits)
	}
	patronRow(w, h, n) -> { cards, labels, pills }   same shape as ConceptTLayout.patronRow, for Client/PatronRow
	fits(w, h), overlaps(rects) -> list of colliding name pairs (empty when clean), ALLOWED lists intended overlaps
]]

local TierStyle = require(script.Parent:WaitForChild("PatronTierStyle"))
local Responsive = require(script.Parent:WaitForChild("ResponsiveLayout"))

local M = {}

local function round(n) return math.floor(n + 0.5) end

M.MIN_W, M.MIN_H = 720, 360 -- narrower or portrait windows keep the older play screen (eight 56 px cards do not fit under 720)
M.MIN_TOUCH = 44
M.CARD_ASPECT = 0.712 -- card width over height, the Concept T cut cards
M.SEATS = 5
M.SORT_GAP = 8
M.REF_SPAN = 0.506 -- Patron seats span (1255 - 410) / 1672 of the width in the reference mockup
M.REF_MIN_W, M.REF_MIN_H = 1200, 600 -- smaller windows keep the compact proportions (cards and the tray need the room)
M.PILL_GAP = 4 -- clear air between a count pill and the top edge of its button

local function box(x, y, w, h) return { x = round(x), y = round(y), w = round(w), h = round(h) } end

function M.fits(w, h)
	return (tonumber(w) or 0) >= M.MIN_W and (tonumber(h) or 0) >= M.MIN_H
end

-- Patron seat rects for n seats (up to 8, more than five overlap evenly inside the same span)
function M.patronRow(w, h, n)
	n = math.max(0, math.min(math.floor(tonumber(n) or M.SEATS), 8))
	local top = round(0.115 * h)
	local labelH, pillH = math.max(16, round(0.036 * h)), math.max(18, round(0.042 * h))
	local ch = round(0.205 * h)
	local cw = round(ch * M.CARD_ASPECT)
	local half = TierStyle.discBand(cw) -- the power disc hangs wholly below the card (never over its name strip), the label sits under it
	-- the reference mockup (1672 x 941) spreads the five seats over x 410 to 1255, half of the width (REF_SPAN)
	local gap = math.max(8, round(0.014 * w), (w >= M.REF_MIN_W and math.floor((M.REF_SPAN * w - M.SEATS * cw) / (M.SEATS - 1)) or 0))
	local span = M.SEATS * cw + (M.SEATS - 1) * gap
	local x0 = round((w - span) / 2)
	local out = { cards = {}, labels = {}, pills = {} }
	for i = 1, n do
		local x
		if n <= M.SEATS then x = x0 + (i - 1) * (cw + gap)
		else x = x0 + (i - 1) * (span - cw) / (n - 1) end
		out.cards[i] = box(x, top, cw, ch)
		out.labels[i] = box(x, top + ch + half + 2, cw, labelH)
		out.pills[i] = box(x, top + ch + half + 2 + labelH + 2, cw, pillH)
	end
	return out
end

-- Where a Patron's trigger pill (+4 Mult) stands, relative to the card top: 2 px under its rarity and effect rows, never above the
-- row and never over the top bar.
M.TRIGGER_PILL_H = 28
function M.triggerPillY(w, h)
	local row = M.patronRow(w, h, 1)
	return row.pills[1].y + row.pills[1].h + 2 - row.cards[1].y
end

function M.rects(w, h)
	local r = {}
	local pad = math.max(8, round(0.012 * w))
	-- top bar: round name, Target gold box, Tips pill (at most 8 percent of the height, never under 30 px)
	-- reference mockup: Target x 410 to 700, Tips ends at 1395 of 1672 (0.245 to 0.834 of the width), y 15 to 100 of 941; the height stays 7 percent so the boss banner still fits above the seats
	local ref = w >= M.REF_MIN_W and h >= M.REF_MIN_H
	local barH = math.max(30, round(0.07 * h))
	local barW = math.min(round((ref and 0.589 or 0.56) * w), w - 2 * pad)
	local barX = ref and math.min(round(0.245 * w), w - pad - barW) or round((w - barW) / 2)
	local barY = math.max(4, round(0.012 * h))
	r.bar = box(barX, barY, barW, barH)
	local inner = 6
	local ih = barH - 2 * inner
	-- Target on the left, the Night and Round name in the middle of the bar, Tips on the right
	r.target = box(barX + inner, barY + inner, round(barW * 0.31), ih)
	r.round = box(r.target.x + r.target.w + inner, barY + inner, round(barW * 0.34), ih)
	local tx = r.round.x + r.round.w + inner
	r.tips = box(tx, barY + inner, barX + barW - inner - tx, ih)
	-- the one Settings gear sits in the top right corner (Engine/GearMenu); the consumables tray starts at the top left, under Roblox's top bar
	local qy = Responsive.clearOfTopBar(pad, 0)
	r.gear = box(w - round(math.max(8, 0.012 * w)) - 44, math.max(Responsive.TOPBAR_H, round(math.max(8, 0.012 * w))), 44, M.MIN_TOUCH)
	-- Patron seats
	local row = M.patronRow(w, h, M.SEATS)
	r.slots = {}
	for i = 1, M.SEATS do r.slots[i] = { card = row.cards[i], label = row.labels[i], pill = row.pills[i] } end
	local rowBottom = row.pills[1].y + row.pills[1].h
	-- buttons: big enough to tap, side by side, centred under the hand
	-- reference mockup: buttons y 810 to 900 of 941 (0.861 to 0.956)
	local btnH = math.max(M.MIN_TOUCH, round((ref and 0.09 or 0.085) * h))
	local btnY = h - btnH - math.max(4, round(0.012 * h))
	if ref then btnY = math.min(round(0.861 * h), btnY) end
	local btnW = round(0.17 * w)
	local btnGap = math.max(10, round(0.014 * w))
	local pairW = btnW * 2 + btnGap
	local px = round((w - pairW) / 2)
	r.play = box(px, btnY, btnW, btnH)
	r.discard = box(px + btnW + btnGap, btnY, btnW, btnH)
	-- the remaining-count pills ride the top right corner of their button, fully above its top edge (PILL_GAP clear), never past the gap between buttons
	local cw = math.max(84, round(btnW * 0.5))
	local cph = math.max(22, round(btnH * 0.4))
	local ext = math.max(0, btnGap - 2)
	local cy = btnY - cph - M.PILL_GAP
	r.playCount = box(r.play.x + r.play.w - cw + ext, cy, cw, cph)
	r.discardCount = box(r.discard.x + r.discard.w - cw + ext, cy, cw, cph)
	-- hand: between the stage and the buttons
	-- short screens (under 500 px tall) start the hand higher so the cards stay at least 56 px wide (the score line shrinks instead)
	local handTop = round((h < 500 and 0.54 or 0.605) * h)
	local handH = btnY - cph - M.PILL_GAP - 6 - handTop -- the count pills hang above the buttons
	local handW = round((w < 1000 and 0.66 or 0.60) * w) -- compact windows widen the hand so eight cards stay at least 56 px wide
	r.hand = box(round((w - handW) / 2), handTop, handW, handH)
	-- stage: the open middle between the Patron row (and its pills) and the hand
	local stTop = rowBottom + 8
	local stH = math.max(24, handTop - 6 - stTop) -- the score is one quiet line, so a short stage is fine
	local stW = round(0.42 * w)
	r.stage = box(round((w - stW) / 2), stTop, stW, stH)
	-- consumables tray (Engine/Gameplay2Tray): two slots side by side at the top left, a Use and a Sell plate under them, all 44 px
	-- tall, only where they clear the hand; the prompt plate takes a third row only when it fits above the sort control, else the Use plate carries the prompt
	local trayW = math.max(0, math.min(240, row.cards[1].x - 8 - pad - pad))
	local ty = qy
	if trayW >= 2 * 60 + 8 and ty + 52 + 2 * M.MIN_TOUCH + 6 <= handTop - 4 then -- (the 52 keeps the old size cut-off: the tray used to start under Mute and Calm) -- no room above the hand on the shortest screens: no tray there
		local sw2 = math.floor((trayW - 8) / 2)
		r.traySlot1 = box(pad, ty, sw2, M.MIN_TOUCH)
		r.traySlot2 = box(pad + sw2 + 8, ty, sw2, M.MIN_TOUCH)
		r.trayUse = box(pad, ty + M.MIN_TOUCH + 6, sw2, M.MIN_TOUCH)
		r.traySell = box(pad + sw2 + 8, ty + M.MIN_TOUCH + 6, sw2, M.MIN_TOUCH)
	end
	-- sort buttons: two halves of one segmented control, left of the hand, each at least 44 px tall
	local shift = round(0.015 * w) -- a hand of eight shifts this far left (ConceptTLayout.handFor)
	-- bottom row: same baseline and height as Play Hand and Discard (reference: Rank x 25 to 185, Suit x 203 to 358 of 1672, y 815 to 895 of 941)
	local sx = round(0.015 * w)
	local sgap = math.max(M.SORT_GAP, round(0.0108 * w))
	local sw = math.max(M.MIN_TOUCH, math.min(round(0.0957 * w), math.floor((r.play.x - 2 * sx - sgap) / 2)))
	local sh = btnH
	local sy = btnY
	r.sortRank = box(sx, sy, sw, sh)
	r.sortSuit = box(sx + sw + sgap, sy, sw, sh) -- two separate plates with a gap between
	if r.trayUse then -- the prompt plate (Pick 2 cards / Suit: Hearts) when a third row fits above Rank and Suit, else the Use plate says it
		local py = r.trayUse.y + M.MIN_TOUCH + 6
		if py + M.MIN_TOUCH + 6 <= sy then r.trayPrompt = box(pad, py, r.traySell.x + r.traySell.w - pad, M.MIN_TOUCH) end
	end
	-- deck: right of the hand, count plate under it
	local dw = math.min(round(0.115 * w), w - (r.hand.x + r.hand.w) - 2 * pad)
	local dh = round(dw * 1.1)
	local dx = w - pad - dw
	local dy = handTop
	r.deck = box(dx, dy, dw, dh)
	r.deckCount = box(dx, dy + dh + 4, dw, math.max(22, round(0.04 * h)))
	return r
end

-- The deck viewer opens from the book AND its count plate: one click rect from the top of the book to the bottom of the plate.
function M.deckHit(r)
	local top, bottom = r.deck.y, r.deckCount.y + r.deckCount.h
	return { x = math.min(r.deck.x, r.deckCount.x), y = top, w = math.max(r.deck.x + r.deck.w, r.deckCount.x + r.deckCount.w) - math.min(r.deck.x, r.deckCount.x), h = bottom - top }
end

-- The TARGET CLEARED / NEW BEST banner (56 px tall, centred): the top of the stage, just under the 26 px hand preview pill, so it never
-- covers the Patron label and pill rows. Returns the banner's centre Y in px.
M.BANNER_H = 56
M.BANNER_AIR = 4 -- px under the preview pill (Gameplay2Preview.H is 26)
function M.bannerY(w, h)
	local st = M.rects(w, h).stage
	return st.y + 26 + M.BANNER_AIR + math.floor(M.BANNER_H / 2)
end

-- The centre score stack inside the stage: caption, numeral (digits about 56 px tall, so a 72 px font), a gold line directly under
-- it and the "<score> of <target>" progress text (18 px) under the line. A short stage keeps the number alone.
M.SCORE_FONT = 72
M.SCORE_FONT_MIN = 44
-- compact: while a hand is being scored the caption goes and the numeral shrinks (at most 52, at least 28) so the played cards get
-- a row of about 50 px or more under the whole block and never cover the numeral or the "of Target" line.
M.COMPACT_FONT = 52
M.COMPACT_FONT_MIN = 28
M.COMPACT_CARD_H = 44
function M.scoreStack(stageH, capH, progH, compact)
	if compact then
		-- a tall stage keeps the caption's row empty for the Patron trigger pills (they sit right under the tag rows); a short one cannot
		local top = stageH >= 150 and capH or 0
		local noProgress = stageH < 100 -- a very short stage keeps the numeral alone while a hand scores
		if noProgress then progH = 0 end
		local numH = math.max(M.COMPACT_FONT_MIN, math.min(M.COMPACT_FONT, stageH - top - progH - 10 - M.COMPACT_CARD_H))
		return { roomy = true, compact = true, noProgress = noProgress, numTop = top, numH = numH, textSize = numH, lineY = top + numH - 2, progressY = top + numH + 2, bottom = top + numH + 2 + (noProgress and 0 or 4 + progH) }
	end
	-- the whole stack (caption, numeral, line, progress) stays whenever the numeral can be at least 44 px; the font shrinks to fit
	local fixed = capH + 2 + 4 + progH + 4
	local fontFit = math.min(M.SCORE_FONT, stageH - fixed)
	local roomy = fontFit >= M.SCORE_FONT_MIN
	local numTop = roomy and capH or math.floor(stageH * 0.1)
	local textSize = roomy and fontFit or math.max(20, math.min(56, stageH - numTop - 4))
	local numH = roomy and fontFit or textSize
	return { roomy = roomy, numTop = numTop, numH = numH, textSize = textSize, lineY = numTop + numH - 2, progressY = numTop + numH + 2, bottom = numTop + numH + 2 + 4 + progH }
end

-- Where a played hand lands on the v2 table: under the centre score block (caption, numeral, line, progress) and above the hand, so
-- there is ONE scoring display and the cards never cover it. Root pixels: { top, bottom }.
M.PLAYED_GAP = 4
M.PLAYED_MIN_H = 80
function M.playedBand(r, capH, progH)
	-- the cards stand wholly under the compact score block (numeral and "of Target" line) and above the hand
	local N = M.scoreStack(r.stage.h, capH or 26, progH or 22, true)
	local bottom = r.hand.y - M.PLAYED_GAP
	return { top = r.stage.y + N.bottom + 2, bottom = bottom }
end

local function intersects(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- every named rect, flattened (the seat parts get names like card1, label1, pill1)
function M.flat(r)
	local out = {}
	for k, v in pairs(r) do
		if k == "slots" then
			for i, s in ipairs(v) do out["card" .. i] = s.card; out["label" .. i] = s.label; out["pill" .. i] = s.pill end
		elseif k ~= "bar" and v.x then
			out[k] = v
		end
	end
	out.bar = r.bar
	return out
end

-- bar parts sit inside the bar on purpose
M.ALLOWED = { ["bar|round"] = true, ["bar|target"] = true, ["bar|tips"] = true, ["play|playCount"] = true, ["discard|discardCount"] = true } -- the count pills are attached to their button

function M.overlaps(r)
	local flat = M.flat(r)
	local names = {}
	for k in pairs(flat) do names[#names + 1] = k end
	table.sort(names)
	local bad = {}
	for i = 1, #names do
		for j = i + 1, #names do
			local a, b = names[i], names[j]
			if not (M.ALLOWED[a .. "|" .. b] or M.ALLOWED[b .. "|" .. a]) and intersects(flat[a], flat[b]) then
				bad[#bad + 1] = a .. "|" .. b
			end
		end
	end
	return bad
end

-- true when every rect lies inside the w x h screen
function M.onScreen(r, w, h)
	for name, v in pairs(M.flat(r)) do
		if v.x < 0 or v.y < 0 or v.x + v.w > w or v.y + v.h > h then return false, name end
	end
	return true
end

-- the controls that must each exist exactly once (a test checks the client builds these and nothing else clickable)
M.CONTROLS = { "play", "discard", "sortRank", "sortSuit", "deck" }
M.TRAY_CONTROLS = { "traySlot1", "traySlot2", "trayUse", "traySell" } -- present whenever the screen is wide enough for the tray

-- the old deck widget (with its corner brackets) sits bottom right under the Run Over scrim: it is hidden on that screen
function M.deckWidgetShown(phase)
	return phase ~= "gameover"
end

return M
