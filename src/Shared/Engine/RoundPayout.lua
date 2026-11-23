--[[
	Engine/RoundPayout.lua
	Splits the Tips gained on a round win into the lines the Round Complete plate shows.
	The engine pays: round reward (flat, boss double, Patron bonuses such as Savings Club) plus interest. There is no
	"hands left" payout, so no such line is made up. Every figure is in Tips (no "$" mixed with the word Tips). Pure Lua.
]]

local RoundPayout = {}

RoundPayout.STAGGER = 0.25 -- seconds between lines

-- total: Tips gained this win (state.lastRoundReward); interest: state.lastInterest or 0.
-- Returns { lines = { {text=, total=bool}, ... }, reward = n, interest = n, total = n }.
function RoundPayout.breakdown(total, interest)
	total = math.max(0, math.floor(tonumber(total) or 0))
	interest = math.max(0, math.min(total, math.floor(tonumber(interest) or 0)))
	local reward = total - interest
	local lines = { { text = string.format("Round reward +%d", reward) } }
	if interest > 0 then
		lines[#lines + 1] = { text = string.format("Interest +%d", interest) }
	end
	lines[#lines + 1] = { text = string.format("Total +%d Tips", total), total = true }
	return { lines = lines, reward = reward, interest = interest, total = total }
end

-- The Round Complete toast: ONE line "Round Complete  +4 Tips" and, when interest was paid, a small second line naming the parts.
function RoundPayout.toastLines(total, interest)
	local b = RoundPayout.breakdown(total, interest)
	local out = { main = string.format("Round Complete  +%d Tips", b.total) }
	if b.interest > 0 then
		out.sub = string.format("Round reward %d + Interest %d", b.reward, b.interest)
	end
	return out
end

-- The main line while the figure counts up to `finalTotal`: it never reads +0 when Tips were paid (the count starts at 1).
function RoundPayout.countLine(n, finalTotal)
	n = math.floor(tonumber(n) or 0)
	if (tonumber(finalTotal) or 0) >= 1 then
		n = math.max(1, n)
	end
	return RoundPayout.toastLines(n, 0).main
end

return RoundPayout
