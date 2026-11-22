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

-- One tip per Card Set (keyed by the CosmeticSets id), shown first when that set was the last one equipped. The classic set and any
-- unknown id have none, so the usual shuffle starts. Same rules as TIPS: plain ASCII, no dashes, 60 characters or less.
LoadingTips.SET_TIPS = {
	winter_evening = "Frosted Garden: the cards sparkle like a snowy morning.",
	festival_night = "Mountain Festival: the lanterns are lit for your next run.",
	closing_time = "Closing Time: one more hand before the lamps go low.",
	golden_gala = "Golden Gala: a grand table for a grand hand.",
	meadow_picnic = "Meadow Picnic: deal a few hands in the warm sunshine.",
	riverside_evening = "Riverside Evening: the water is calm, so take your time.",
	summit_camp = "Summit Camp: the air is crisp, so climb to Night 8.",
	dune_market = "Dune Market: the stalls are open, so spend your Tips well.",
	marsh_lanterns = "Marsh Lanterns: follow the glow to a big hand.",
	snowy_hearth = "Snowy Hearth: the fire is warm and the table is ready.",
	harbor_lights = "Harbor Lights: the boats are in and the cards are out.",
	tavern_feast = "Tavern Feast: pull up a chair, there is room for all.",
	harvest_table = "Harvest Table: a bumper crop of cards awaits.",
	winter_table = "Winter Welcome Table: come in from the cold and play.",
}

-- The tip for the last equipped set, or nil (classic, unknown or not a string).
function LoadingTips.setTip(setId)
	if type(setId) ~= "string" then return nil end
	return LoadingTips.SET_TIPS[setId]
end

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
