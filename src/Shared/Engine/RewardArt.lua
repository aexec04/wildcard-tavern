-- One resolver for "what picture does this reward get?". Every reward tile (Collection Rewards, Season, Tavern Rank,
-- Quests, Login streak, Legend) asks here, so a reward kind with no painted art always has an emoji and never falls
-- back to the grey X box. Pure data: the UI looks (category, key) up in ContentArt and keeps the emoji if there is no id.
--
--   RewardArt.resolve(reward) -> category|nil, key|nil, emoji     (emoji is always a non-empty string)
--
-- Painted today: Tips (hud/coin_purse), card backs, titles, Card Set backdrops, Flair. XP, auras, trinkets and
-- nights-in-run have no painted icon yet and use their emoji.
local RewardArt = {}

local KINDS = {
	tips = { "hud", "coin_purse", "💰" },
	xp = { nil, nil, "⭐" },
	tokens = { nil, nil, "🎟️" },
	keys = { nil, nil, "🗝️" },
	aura = { nil, nil, "✨" },
	trinket = { nil, nil, "🏆" },
	nightsInRun = { nil, nil, "🌙" },
	cardBack = { "card_backs", true, "🂠" }, -- true = use reward.id as the key
	title = { "titles", true, "🏷️" },
	set = { "set_backdrops", true, "🎴" },
	flair = { "flair", true, "✨" },
}

RewardArt.Kinds = KINDS

function RewardArt.resolve(reward)
	local spec = type(reward) == "table" and KINDS[reward.kind] or nil
	if not spec then
		return nil, nil, (type(reward) == "table" and reward.icon) or "🎁"
	end
	local key = spec[2]
	if key == true then key = reward.id end
	local emoji = spec[3]
	if type(reward.icon) == "string" and reward.icon ~= "" and spec[1] == nil then emoji = reward.icon end
	if key == nil then return nil, nil, emoji end
	return spec[1], key, emoji
end

return RewardArt
