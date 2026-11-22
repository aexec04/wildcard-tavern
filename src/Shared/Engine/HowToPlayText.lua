--[[
	Shared/Engine/HowToPlayText.lua
	The six rule tiles on page 1 of How to Play (Client/HowToPlay draws them). One short sentence each, in words a
	10 year old knows, and none names a screen the player has not seen yet.
]]

local HowToPlayText = {}

HowToPlayText.MAX_WORDS = 12

HowToPlayText.Tiles = {
	{ key = "select_cards", icon = "👆", title = "Pick Cards", text = "Tap up to 5 cards in your hand." },
	{ key = "play_hand", icon = "▶️", title = "Play Hand", text = "Score your best poker hand." },
	{ key = "discard", icon = "🔄", title = "Discard", text = "Swap cards you do not want without using a hand." },
	{ key = "target", icon = "🎯", title = "Hit the Target", text = "Reach the target score before your hands run out." },
	{ key = "shop", icon = "🪙", title = "Shop", text = "Clear a round, then spend Tips at The Counter." },
	{ key = "endless", icon = "🌙", title = "Keep Going", text = "Beat all 8 Nights, then play on in Endless." },
}

return HowToPlayText
