--[[
	ScoreFeel.lua
	Pure rules for how a played hand FEELS (no Roblox APIs, unit-tested). Nothing here touches scoring math: it only
	decides sizes, colors and counters the UI shows after the engine has already decided the score.

	tierFor(score, target)     -> 1..5     how big the hand was against the round Target (share: <10%, <25%, <50%, <100%, 100%+)
	popScale(tier)             -> number   how far the score popup pops at its finale
	tierColor(tier)            -> {r,g,b}  the color of the popup's hand name at that tier
	slamFor(tier)              -> number   extra screen shake for big hands (0 below tier 4)
	nextCombo(prev, score, firstHandOfRound) -> number
	                           the combo after this hand: it builds across consecutive scoring hands in a round and
	                           resets on a new round or a hand that scored nothing
	comboText(combo)           -> string|nil   "COMBO x3" from 2 up
	comboScale(combo)          -> number   flourish size, 1.0 to 1.6
	Combos are VISUAL ONLY: they never change a score, a Patron has to say so.
]]

local ScoreFeel = {}

ScoreFeel.TIER_LIMITS = { 0.10, 0.25, 0.50, 1.00 } -- share of the Target that ends tiers 1 to 4
ScoreFeel.POP = { 1.15, 1.25, 1.35, 1.5, 1.7 }
ScoreFeel.COLORS = {
	{ 250, 240, 220 }, -- cream
	{ 170, 230, 150 }, -- fresh green
	{ 255, 214, 90 }, -- gold
	{ 255, 160, 70 }, -- amber
	{ 240, 130, 255 }, -- violet: the biggest hands
}
ScoreFeel.MAX_COMBO = 99

function ScoreFeel.tierFor(score, target)
	score = tonumber(score) or 0
	if not target or target <= 0 then
		return 1
	end
	local share = score / target
	for tier, limit in ipairs(ScoreFeel.TIER_LIMITS) do
		if share < limit then
			return tier
		end
	end
	return #ScoreFeel.TIER_LIMITS + 1
end

function ScoreFeel.popScale(tier)
	return ScoreFeel.POP[math.max(1, math.min(#ScoreFeel.POP, tier or 1))]
end

function ScoreFeel.tierColor(tier)
	return ScoreFeel.COLORS[math.max(1, math.min(#ScoreFeel.COLORS, tier or 1))]
end

function ScoreFeel.slamFor(tier)
	if (tier or 1) >= 4 then
		return 4 + (tier - 4) * 3 -- 4 at tier 4, 7 at tier 5
	end
	return 0
end

function ScoreFeel.nextCombo(prev, score, firstHandOfRound)
	if (tonumber(score) or 0) <= 0 then
		return 0
	end
	local base = firstHandOfRound and 0 or (prev or 0)
	return math.min(ScoreFeel.MAX_COMBO, base + 1)
end

function ScoreFeel.comboText(combo)
	if (combo or 0) >= 2 then
		return "COMBO x" .. tostring(math.floor(combo))
	end
	return nil
end

function ScoreFeel.comboScale(combo)
	combo = math.max(0, combo or 0)
	return math.min(1.6, 1 + math.max(0, combo - 1) * 0.1)
end

return ScoreFeel
