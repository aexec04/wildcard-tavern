--[[
	Client/ArtAssets.lua
	Single place to swap in real Roblox asset IDs for the AI-generated art
	from the "Wildcard Tavern -- Game Reference & Art Brief" doc (Part 3's
	priority prompts). Every art-consuming module reads its image from here
	instead of hardcoding one -- so plugging in a real uploaded asset id,
	or swapping a bad one out, is a ONE-LINE change in this file, never a
	hunt through the UI code.

	Everything starts at "rbxassetid://0" -- Roblox's own "no image"
	sentinel (same convention Sound.lua already uses for "no custom track
	set"). Every call site that reads one of these already has a working
	flat-color fallback (each field below says which module/screen it
	feeds and what the fallback looks like), so leaving any of these at
	the placeholder is always safe -- never a broken or blank screen.

	HOW TO FILL THESE IN: upload the image in Roblox Studio (or the
	Creator Dashboard) as a Decal/Image, wait for moderation to clear it,
	then take the number from the resulting asset id and write it in below
	as "rbxassetid://<that number>".

	SWITCH (Ahmed's report: the single AI-generated card template had sat in
	Roblox's moderation queue a full month with no sign of clearing) --
	cardFaceTemplate is gone. Replaced with cardSpriteSheet: Kenney's
	"Playing Cards Pack" (www.kenney.nl), CC0 -- free for any use, no
	attribution required, and (being a plain clip-art style asset nobody
	generated with AI) nothing that should give Roblox's moderation queue a
	reason to sit on it. It's a single packed sprite sheet image (896x256,
	14 columns x 4 rows, each card exactly 64x64px with zero padding
	between cells) covering all 52 unique card faces PLUS a card back, in
	ONE asset -- one upload, one moderation wait, instead of the 52+
	individual uploads doing this "properly" would otherwise take. Column
	order left-to-right: A,2,3,4,5,6,7,8,9,10,J,Q,K (column 13, the last
	one, is special-cased per row -- see cardSpriteBackOffset below). Row
	order top-to-bottom: Hearts, Diamonds, Clubs, Spades. cardSpriteOffset
	below turns a (rank, suit) pair from Shared/Engine/Card.lua into the
	ImageRectOffset that slices the right cell out of the sheet -- see its
	own comment, and init.client.lua's rebuildHand for the call site.
]]

local CARD_SPRITE_CELL = 64

-- Row order in the sheet, see the header comment above.
local CARD_SUIT_ROW = { Hearts = 0, Diamonds = 1, Clubs = 2, Spades = 3 }

-- rank is 2-14 (14 = Ace, see RANK_NAMES in init.client.lua) -- the sheet's
-- column order puts Ace FIRST (column 0), then 2 through K fill columns
-- 1-12 in order, so every rank except Ace lands at (rank - 1).
local function cardSpriteOffset(rank, suit)
	local col = (rank == 14) and 0 or (rank - 1)
	local row = CARD_SUIT_ROW[suit] or 0
	return Vector2.new(col * CARD_SPRITE_CELL, row * CARD_SPRITE_CELL)
end

return {
	-- Menu.lua: the empty-tavern-room background art (Part 3, prompt 3).
	-- Fallback: Menu.lua's own flat Color3.fromRGB(18, 14, 10) panel.
	-- Uploaded Sep 20, 2026 as "menu-background-empty-tavern".
	menuBackground = "rbxassetid://98136240961797",

	-- Shop.lua ("The Bar"): the wooden bar backdrop art (Part 3, prompt 4).
	-- Fallback: Shop.lua's own flat Color3.fromRGB(40, 30, 22) panel.
	-- Uploaded Sep 20, 2026 as "shop-background-the-bar".
	shopBackground = "rbxassetid://79117387321613",

	-- GameOver.lua: shown ONLY on an actual run win, behind the "you beat
	-- the tavern" panel. Fallback: the panel's own flat brown background
	-- (same as the loss state, which has no image at all).
	-- Uploaded Sep 20, 2026 as "gameover-win-celebration-scene".
	gameOverWinBackground = "rbxassetid://92026057699401",

	-- init.client.lua's hand cards, ScorePopup.lua's ghost clones of them,
	-- and DeckWidget.lua's deck icon (via cardSpriteBackOffset below).
	-- Fallback while this is "rbxassetid://0": rebuildHand's
	-- cardRankSuitLabel (plain text rank/suit, same look the game always
	-- had) stays VISIBLE whenever this is the placeholder, and auto-hides
	-- itself the moment a real sheet is wired in here -- see its own
	-- comment in init.client.lua. DeckWidget.lua's emoji card-back icon
	-- does the same. Nothing to toggle by hand either way.
	-- Uploaded Oct 18, 2026 as "card-sprite-sheet-kenney-cc0".
	cardSpriteSheet = "rbxassetid://99708970408841",

	-- Every slice into cardSpriteSheet is exactly this many pixels square.
	cardSpriteCellSize = CARD_SPRITE_CELL,

	-- DeckWidget.lua's deck icon: the sheet's one card-back cell, at column
	-- 13 (the last column) of the Diamonds row (row 1) -- see the header
	-- comment and the tilemap image itself for why that specific cell.
	cardSpriteBackOffset = Vector2.new(13 * CARD_SPRITE_CELL, 1 * CARD_SPRITE_CELL),

	-- (rank, suit) -> Vector2 ImageRectOffset into cardSpriteSheet. See its
	-- own comment above.
	cardSpriteOffset = cardSpriteOffset,
}
