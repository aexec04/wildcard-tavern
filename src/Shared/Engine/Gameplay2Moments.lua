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
	defeatLine(state)                -> "Out of hands. Score X of Y."
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
	return { title = "Target cleared", score = string.format("Score %d of %d", score, target), tips = string.format("Tips +%d", earned), tipsEarned = earned }
end

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

function M.bossText(state)
	if not state or not state.bossModifier or (state.round or 0) < 3 then return nil, nil end
	return state.bossModifier.name or "Boss", state.bossModifier.description or ""
end

function M.bossGlow(calm)
	return { color = { 150, 38, 30 }, transparency = calm and 0.9 or 0.84 }
end

function M.defeatLine(state)
	state = state or {}
	return string.format("Out of hands. Score %d of %d.", floor(state.roundScore), floor(state.targetScore))
end

return M
