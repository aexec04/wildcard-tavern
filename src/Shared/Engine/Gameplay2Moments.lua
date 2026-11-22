--[[
	Engine/Gameplay2Moments.lua
	Gameplay v2: the big moments on the new table, pure and tested. Client/Gameplay2MomentsFX draws them.

	  Round clear   a centred "Target cleared" plate with the final score, the tips earned and a coin count up; slides in 0.4 s,
	                holds, then fades into the Counter. It takes no clicks and never blocks the Counter. Calm mode and Reduce motion:
	                the plate simply shows for a short time, no slide, no fade, no count.
	  Boss round    the table_boss scene, a slim rule banner under the top bar (boss name in gold, rule in cream), a redder candle glow
	                (a static tint, no pulse) and the Patron row stays visible. The banner is left out when the gap under the bar is
	                too small for 14 px text (short windows): the boss name then lives in the bar's round label.
	  Defeat        "Out of hands" with the score against the target (the Run Over screen already has the green Retry, the brown
	                Main Menu and the table_runover scene).

	clearLines(prev, now)            -> { title, score, tips, tipsEarned } or nil when the round was not cleared
	clearPlate(w, h)                 -> { x, y, w, h } centred, inside the screen
	clearTiming(calm, fast)          -> { slide, hold, fade, count } seconds
	bossBanner(rects, w, h)          -> { x, y, w, h } or nil (no room)
	bossText(state)                  -> name, rule (nil, nil when not a boss round)
	bossGlow(calm)                   -> { color = {r,g,b}, transparency }
	nightLines(prev)                 -> nil | { title = "Night cleared" | "Run complete", sub, runComplete, button } (a Boss Round was cleared)
	nightPlate(w, h, runComplete)    -> { x, y, w, h } the Night plate (bigger for Run complete), inside the screen
	continueRect(plate)              -> { x, y, w, h } relative to the plate, 48 px tall
	defeatLine(state)                -> "Out of hands. Score X of Y."
	bossIcon(rules)                  -> one or two ASCII letters for the rule family (drawn on a small red shield, never a symbol glyph)
	bossEntrance(calm, fast)         -> { slide, hold, settle } seconds; slide 0 means no motion (Calm mode, Reduce motion)
	bossEntranceKey(state)           -> text that changes per boss round, so the entrance plays once per round
	bossIntro(calm, fast)            -> nil | { slide, hold, fade, dim } the boss intro cinematic (dim table, portrait plate), nil in Calm mode
	bossIntroPlate(w, h)             -> { x, y, w, h } the intro plate, inside the screen
	bossIntroPlateFor(rects, w, h)   -> the same plate placed under the Patron row (the live table uses this one)
	bossIntroParts(plate)            -> portrait rect, text rect (relative to the plate)
	nightIntroKey(state)             -> "night:round" while a non Boss round is being played, else nil (a Boss round has its own intro)
	nightIntro(calm, fast)           -> nil in Calm mode | { fadeIn, hold, fade, total, dim } seconds, 1.2 in all (0.6 on Fast)
	nightIntroLines(state, room)     -> { title = "Night 3", room, rule = "Score 1200 in 4 hands." }
	nightIntroPlate(w, h)            -> { x, y, w, h } centred a little above the middle, inside the screen
]]

local M = {}

M.MIN_BANNER_H = 18
M.MAX_BANNER_H = 28

local function floor(n) return math.floor(tonumber(n) or 0) end

