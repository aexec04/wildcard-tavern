--[[
	Shared/Engine/BossRuleFit.lua
	Pure stacking for the Round Select boss card text block (tested). The rule text is bottom anchored just above
	the Target plaque and grows upward; the boss name and room labels sit above it. A long rule used to run up
	into the name and get cut, so the name and room labels are pushed up by however much taller than the
	designed two lines the rule really is.

	  BossRuleFit.lines(text, textSize, width) -> estimated wrapped line count (client measures with TextService)
	  BossRuleFit.height(lineCount, textSize) -> rule label height (lines plus 12 px padding)
	  BossRuleFit.extra(ruleHeight) -> px to lift the boss name and room labels (0 when the rule fits two lines)
]]

local BossRuleFit = {}

BossRuleFit.PAD = 12
BossRuleFit.LINE_FACTOR = 1.2 -- Gotham line height / text size
BossRuleFit.DESIGN_LINES = 2

function BossRuleFit.lines(text, textSize, width)
	if not text or text == "" then return 0 end
	local perLine = math.max(1, math.floor(width / (textSize * 0.52)))
	local n, cur = 1, 0
	for word in text:gmatch("%S+") do
		local w = #word
		if cur == 0 then
			cur = w
		elseif cur + 1 + w <= perLine then
			cur = cur + 1 + w
		else
			n = n + 1
			cur = w
		end
	end
	return n
end

function BossRuleFit.height(lineCount, textSize)
	return math.ceil(lineCount * textSize * BossRuleFit.LINE_FACTOR) + BossRuleFit.PAD
end

function BossRuleFit.extra(ruleHeight)
	local designed = BossRuleFit.height(BossRuleFit.DESIGN_LINES, 16)
	return math.max(0, math.ceil(ruleHeight - designed))
end

return BossRuleFit
