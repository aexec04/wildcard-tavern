--[[
	Engine/LoadingTips.lua
	Twelve short tips for the launch loading screen, in the tavern voice. Plain ASCII, no dashes, short enough
	for one line at 15 px on a phone. LoadingTips.order(seed) gives a shuffled index list (every tip once).
]]

local LoadingTips = {}

LoadingTips.MAX_LENGTH = 60

-- Twenty tips: Patron Bonds, hand levels and Recipes, the Daily twist, then the Counter and the tavern.
LoadingTips.TIPS = {
	"Patrons that share a tag form a Bond. Seat friends together.",
	"A Bond makes your Patrons work as a team.",
	"Mix tags at your table to start a new Bond.",
	"Every hand type has a level. Higher level, bigger score.",
	"Upgrade the hand you play most with a Recipe.",
	"A Recipe levels up one hand type for good.",
	"Today's Daily has a twist. Read its rule before you play.",
	"Daily runs share one seed, so everyone gets the same deal.",
	"Scout a Boss first and ban its rule once per run.",
	"Tips earn interest at the Counter. Save a few coins.",
	"Haggle once per visit. Marlo might knock a coin off.",
	"Out of hands? One More Round gives you a second wind.",
	"A free One More Round waits for you every day.",
	"Skip a Round for a Tag and take what the house offers.",
	"Card Sets change how the whole tavern looks.",
	"Flushes, straights and pairs all score. Play what you hold.",
	"Use Discards to chase a big hand, then play it.",
	"Higher stakes bring bigger rewards and tougher Bosses.",
	"Finish your daily quests for extra Tips.",
	"Claim your Daily Reward to keep your streak going.",
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
