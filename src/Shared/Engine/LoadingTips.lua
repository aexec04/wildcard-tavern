--[[
	Engine/LoadingTips.lua
	Twelve short tips for the launch loading screen, in the tavern voice. Plain ASCII, no dashes, short enough
	for one line at 15 px on a phone. LoadingTips.order(seed) gives a shuffled index list (every tip once).
]]

local LoadingTips = {}

LoadingTips.MAX_LENGTH = 78

LoadingTips.TIPS = {
	"Tips earn interest at the Counter, so a few coins saved can grow.",
	"Haggle once per visit. Marlo might knock a coin off, or not.",
	"Patrons that share a tag form a Bond. Keep friends at your table.",
	"Scout a Boss before the fight and ban its rule once per run.",
	"Upgrade the hands you play most, a Recipe goes a long way.",
	"Out of hands? One More Round gives a run a second wind.",
	"A free One More Round waits for you every day.",
	"Skip a Round for a Tag, and take what the house offers.",
	"Card Sets change how the whole tavern looks. Try one on.",
	"Flushes, straights and pairs all score. Chase the hand you hold.",
	"Daily runs share one seed, so everyone plays the same deal.",
	"Higher stakes bring bigger rewards and meaner Bosses.",
}

function LoadingTips.order(seed)
	local n = #LoadingTips.TIPS
	local list = {}
	for i = 1, n do list[i] = i end
	local s = math.floor(tonumber(seed) or 1) % 2147483647
	if s <= 0 then s = 1 end
	for i = n, 2, -1 do
		s = (s * 48271) % 2147483647
		local j = (s % i) + 1
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return LoadingTips
