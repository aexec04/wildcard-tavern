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
	lines.unlockItems = now.unlockNotice and now.unlockNotice.items or nil
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
	local top = r.bar.y + r.bar.h + 2
	local slotTop = r.slots[1].card.y
	local bh = math.min(M.MAX_BANNER_H, slotTop - top - 4)
	if bh < M.MIN_BANNER_H then return nil end
	local bw = r.bar.w
	return { x = r.bar.x, y = top, w = bw, h = bh }
end

-- One line rule plate for a Boss round: left of the centre in the band under the Patron row, level with the top of the stage. It never
-- covers a Patron card, label or pill (they end at the row bottom), the centred preview pill or score block (it stops 8 px short of the
-- stage), the Mute and Calm buttons or the sort control. Returns nil when there is no room (under 140 px wide or 20 px tall).
M.RULE_H = 24
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

function M.bossGlow(calm)
	return { color = { 150, 38, 30 }, transparency = calm and 0.9 or 0.84 }
end

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
	return { slide = 0.3 * k, hold = 0.5 * k, fade = 0.3 * k, dim = M.INTRO_DIM }
end

-- the intro plate, centred a little above the middle: portrait chip on the left, name over rule on the right. Root pixels.
M.INTRO_PORTRAIT = 72
function M.bossIntroPlate(w, h)
	local pw = math.min(560, w - 32)
	local ph = math.min(104, math.max(M.INTRO_PORTRAIT + 16, h - 32))
	return { x = math.floor((w - pw) / 2), y = math.floor(h * 0.36 - ph / 2), w = pw, h = ph }
end

-- inner rects, relative to the plate: the portrait chip and the text column
function M.bossIntroParts(plate)
	local side = math.min(M.INTRO_PORTRAIT, plate.h - 16)
	local portrait = { x = 12, y = math.floor((plate.h - side) / 2), w = side, h = side }
	local tx = portrait.x + side + 14
	return portrait, { x = tx, y = 10, w = plate.w - tx - 12, h = plate.h - 20 }
end

function M.bossEntranceKey(state)
	if not state or not state.bossModifier then return nil end
	return string.format("%s:%s:%s", tostring(state.night or 0), tostring(state.round or 0), tostring(state.bossModifier.id or state.bossModifier.name))
end

function M.defeatLine(state)
	state = state or {}
	return string.format("Out of hands. Score %d of %d.", floor(state.roundScore), floor(state.targetScore))
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