-- the previous state was a round in play; the new one is not and its score reached the target
function M.clearLines(prev, now)
	if not prev or not now then return nil end
	if prev.phase ~= "playing" or now.phase == "playing" or now.phase == "gameover" then return nil end
	local target = floor(prev.targetScore)
	local score = floor(now.roundScore)
	if score < floor(prev.roundScore) then score = floor(prev.roundScore) end
	if target <= 0 or score < target then return nil end
	local earned = math.max(0, floor(now.tips) - floor(prev.tips))
	local lines = { title = "Target cleared", score = string.format("Score %d of %d", score, target), tips = string.format("Tips +%d", earned), tipsEarned = earned }
	lines.night = M.nightLines(prev)
	if now.nightStar and now.nightStar.night == floor(prev.night) then lines.star = require(script.Parent.NightStar).line(now.nightStar) end
	lines.unlockItems = now.unlockNotice and now.unlockNotice.items or nil
	lines.summary = { -- the Victory screen's numbers: only what the run really tracks
		tipsEarned = earned, unlockCount = lines.unlockItems and #lines.unlockItems or 0, score = score,
		night = floor(prev.night), cap = floor(prev.nightCap), hands = floor(now.handsPlayedTotal), tipsTotal = floor(now.tipsEarnedTotal),
		-- Run complete extras: best Night on the profile, Night boons picked and the deck at the end (cards, and how many wear a mark)
		bestNight = floor(now.profileStats and now.profileStats.bestNightReached), boons = floor(now.runCounters and now.runCounters.boonsPicked),
		deckSize = #(now.deckView or {}), marked = (function()
			local n = 0
			for _, e in ipairs(now.deckView or {}) do if e.mark then n = n + 1 end end
			return n
		end)(),
	}
	return lines
end

-- the last round of a Night (the Boss Round) was cleared: a bigger plate with a Continue button; clearing the last Night of a run is
-- "Run complete" with a crown glow. nil for an ordinary round.
function M.nightLines(prev)
	if not prev or not prev.bossModifier or floor(prev.round) < 3 then return nil end
	local night, cap = floor(prev.night), floor(prev.nightCap)
	local complete = cap > 0 and night >= cap and prev.endless ~= true
	return {
		title = complete and "Run complete" or "Night cleared",
		sub = cap > 0 and string.format("Night %d of %d", night, cap) or string.format("Night %d", night),
		runComplete = complete,
		button = "Continue",
	}
end

-- a normal Night clear is one short CornerToast line, never a plate; only Run complete (the final Night) keeps the plate
function M.nightPopup(lines)
	return lines ~= nil and lines.night ~= nil and lines.night.runComplete == true
end

function M.nightToast(lines)
	if not lines or not lines.night or lines.night.runComplete then return nil end
	local n = floor(lines.night.sub and tonumber(string.match(lines.night.sub, "%d+")) or 0)
	local tips = floor(lines.tipsEarned)
	local head = n > 0 and string.format("Night %d cleared", n) or "Night cleared"
	if tips > 0 then head = string.format("%s  +%d Tips", head, tips) end
	if lines.star then head = head .. ".  " .. lines.star end -- the best card or Patron of the Night, one kind line
	return head .. ".  Next: visit the Counter"
end

function M.nightPlate(w, h, runComplete)
	local pw = math.min(runComplete and 560 or 480, math.max(280, math.floor(w * (runComplete and 0.5 or 0.44))))
	local ph = math.min(runComplete and 300 or 260, math.max(runComplete and 262 or 214, math.floor(h * (runComplete and 0.40 or 0.36))))
	ph = math.min(ph, h - 16)
	return { x = math.floor((w - pw) / 2), y = math.max(8, math.floor((h - ph) / 2)), w = pw, h = ph }
end

-- Run complete lists what the run opened on one gold line under the Tips line; { y, h } inside the plate, 26 px tall, ending
-- at least 8 px above the Continue plate
M.UNLOCK_Y, M.UNLOCK_H = 150, 26
function M.unlockRow(plate)
	local cr = M.continueRect(plate)
	if M.UNLOCK_Y + M.UNLOCK_H + 8 > cr.y then return nil end
	return { y = M.UNLOCK_Y, h = M.UNLOCK_H }
end

-- the Continue plate sits at the bottom of the night plate (relative to it), 48 px tall, inside it
function M.continueRect(plate)
	local bw, bh = math.min(200, plate.w - 40), 48
	return { x = math.floor((plate.w - bw) / 2), y = plate.h - bh - 14, w = bw, h = bh }
