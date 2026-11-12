--[[
	Engine/RoundPayout.lua
	Splits the Tips gained on a round win into the lines the Round Complete plate shows.
	The engine pays: round reward (flat, boss double, Patron bonuses) plus interest. There is no
	"hands left" payout, so no such line is made up. Pure Lua.
]]

local RoundPayout = {}

RoundPayout.STAGGER = 0.25 -- seconds between lines

-- total: Tips gained this win (state.lastRoundReward); interest: state.lastInterest or 0.
-- Returns { lines = { {text=, total=bool}, ... }, reward = n, interest = n, total = n }.
function RoundPayout.breakdown(total, interest)
	total = math.max(0, math.floor(tonumber(total) or 0))
	interest = math.max(0, math.min(total, math.floor(tonumber(interest) or 0)))
	local reward = total - interest
	local lines = { { text = string.format("Round reward +$%d", reward) } }
	if interest > 0 then
		lines[#lines + 1] = { text = string.format("Interest +$%d", interest) }
	end
	lines[#lines + 1] = { text = string.format("Total +$%d Tips", total), total = true }
	return { lines = lines, reward = reward, interest = interest, total = total }
end

return RoundPayout
