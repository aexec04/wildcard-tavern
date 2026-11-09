--[[
	Shared/Engine/ShopkeeperLines.lua
	Short, kid-safe lines for Marlo the Peddler, shown in a speech bubble in the Counter.
	ShopkeeperLines.pick(event, seed) is deterministic: the same event and seed give the same line.
	Rules (tested): 4 or more lines per event, each 60 characters or fewer, no dashes.
]]

local ShopkeeperLines = {}

ShopkeeperLines.Events = {
	"enter", "enterFirstTime", "buy", "buyPatron", "buyPack", "reroll",
	"cantAfford", "leave", "lowTips", "richTips", "rareOffer", "soldOut",
}

ShopkeeperLines.ByEvent = {
	enter = { "Come in, come in!", "Fresh wares today!", "Mind the lantern!", "Welcome back, friend!" },
	enterFirstTime = { "Hello! I am Marlo.", "A new face! Welcome!", "Look around, friend!", "My wagon is your wagon!" },
	buy = { "A fine choice!", "Thank you kindly!", "Pleasure to serve!", "That one is a gem!" },
	buyPatron = { "A new friend for your table!", "They will love it here!", "Great pick, great pal!", "Make room, make room!" },
	buyPack = { "Open it up, quick!", "Ooh, what is inside?", "Surprises ahead!", "Rip it open!" },
	reroll = { "Fresh stock coming!", "Shake, shake, shake!", "Let me find more!", "New goods, just for you!" },
	cantAfford = { "A few more tips, friend.", "Come back with a bit more.", "Almost there!", "Save up and try again!" },
	leave = { "Safe travels!", "See you down the road!", "Come again soon!", "Good luck out there!" },
	lowTips = { "Light pockets? Browse anyway!", "Looking is free!", "Every tip counts!", "Small purse, big dreams!" },
	richTips = { "My, what a heavy purse!", "Big spender today!", "Treat yourself!", "So many tips to spend!" },
	rareOffer = { "Ooh, a rare one today!", "That shine is special!", "Do not miss this one!", "Rare finds, right here!" },
	soldOut = { "All gone, friend!", "You cleaned me out!", "Try a reroll!", "The shelf is bare!" },
}

local function hash(text)
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

function ShopkeeperLines.pick(event, seed)
	local lines = ShopkeeperLines.ByEvent[event] or ShopkeeperLines.ByEvent.enter
	return lines[(hash(tostring(seed or 0) .. "|" .. tostring(event)) % #lines) + 1]
end

return ShopkeeperLines
