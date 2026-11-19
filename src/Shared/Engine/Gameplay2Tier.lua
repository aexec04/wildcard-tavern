--[[
	Engine/Gameplay2Tier.lua
	Gameplay v2: the score celebration scaled to how strong the hand was. Pure numbers, tested; Client/Gameplay2TierFX draws
	them inside the centre score block, never over the Patron rows or the hand. Presentation only: it never changes a score.

	Tier by this hand's total against the round Target:
	  0 quiet      under 1x      the count up only
	  1 pulse      1x to 2x      a gold pulse around the score block
	  2 burst      2x to 5x      a gold burst and a small shake of the number
	  3 overkill   5x and over   an OVERKILL banner and a coin shower
	A Patron combo of 3 or more triggers in one hand adds a "Combo x N" pill.
	Calm mode and Reduce motion: the number and one static label only (the tier word, or the combo word when the tier is quiet).

	tierOf(handTotal, target)          -> 0..3
	comboOf(triggers)                  -> nil, or N when N >= COMBO_MIN
	spec(tier, triggers, calm, fast)   -> { tier, label, combo, comboText, pulse, burst, shake, coins, banner, hold, static }
	labelRect(box)                     -> { x, y, w, h } the tier label, inside box (x, y, w, h), along its bottom edge
	comboRect(box)                     -> { x, y, w, h } the combo pill, inside box, along its top edge
	coinPath(i, n, box)                -> { x0, y0, x1, y1 } where coin i of n starts and lands, all inside box
]]

local M = {}

M.COMBO_MIN = 3
M.STALE = 8 -- seconds: trigger counts older than this belong to an earlier hand
M.LABELS = { [1] = "Target beaten", [2] = "Big hand", [3] = "OVERKILL" }
M.PILL_H = 24
M.PILL_W = 120

function M.tierOf(handTotal, target)
	handTotal, target = tonumber(handTotal), tonumber(target)
	if not handTotal or not target or target <= 0 then return 0 end
	local ratio = handTotal / target
	if ratio >= 5 then return 3 end
	if ratio >= 2 then return 2 end
	if ratio >= 1 then return 1 end
	return 0
end

function M.comboOf(triggers)
	triggers = math.floor(tonumber(triggers) or 0)
	if triggers >= M.COMBO_MIN then return triggers end
	return nil
end

function M.spec(tier, triggers, calm, fast)
	tier = math.max(0, math.min(3, math.floor(tonumber(tier) or 0)))
	local combo = M.comboOf(triggers)
	local comboText = combo and ("Combo x " .. combo) or nil
	if calm then
		return { tier = tier, label = M.LABELS[tier] or comboText, combo = nil, comboText = nil, pulse = 0, burst = 0, shake = 0, coins = 0,
			banner = tier == 3, hold = 1.0, static = true }
	end
	local k = fast and 0.5 or 1
	return {
		tier = tier, label = M.LABELS[tier], combo = combo, comboText = comboText, static = false,
		pulse = tier >= 1 and 0.5 * k or 0,
		burst = tier >= 2 and (tier == 3 and 16 or 10) or 0,
		shake = tier == 2 and 0.3 * k or 0, -- seconds of a small shake of the number (about 2 degrees)
		coins = tier == 3 and 14 or 0,
		banner = tier == 3,
		hold = (tier == 3 and 1.6 or 1.2) * k,
	}
end

function M.labelRect(box)
	local w = math.min(M.PILL_W + 20, box.w)
	return { x = box.x + math.floor((box.w - w) / 2), y = box.y + box.h - M.PILL_H, w = w, h = M.PILL_H }
end

function M.comboRect(box)
	local w = math.min(M.PILL_W, box.w)
	return { x = box.x + math.floor((box.w - w) / 2), y = box.y, w = w, h = M.PILL_H }
end

function M.coinPath(i, n, box)
	n = math.max(1, n)
	local f = (i - 0.5) / n
	local x = box.x + math.floor(4 + f * math.max(0, box.w - 12))
	return { x0 = x, y0 = box.y, x1 = x, y1 = box.y + box.h - 8 }
end

return M