end

M.NIGHT_AUTO_CLOSE = 8 -- seconds; Continue ends it sooner, and it never blocks the Counter behind it

function M.clearPlate(w, h)
	local pw = math.min(420, math.max(240, math.floor(w * 0.36)))
	local ph = math.min(150, math.max(96, math.floor(h * 0.17)))
	return { x = math.floor((w - pw) / 2), y = math.floor(h * 0.30), w = pw, h = ph }
end

function M.clearTiming(calm, fast)
	if calm then return { slide = 0, hold = 1.2, fade = 0, count = false } end
	local k = fast and 0.5 or 1
	return { slide = 0.4 * k, hold = 1.4 * k, fade = 0.4 * k, count = true }
end

function M.bossBanner(r, w, h)
	local top = r.bar.y + r.bar.h + 1
	local slotTop = r.slots[1].card.y
	local bh = math.min(M.MAX_BANNER_H, slotTop - top - 2)
	if bh < M.MIN_BANNER_H then return nil end
	local bw = r.bar.w
	return { x = r.bar.x, y = top, w = bw, h = bh }
end

-- One line rule plate for a Boss round: left of the centre in the band under the Patron row, level with the top of the stage. It never
-- covers a Patron card, label or pill (they end at the row bottom), the centred preview pill or score block (it stops 8 px short of the
-- stage), the Mute and Calm buttons or the sort control. Returns nil when there is no room (under 140 px wide or 20 px tall).
M.RULE_H = 30 -- tall enough for the parchment scroll frame around 14 px ink
function M.rulePlate(r)
	local last = r.slots[#r.slots].pill
	local rowBottom = last.y + last.h
	local pad = 8
	local x = pad
	local w = r.stage.x - 8 - x
	local y = rowBottom + 4
	local maxH = r.hand.y - y - 4
	if w < 140 or maxH < 20 then return nil end
	return { x = x, y = y, w = w, h = math.min(M.RULE_H, maxH) }
end

-- Compact sizes: when the full "Name: rule" line does not fit the plate (about 7.5 px a letter at 14 px plus the icon), the plate becomes a short chip
-- "Boss: Name" and the rule goes in the Night and Round scroll as its second line. The chip is a small box above the left rim: its height is
-- COMPACT_H, its width follows the label, and it is pulled up until no corner touches the felt ellipse.
M.COMPACT_H, M.COMPACT_SIZE, M.CHIP_CHAR_W = 22, 12, 0.6
function M.ruleFits(pr, name, rule)
	local need = #M.plateLine(name, rule) * 14 * 0.55 + M.rulePlateParts(pr).textX + 8
	return pr.w >= need
end
function M.chipLabel(name) return "Boss: " .. tostring(name or "Boss") end
-- returns { rect, compact, text, size }; nil when there is no room at all
function M.ruleChip(r, w, h, name, rule)
	local pr = M.rulePlate(r)
	if not pr then return nil end
	if M.ruleFits(pr, name, rule) then return { rect = pr, compact = false, text = M.plateLine(name, rule), size = math.max(14, math.min(18, pr.h - 6)) } end
	local size = M.COMPACT_SIZE
	local label = M.chipLabel(name)
	local ch = M.COMPACT_H
	local textX = 4 + (ch - 8) + M.ICON_GAP
	local cw = math.min(pr.w, math.ceil(#label * size * M.CHIP_CHAR_W) + textX + 8)
	local rect = { x = pr.x, y = pr.y, w = cw, h = ch }
	local f = require(script.Parent.ConceptTLayout).feltFor(w, h).rim
	local a, b, cx, cy = f.w / 2, f.h / 2, f.x + f.w / 2, f.y + f.h / 2
	local function touches(q) -- the chip's lower corners are the points nearest the felt
		for _, px in ipairs({ q.x, q.x + q.w }) do
			if ((px - cx) / a) ^ 2 + ((q.y + q.h - cy) / b) ^ 2 < 1 then return true end
		end
		return false
	end
	local guard = 0
	-- the tray (slots, Use, Sell, prompt) sits low on the left: lift the chip until it clears every tray plate by 4 px
	local function hitsTray(q)
		for _, k in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do
			local t = r[k]
			if t and q.x < t.x + t.w + 4 and t.x - 4 < q.x + q.w and q.y < t.y + t.h + 4 and t.y - 4 < q.y + q.h then return true end
		end
		return false
	end
	while (touches(rect) or hitsTray(rect)) and rect.y > 0 and guard < 400 do rect.y = rect.y - 1; guard = guard + 1 end
	return { rect = rect, compact = true, text = label, size = size }
end
-- the largest size at which `text` fits one line of a scroll plateW wide (0.58 of the size per letter, 90 percent of the width)
function M.subtitleSize(text, plateW) return math.floor(plateW * 0.9 / (math.max(1, #tostring(text)) * 0.58)) end
-- the second scroll line in compact mode: the rule alone (the chip carries the boss name)
function M.ruleSubtitle(rule, plateW)
	local line = M.plateLine("", rule):gsub("^:%s*", "")
	line = line:gsub(" this round", ""):gsub(" every hand", ""):gsub(" after every hand you play", " each hand")
	local function cap(t) return (t:gsub("^%l", string.upper)) end
	-- still too long for one line at 9 px: keep the first clause, then drop trailing words
	if plateW and M.subtitleSize(line, plateW) < 9 then
		line = line:gsub("[,(].*$", ""):gsub(" but .*$", ""):gsub(" and .*$", ""):gsub("%s+$", "")
		while M.subtitleSize(line, plateW) < 9 and line:find(" ") do line = line:gsub("%s+%S+$", "") end
	end
	return cap(line)
end

-- Inside the one rule plate: a square icon chip at the left edge and the text starting ICON_GAP px after it, so the chip never covers a letter.
M.ICON_GAP = 12
function M.rulePlateParts(pr)
	local side = math.max(12, pr.h - 8)
	local icon = { x = 4, y = math.floor((pr.h - side) / 2), w = side, h = side }
	return { icon = icon, textX = icon.x + icon.w + M.ICON_GAP }
end

-- Each Boss rule family has its own plate colour (RGB). Fill is dark, edge is the bright version.
M.TINTS = {
	fewerHands = { 150, 38, 30 }, fewerDiscards = { 150, 38, 30 }, lowHandSize = { 150, 38, 30 }, cardToss = { 150, 38, 30 }, cardCount = { 150, 38, 30 },
	suitDebuff = { 96, 52, 150 }, faceDebuff = { 96, 52, 150 }, oddRank = { 96, 52, 150 }, noRepeat = { 96, 52, 150 }, handBan = { 96, 52, 150 },
	targetBoost = { 176, 104, 28 }, weakenChips = { 176, 104, 28 }, weakenMult = { 176, 104, 28 },
	tipsDrain = { 28, 120, 92 }, patronLimit = { 28, 100, 150 }, slowStart = { 28, 100, 150 },
}

function M.bossTint(rules)
	local c = M.TINTS[rules and rules[1] or ""] or { 150, 38, 30 }
	return { fill = { math.floor(c[1] * 0.45), math.floor(c[2] * 0.45), math.floor(c[3] * 0.45) }, edge = { c[1], c[2], c[3] } }
end

-- the rule icon chip: the edge colour a little darker, so the cream glyph on it is 4.5:1 for every rule family (the orange one was 3.8:1)
function M.iconFill(rules)
	local e = M.bossTint(rules).edge
	return { math.floor(e[1] * 0.85), math.floor(e[2] * 0.85), math.floor(e[3] * 0.85) }
end

function M.bossText(state)
	if not state or not state.bossModifier or (state.round or 0) < 3 then return nil, nil end
	return state.bossModifier.name or "Boss", state.bossModifier.description or ""
end

-- The one line on the slim boss plate: "The Bouncer: one fewer card this round" (leading "Deals you" and the final full stop dropped).
function M.plateLine(name, rule)
	local r = tostring(rule or ""):gsub("^%s+", ""):gsub("%s+$", "")
	r = r:gsub("^Deals you ", ""):gsub("%.$", "")
	if r:find("^%u%l") then r = r:sub(1, 1):lower() .. r:sub(2) end
	if r == "" then return tostring(name or "Boss") end
	return tostring(name or "Boss") .. ": " .. r
end

function M.bossGlow(calm)
	-- a light red wash: over the reference felt (60, 85, 45) 0.84 turned it brown olive (74, 77, 47); at 0.94 the felt stays green
	return { color = { 150, 38, 30 }, transparency = calm and 0.97 or 0.96 } -- the boss backdrop (table_boss_ref) is already red lit with a green felt at about 70 percent, so the wash stays thin
end

-- the live boss felt read (52, 60, 40) against the normal table (60, 90, 50): this green layer (alpha 0.24) lifts it to about (54, 77, 45)
local ICONS = {
	fewerHands = "H", fewerDiscards = "D", lowHandSize = "C", cardToss = "T", cardCount = "N", suitDebuff = "S", faceDebuff = "F",
	oddRank = "O", noRepeat = "R", handBan = "B", targetBoost = "G", weakenChips = "Ch", weakenMult = "Mu", tipsDrain = "$", patronLimit = "P",
	slowStart = "Z",
}
M.ICONS = ICONS

function M.bossIcon(rules)
	local first = rules and rules[1]
	return ICONS[first] or "!"
end

function M.bossEntrance(calm, fast)
	if calm then return { slide = 0, hold = 0, settle = 0 } end
	local k = fast and 0.5 or 1
	return { slide = 0.4 * k, hold = 1.2 * k, settle = 0.4 * k }
end

-- BOSS INTRO CINEMATIC: the first time a Boss round shows, the table dims and a plate with the boss portrait, name and rule slides
-- in, holds, then fades (0.8 s of slide and hold in all, then the fade). Calm mode and Reduce motion: nothing at all (the banner and
-- the rule plate already tell the player). Fast halves every time.
M.INTRO_DIM = 0.5 -- background transparency of the dim (0.5 = half dark)
function M.bossIntro(calm, fast)
	if calm then return nil end
	local k = fast and 0.5 or 1
	return { slide = 0.3 * k, hold = 2.2 * k, fade = 0.3 * k, dim = M.INTRO_DIM } -- 2.5 s on screen, then the slim rule plate is the only boss text
end

-- the victory plate's reward line: "+12 Tips" from the Tips this win paid, nil when nothing was paid
function M.victoryReward(state)
	local n = math.floor(tonumber(state and state.lastRoundReward) or 0)
	if n <= 0 then return nil end
	return string.format("+%d Tips", n)
end

-- the intro plate, centred a little above the middle: portrait chip on the left, name over rule on the right. Root pixels.
M.INTRO_PORTRAIT = 72
function M.bossIntroPlate(w, h)
	local pw = math.min(560, w - 32)
	local ph = math.min(104, math.max(M.INTRO_PORTRAIT + 16, h - 32))
	return { x = math.floor((w - pw) / 2), y = math.floor(h * 0.36 - ph / 2), w = pw, h = ph }
end

-- With the table rects the intro plate stands BELOW the Patron row (never over the top bar, Tips chip or the seats): top 12 px under the
-- last seat pill, centred on the table, as tall as the open band allows (never taller than the plain plate). Falls back to bossIntroPlate.
function M.bossIntroPlateFor(r, w, h)
	local base = M.bossIntroPlate(w, h)
	if not r or not r.slots or not r.slots[#r.slots] then return base end
	local last = r.slots[#r.slots].pill
	local top = last.y + last.h + 12
	local room = (r.hand and r.hand.y or h) + 40 - top -- the cards of the fan start under the band; the plate may overlap their tops a little
	local ph = math.min(base.h, math.max(M.INTRO_PORTRAIT + 16, room, 100)) -- 100 px: name, two rule lines and the reward line
	if top + ph > h - 8 then ph = math.max(40, h - 8 - top) end
	return { x = base.x, y = top, w = base.w, h = ph }
end

-- inner rects, relative to the plate: the portrait chip and the text column
function M.bossIntroParts(plate)
	local side = math.min(M.INTRO_PORTRAIT, plate.h - 16)
	local portrait = { x = 12, y = math.floor((plate.h - side) / 2), w = side, h = side }
	local tx = portrait.x + side + 14
	return portrait, { x = tx, y = 10, w = plate.w - tx - 12, h = plate.h - 20 }
end

-- the name row and the rule row inside the text column ({ y, h } each): the name is up to 34 px, but gives way on a short plate so the rule
-- always keeps room for two 14 px lines (34 px) and the name for one 18 px line
function M.bossIntroRows(text)
	local nameH = math.max(22, math.min(34, text.h - 40 - M.INTRO_REWARD_H))
	local ruleY = nameH + 4
	local rewardY = text.h - M.INTRO_REWARD_H
	return { y = 0, h = nameH }, { y = ruleY, h = math.max(20, rewardY - ruleY - 2) }, { y = rewardY, h = M.INTRO_REWARD_H }
end

-- the one-line reward under the rule: "Beat it: +10 Tips" (nil when nothing is paid)
M.INTRO_REWARD_H = 18
function M.bossRewardLine(tips)
	local n = math.floor(tonumber(tips) or 0)
	if n <= 0 then return nil end
	return string.format("Beat it: +%d Tips", n)
end

function M.bossEntranceKey(state)
	if not state or not state.bossModifier then return nil end
	return string.format("%s:%s:%s", tostring(state.night or 0), tostring(state.round or 0), tostring(state.bossModifier.id or state.bossModifier.name))
end

function M.defeatLine(state)
	state = state or {}
	local score, target = floor(state.roundScore), floor(state.targetScore)
	if target > score then
		return string.format("Out of hands. Score %d of %d, %d short.", score, target, target - score)
	end
	return string.format("Out of hands. Score %d of %d.", score, target)
end

-- NIGHT INTRO: when the table opens for a round, a plate (Night N, the room, the rule in one line) shows 1.2 s over a soft dim, then
-- fades to the table; a tap skips it. Calm mode and Reduce motion: none (the round label already says the Night and Round).
M.NIGHT_INTRO_DIM = 0.55
function M.nightIntroKey(state)
	if not state or state.phase ~= "playing" or state.tutorialStage ~= nil then return nil end
	if state.bossModifier and (state.round or 0) >= 3 then return nil end
	return string.format("%d:%d", floor(state.night), floor(state.round))
end

function M.nightIntro(calm, fast)
	if calm then return nil end
	local k = fast and 0.5 or 1
	return { fadeIn = 0.2 * k, hold = 0.7 * k, fade = 0.3 * k, total = 1.2 * k, dim = M.NIGHT_INTRO_DIM }
end

function M.nightIntroLines(state, room)
	state = state or {}
	local hands = floor(state.handsRemaining)
	return {
		title = string.format("Night %d", math.max(1, floor(state.night))),
		room = tostring(room or ""),
		rule = string.format("Score %d in %d %s.", floor(state.targetScore), hands, hands == 1 and "hand" or "hands"),
	}
end

function M.nightIntroPlate(w, h)
	local pw = math.min(440, w - 32)
	local ph = math.min(132, math.max(96, h - 32))
	return { x = math.floor((w - pw) / 2), y = math.floor(h * 0.36 - ph / 2), w = pw, h = ph }
end

return M
