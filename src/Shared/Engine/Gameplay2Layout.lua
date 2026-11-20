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
-- top bar words (Target: 65, Tips: 0, the scroll's two lines) grow with the plate height: reference text is about 44 px at 1672 on an 85 px plate
function M.barTextSize(plateH) return math.max(16, math.min(40, round((tonumber(plateH) or 0) * 0.5))) end
M.PILL_GAP = 4 -- clear air between a count pill and the top edge of its button

local function box(x, y, w, h) return { x = round(x), y = round(y), w = round(w), h = round(h) } end

function M.fits(w, h)
	return (tonumber(w) or 0) >= M.MIN_W and (tonumber(h) or 0) >= M.MIN_H
end

-- Patron seat rects for n seats (up to 8, more than five overlap evenly inside the same span)
function M.patronRow(w, h, n)
	n = math.max(0, math.min(math.floor(tonumber(n) or M.SEATS), 8))
	local ref = w >= M.REF_MIN_W and h >= M.REF_MIN_H
	local top = round((ref and 0.131 or 0.115) * h) -- reference: seats start at y 125 of 941, under the 100 px bar with room for the boss banner
	local labelH, pillH = math.max(16, round((ref and 0.018 or 0.036) * h)), math.max(ref and 17 or 18, round((ref and 0.019 or 0.042) * h)) -- on the reference screen slim rows keep the Score plate at its mockup height
	local ch = round((ref and 0.197 or 0.205) * h) -- the mockup seat is 205 of 941 tall (reference screens: 14 px taller than the first pass at 957)
	local cw = round(ch * M.CARD_ASPECT)
	local half = TierStyle.discBand(cw) -- the power disc hangs wholly below the card (never over its name strip), the label sits under it
	-- the reference mockup (1672 x 941) spreads the five seats over x 410 to 1255, half of the width (REF_SPAN)
	local gap = math.max(8, round(0.014 * w), (w >= M.REF_MIN_W and math.floor((M.REF_SPAN * w - M.SEATS * cw) / (M.SEATS - 1)) or 0))
	local span = M.SEATS * cw + (M.SEATS - 1) * gap
	local x0 = round((w - span) / 2)
	-- reference screens: the value bubble rows ride up onto the card's bottom edge (as in the mockup) as far as the power disc still clears the label
	local lift = ref and math.max(0, math.min(round(0.0146 * h), half - (function() local d = TierStyle.discRect(cw, ch); return d.y + d.h - ch end)())) or 0
	local out = { cards = {}, labels = {}, pills = {} }
	for i = 1, n do
		local x
		if n <= M.SEATS then x = x0 + (i - 1) * (cw + gap)
		else x = x0 + (i - 1) * (span - cw) / (n - 1) end
		out.cards[i] = box(x, top, cw, ch)
		out.labels[i] = box(x, top + ch + half - lift, cw, labelH)
		out.pills[i] = box(x, top + ch + half - lift + labelH + 2, cw, pillH)
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
	local barH = math.max(30, (ref and round(0.085 * h) or round(0.07 * h))) -- the reference screen is 8 percent so Target and Tips reach the mockup's height
	local barW = math.min(round((ref and 0.589 or 0.56) * w), w - 2 * pad)
	local barX = ref and math.min(round(0.245 * w), w - pad - barW) or round((w - barW) / 2)
	local barY = math.max(4, round((ref and 0.016 or 0.012) * h)) -- 24 px stay free under the bar for the boss banner
	r.bar = box(barX, barY, barW, barH)
	local inner = ref and 0 or 6 -- the reference plates are the whole bar height (y 15 to 100 of 941)
	local igap = ref and round(0.0102 * w) or inner -- reference: 17 px between Target and the scroll
	local ih = barH - 2 * inner
	-- Target on the left, the Night and Round name in the middle of the bar, Tips on the right
	r.target = box(barX + inner, barY + inner, round(barW * (ref and 0.2995 or 0.31)), ih)
	r.round = box(r.target.x + r.target.w + igap, barY + inner, round(barW * (ref and 0.414 or 0.34)), ih) -- the mockup scroll spans x 722 to 1130
	do -- the parchment scroll is a 3.97 : 1 picture: on a wide bar it keeps at most 1.4 times that shape, centred in its slot (never stretched into a slab)
		local maxW = round(ih * 3.97 * (ref and 1.43 or 1.4))
		if r.round.w > maxW then r.round = box(r.round.x + round((r.round.w - maxW) / 2), r.round.y, maxW, ih) end
	end
	local tx = r.round.x + r.round.w + igap
	r.tips = box(tx, barY + inner, barX + barW - inner - tx, ih)
	do -- Target and Tips are 4.2 : 1 pictures: at most 1.4 times that shape, Target hugs the left end of the bar and Tips the right
		local maxW = round(ih * 4.22 * 1.4)
		if r.target.w > maxW then r.target = box(r.target.x, r.target.y, maxW, ih) end
		if r.tips.w > maxW then r.tips = box(r.tips.x + r.tips.w - maxW, r.tips.y, maxW, ih) end
		if ref then local tw = round(barW * 0.25); r.tips = box(barX + barW - inner - tw, r.tips.y, tw, ih) end -- mockup Tips x 1150 to 1395
	end
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
	local btnW = round((ref and 0.1855 or 0.17) * w) -- mockup: Play Hand x 530 to 840, Discard x 865 to 1180
	local btnGap = math.max(10, round((ref and 0.015 or 0.014) * w))
	local pairW = btnW * 2 + btnGap
	local px = ref and round(0.317 * w) or round((w - pairW) / 2)
	r.play = box(px, btnY, btnW, btnH)
	r.discard = box(px + btnW + btnGap, btnY, btnW, btnH)
	-- the remaining-count pills ride the top right corner of their button, fully above its top edge (PILL_GAP clear), never past the gap between buttons
	local cw = math.max(84, round(btnW * (ref and 0.46 or 0.5)))
	local cph = math.max(22, round(btnH * 0.4))
	local ext = math.max(0, btnGap - 2)
	local cy = btnY - cph - M.PILL_GAP
	r.playCount = box(r.play.x + r.play.w - cw + ext, cy, cw, cph)
	r.discardCount = box(r.discard.x + r.discard.w - cw + ext, cy, cw, cph)
	if ref then -- reference: Hands x 620 to 780 and Discards x 915 to 1088 of 1672, y 773 to 808, over the buttons' middle; centres kept, width keeps the 4.7 : 1 counter shape
		local hw = math.min(round(0.102 * w), round(cph * 5.4)) -- measured: Hands 165 and Discards 177 of 1672 wide, 34 tall (about 5.4 : 1)
		local leanP, leanD = round(0.0093 * w), round(0.011 * w) -- the pills lean toward the middle of the pair (15 and 18 px at 1672)
		r.playCount = box(r.play.x + round((r.play.w - hw) / 2) + leanP, cy, hw, cph)
		r.discardCount = box(r.discard.x + round((r.discard.w - hw) / 2) - leanD, cy, hw, cph)
	end
	-- hand: between the stage and the buttons
	-- short screens (under 500 px tall) start the hand higher so the cards stay at least 56 px wide (the score line shrinks instead)
	local handTop = round((h < 500 and 0.54 or (w >= 1600 and 0.585 or 0.605)) * h)
	local handH = btnY - cph - M.PILL_GAP - 6 - handTop -- the count pills hang above the buttons
	local handW = round((w < 1000 and 0.68 or 0.67) * w) -- reference fan spans x 300 to 1410 of 1672 (0.664 wide, centre 0.511) -- compact windows widen the hand so eight cards stay at least 56 px wide
	r.hand = box(round((w - handW) / 2 + (w < 1000 and 0 or 0.011 * w)), handTop, handW, handH)
	-- stage: the open middle between the Patron row (and its pills) and the hand
	local stTop = rowBottom + (ref and 0 or 8)
	local stH = math.max(24, handTop - 6 - stTop) -- the score is one quiet line, so a short stage is fine
	local stW = round(0.42 * w)
	r.stage = box(round((w - stW) / 2), stTop, stW, stH)
	-- consumables tray (Engine/Gameplay2Tray): two slots side by side at the top left, a Use and a Sell plate under them, all 44 px
	-- tall, only where they clear the hand; the prompt plate takes a third row only when it fits above the sort control, else the Use plate carries the prompt
	local trayW = math.max(0, math.min(240, row.cards[1].x - 8 - pad - pad))
	local ty = qy + require(script.Parent:WaitForChild("GearMenu")).quickSize(w) + 8 -- one row below the Speaker and Pause buttons (Engine/GearMenu.quickRects)
	if trayW >= 2 * 60 + 8 and ty + 2 * M.MIN_TOUCH + 6 <= handTop - 4 then -- no room above the hand on the shortest screens: no tray there
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
		if py + M.MIN_TOUCH + 6 <= sy and py + M.MIN_TOUCH <= handTop - 4 then r.trayPrompt = box(pad, py, r.traySell.x + r.traySell.w - pad, M.MIN_TOUCH) end
	end
	-- deck: right of the hand, count plate under it
	local dw = math.min(round((ref and 0.1316 or 0.115) * w), w - (r.hand.x + r.hand.w) - 2 * pad)
	local dh = round(dw * 1.1)
	local dx = w - pad - dw
	local dx0 = dx -- the hand frame keeps its place for the unshifted deck
	local dy = handTop
	local deckLeft = dx0
	if ref then -- no tray: r.deck is the painted pile, 0.9 of its old size (the picture around it is clear padding),  on the felt, centred near x 0.9036 w, y 0.669 h, turned along the rim, nudged left until it is 30 px inside the felt
		local CT = require(script.Parent:WaitForChild("ConceptTLayout"))
		dw = round(dw * CT.DECK_SCALE * CT.DECK_VISIBLE); dh = round(dw * 0.98)
		dx, dy = round(0.9036 * w - dw / 2), round(0.69 * h - dh / 2)
		local HS = require(script.Parent:WaitForChild("HandSizing"))
		local fanEnd = 0 -- the right end of the widest fan (9 cards) stays 24 px clear of the pile, so the pile never slides left of this floor (or of 24 px past the hand frame's right edge)
		for n = 7, 9 do
			local fr = HS.frameFor(w, CT.handFor(r.hand, w, n), math.max(n, 8))
			fanEnd = math.max(fanEnd, fr.x + fr.w / 2 + HS.fanSpan(w, HS.cardSize(w, fr.w, fr.h, n), n) / 2)
		end
		for _ = 1, 400 do
			local pile = { x = dx, y = dy, w = dw, h = dh }
			if CT.insideFelt(pile, CT.DECK_TILT, w, h, CT.DECK_FELT_MARGIN) or dx - 1 < math.max(fanEnd, r.hand.x + r.hand.w) + 24 then break end
			dx = dx - 1
		end
		dx = math.max(dx, math.max(fanEnd, r.hand.x + r.hand.w) + 24)
		deckLeft = CT.hullOf({ x = dx, y = dy, w = dw, h = dh }, CT.DECK_TILT).x
	end
	r.deck = box(dx, dy, dw, dh)
	local over = (r.hand.x + r.hand.w) - (deckLeft - 24) -- the fan's right end stays 24 px clear of the deck: slide the hand frame left if it does not
	-- (the reference layout keeps the fan where it is and slides the pile instead)
	if over > 0 and w >= 1000 and not ref then r.hand = box(r.hand.x - over, r.hand.y, r.hand.w, r.hand.h) end
	do -- the count plate is a 3.4 : 1 picture: at most 1.4 times that shape, centred under the book
		local ch = math.max(22, round((ref and 0.046 or 0.04) * h))
		local cwid = math.min(dw, round(ch * 3.4 * 1.4))
		r.deckCount = box(dx + round((dw - cwid) / 2), dy + dh + 4, cwid, ch)
		if ref then -- reference: the count plate is the bottom right counter, x 1428 to 1648, y 833 to 900, level with the buttons
			local cwr = math.min(round(0.1316 * w), w - pad - dx)
			r.deckCount = box(math.min(round(0.854 * w), w - pad - cwr), btnY + round(0.0244 * h), cwr, round(0.0712 * h))
		end
	end
	return r
end

-- Wall banners (decorative, never in rects or flat, so no click or overlap rule counts them): two purple banners hang on the upper walls
-- beside the top bar, at the reference mockup's spots (x 285 to 380 and x 1430 to 1550 of 1672). Only on screens that use the reference layout.
-- Returns { left = box, right = box } (art aspect 594:934 and 682:977), or nil when the screen is compact.
M.BANNER_ASPECT = { left = 594 / 934, right = 682 / 977 }
function M.banners(w, h)
	if w < M.REF_MIN_W or h < M.REF_MIN_H then return nil end
	local r = M.rects(w, h)
	local y = math.max(0, round(0.012 * h) - 10) -- 10 px higher: the left banner no longer reaches the first Patron seat's shadow
	local lw, rw = round(0.0568 * w), round(0.0718 * w)
	local out = { right = box(round(0.8553 * w), y, rw, round(rw / M.BANNER_ASPECT.right)) }
	local left = box(round(0.1705 * w), y, lw, round(lw / M.BANNER_ASPECT.left))
	-- the consumables tray (top left) wins: slide the banner right of it, and leave it out when it no longer fits before the top bar
	for _, k in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do
		local t = r[k]
		if t and left.x < t.x + t.w + 8 and t.x < left.x + left.w and left.y < t.y + t.h and t.y < left.y + left.h then
			left.x = t.x + t.w + 8
		end
	end
	if left.x + left.w + 8 <= r.bar.x then out.left = left end
	return out
end

-- The deck viewer opens from the book AND its count plate: one click rect from the top of the book to the bottom of the plate.
function M.deckHit(r)
	local top, bottom = r.deck.y, r.deckCount.y + r.deckCount.h
	return { x = math.min(r.deck.x, r.deckCount.x), y = top, w = math.max(r.deck.x + r.deck.w, r.deckCount.x + r.deckCount.w) - math.min(r.deck.x, r.deckCount.x), h = bottom - top }
end

-- The TARGET CLEARED / NEW BEST banner (56 px tall, centred): the top of the stage, just under the 32 px hand preview strip, so it never
-- covers the Patron label and pill rows. Returns the banner's centre Y in px.
M.BANNER_H = 56
M.BANNER_AIR = 4 -- px under the preview pill (Gameplay2Preview.H is 32)
function M.bannerY(w, h)
	local st = M.rects(w, h).stage
	return st.y + 32 + M.BANNER_AIR + math.floor(M.BANNER_H / 2)
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
function M.scoreStack(stageH, capH, progH, compact, minFont)
	if compact then
		-- while a hand scores the plate keeps its caption row whenever the stage can hold caption plus a 28 px numeral, and drops the
		-- "of Target" line (the hand name banner and the played cards take that room); a shorter stage keeps the numeral alone, so the cards keep their row
		local top = stageH >= capH + M.COMPACT_FONT_MIN + M.COMPACT_CARD_H + 6 and capH or 0 -- and a row of cards still fits under it
		-- the "0 of Target" line stays too when the stage can still hold it with a 28 px numeral and a row of cards
		-- (the played cards stand under the hand name banner below the plate, so the line only needs room inside the plate itself)
		local prog = top > 0 and stageH >= top + M.COMPACT_FONT_MIN + progH + 4 + 4
		local extra = prog and (progH + 4) or 0
		local numH = math.max(M.COMPACT_FONT_MIN, math.min(M.COMPACT_FONT, stageH - top - 4 - extra))
		return { roomy = true, compact = true, noProgress = not prog, numTop = top, numH = numH, textSize = numH, lineY = top + numH - 2, progressY = top + numH + 2, bottom = top + numH + 2 + extra }
	end
	-- the whole stack (caption, numeral, line, progress) stays whenever the numeral can be at least 44 px; the font shrinks to fit
	local fixed = capH + 2 + 4 + progH + 4
	local fontFit = math.min(M.SCORE_FONT, stageH - fixed)
	local roomy = fontFit >= (minFont or M.SCORE_FONT_MIN) -- the idle plate passes a smaller minimum so a short stage keeps caption and progress
	local numTop = roomy and capH or math.floor(stageH * 0.1)
	local textSize = roomy and fontFit or math.max(20, math.min(56, stageH - numTop - 4))
	local numH = roomy and fontFit or textSize
	return { roomy = roomy, numTop = numTop, numH = numH, textSize = textSize, lineY = numTop + numH - 2, progressY = numTop + numH + 2, bottom = numTop + numH + 2 + 4 + progH }
end

-- Where a played hand lands on the v2 table: under the centre score block (caption, numeral, line, progress) and above the hand, so
-- there is ONE scoring display and the cards never cover it. Root pixels: { top, bottom }.
M.PLAYED_GAP = 4
M.PLAYED_MIN_H = 80
M.PLATE_PAD = 8      -- the score block stands this far inside the carved border (Gameplay2ScorePlate.PAD)
M.NAME_ROW_H = 34    -- the hand name banner row
M.SCORING_GAP = 12   -- plate to banner, banner to the played cards
M.PLAYED_GOAL_W = 90 -- played cards are at least this wide when the room allows
M.PLAYED_RATIO = 1.45-- card height over width
M.HAND_OVERLAP = 0.7 -- (kept for tests) the played row may always reach this share of the hand rect down
M.HAND_BELOW = 12    -- the played row may end this far under the hand rect (the hand has fewer cards then); keeps 1506 x 751 at 88+ px cards

-- The scoring moment, top to bottom inside and just under the stage: the Score plate (caption and counting total, same top as the idle
-- plate), 12 px, the hand name banner row, 12 px, the played cards (at least 90 wide where the room allows, reaching into the hand rect
-- when the stage is short). { plateBottom, name = { x, y, w, h } | nil, band = { top, bottom } }. A stage too short for a banner row
-- keeps the old shape: no name row, cards right under the numeral.
function M.scoringRows(r, capH)
	local pad = M.PLATE_PAD
	local N = M.scoreStack(math.max(1, r.stage.h - 2 * pad), capH or 26, 22, true)
	local content = N.noProgress and (N.numTop + N.numH) or N.bottom -- the plate holds the "of Target" line too when it fits
	local plateBottom = r.stage.y + math.min(r.stage.h, math.max(40, content + 2 * pad))
	local nameY = plateBottom + M.SCORING_GAP
	local top = nameY + M.NAME_ROW_H + M.SCORING_GAP
	local bottom = math.max(r.hand.y - M.PLAYED_GAP, math.min(top + M.PLAYED_GOAL_W * M.PLAYED_RATIO, r.hand.y + r.hand.h + M.HAND_BELOW))
	for _, key in ipairs({ "playCount", "discardCount" }) do -- the Hands and Discards pills stand under the hand: the row stops 4 px above them
		local pill = r[key]
		if pill and pill.y - 4 < bottom and pill.y - 4 - top >= 44 then bottom = pill.y - 4 end
	end
	if bottom - top >= 44 then
		return { plateBottom = plateBottom, name = { x = r.stage.x, y = nameY, w = r.stage.w, h = M.NAME_ROW_H }, band = { top = top, bottom = bottom } }
	end
	local N0 = M.scoreStack(r.stage.h, capH or 26, 22, true)
	return { plateBottom = plateBottom, name = nil, band = { top = r.stage.y + N0.bottom + 2, bottom = r.hand.y - M.PLAYED_GAP } }
end

-- how far a picked card rises: the wanted lift, cut so its top stays 4 px under the idle Score plate (never under the hover lift of 10)
M.LIFT_CLEAR = 4
function M.selectedLift(r, want, capH)
	return want or 28 -- always the full lift so a pick reads on screen; the card draws above the idle plate (Z raised on pick)
end

-- per card cap: a picked card keeps its top at least PROGRESS_CLEAR px under the bottom of the "N of Target" line
-- (lift = min(want, restTop - (progressBottom + PROGRESS_CLEAR))), never negative; nil inputs keep the wanted lift
M.PROGRESS_CLEAR = 10
function M.capLift(want, restTop, progressBottom)
	want = want or 28
	if not (restTop and progressBottom) then return want end
	return math.max(0, math.min(want, restTop - (progressBottom + M.PROGRESS_CLEAR)))
end

function M.playedBand(r, capH, progH)
	return M.scoringRows(r, capH).band
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

-- the Rank and Suit gold frames, icons and words belong to the table only: never on the Counter, Round Select or the Menu
function M.sortChromeShown(active)
	return active == true
end

return M
