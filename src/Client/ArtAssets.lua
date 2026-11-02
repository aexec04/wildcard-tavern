--[[
	Client/ArtAssets.lua
	Single place to swap in real Roblox asset IDs for the game's art.
	Every art-consuming module reads its image from here instead of
	hardcoding one -- so plugging in a real uploaded asset id, or
	swapping a bad one out, is a ONE-LINE change in this file, never a
	hunt through the UI code.

	Everything starts at "rbxassetid://0" -- Roblox's own "no image"
	sentinel. Every call site that reads one of these already has a
	working flat-color/plain-text fallback, so leaving any of these at
	the placeholder is always safe -- never a broken or blank screen.

	HOW TO FILL THESE IN: upload the image in Roblox Studio's Toolbox
	(Create tab > Decals) or on create.roblox.com, wait for moderation to
	clear it, then take the number from the resulting asset id and write
	it in below as "rbxassetid://<that number>".

	CORRECTION (verified live in Studio, Oct 25 2026): Decal vs Image
	asset type does NOT matter for any of the UI slots below -- a
	Decal-uploaded id drops straight into an ImageLabel.Image /
	ImageButton.Image with zero errors. An earlier note here said
	"Images, not Decals" -- that was stale/wrong, left over from an older
	Studio behavior. Upload everything the same way (Toolbox > Decals).

	CARD ART HISTORY: originally a single AI-generated template, then
	swapped to Kenney's free CC0 "Playing Cards Pack" sprite sheet after
	the AI template sat in Roblox moderation a full month. Now back to a
	single AI-generated template (ChatGPT) for both face and back --
	rank/suit is rendered as text ON TOP of this by Client/init.client.lua's
	rebuildHand, not baked into unique per-card art, so there's no
	52-cell grid-accuracy risk a full AI-generated sprite sheet would
	have had.

	CORNER ICON SET + SIDEBAR TEXTURE: Ahmed's "isolate one element from
	the mockup" ChatGPT prompts, uploaded as a matching set of
	gold-emblem icons. Each one feeds exactly one corner button (or,
	for cornerIconLeaderboards / cornerIconHowToPlay, one button inside
	Settings.lua's panel) via makeCornerButton's new optional iconId
	param -- see init.client.lua's corner-button section. Same
	safe-placeholder convention as everywhere else: "rbxassetid://0"
	keeps the existing emoji/text look with no code changes needed.
	cornerIconVolume is intentionally NOT wired into the Volume button --
	that button's text already does real work (it swaps between the
	loud/mute glyphs live, see VolumePanel.lua), and a static icon image
	would sit on top and permanently hide that -- kept here for when a
	non-covering treatment (e.g. a small corner badge) is worth doing.

	RE-UPLOAD (Oct 29 2026): the first upload pass (Oct 25) for this
	whole batch -- every id below except cardFaceTemplate/cardBackTemplate,
	which were already fine -- went through some path other than Studio's
	own Toolbox (likely the Creator Dashboard's generic asset uploader),
	which produces a DIFFERENT underlying asset type than a Decal. They
	all had correct experience permissions but still failed live with
	"Asset type does not match requested type" in Studio's Output --
	a type mismatch, not a permissions or moderation problem. Confirmed
	by re-uploading just the Collection chest icon through Studio's
	Toolbox > Create > Decals instead, which worked immediately -- so
	Ahmed re-uploaded the rest of the batch the same way, all ids below
	are from that second, Decal-path upload.
]]

return {
	-- Menu.lua: the empty-tavern-room background art.
	-- "Candlelit Fantasy Tavern Interior" -- Ahmed's pick for the main
	-- game background. Fallback: Menu.lua's own flat
	-- Color3.fromRGB(18, 14, 10) panel.
	--
	-- BUGFIX (Nov 1 2026): there are TWO separate uploads of this same
	-- artwork in the project's Asset Manager -- 103951896085634 (an
	-- Image, from the Oct 29 Decal re-upload pass, despite that pass's
	-- own name) and 70705886597488 (a Decal, the ORIGINAL Oct 25 id,
	-- from before this whole re-upload saga even started). 103951896085634
	-- never rendered live and never threw an error either, same silent
	-- failure as sidebarPanelTexture's wrong-id bug just above -- but
	-- this one's id WAS right, so it isn't that. Switching to the older
	-- Decal id: it's had 6 extra days to clear moderation, it's the same
	-- Decal type as every other asset in this file that's confirmed
	-- working, and the Image type isn't actually the problem on its own
	-- (cornerIconCollection below is also an Image and renders fine) --
	-- so this is the most likely asset to actually have usable pixel
	-- data behind it. If this id doesn't render either, the two are
	-- probably both still moderation-pending and this isn't a code fix.
	-- BUGFIX (Nov 1 2026, round 2): rbxassetid://70705886597488 still
	-- failed, with Studio Output now showing the real cause explicitly --
	-- "Asset type does not match requested type". This is a documented
	-- Roblox quirk: a DECAL's own asset id (which is what 70705886597488
	-- is, confirmed in Asset Manager) can't be used directly in
	-- ImageLabel.Image/ImageButton.Image at all -- only the separate,
	-- underlying raw Image id Roblox generates alongside it works there,
	-- and that id isn't exposed anywhere in Asset Manager's UI. rbxthumb
	-- sidesteps this entirely: it renders ANY asset type (Decal
	-- included) as a thumbnail, no type-matching check. 420x420 is the
	-- largest size Roblox's rbxthumb Asset type actually supports (150
	-- or 420 square only) -- lower-res than the source art, but it
	-- renders, which rbxassetid:// flatly refused to do either way this
	-- was tried. Swap to the real Image id (pasting the Decal id into an
	-- Image property in Studio's own Properties panel auto-resolves it)
	-- for full quality whenever that's worth the trip back into Studio.
	--
	-- BUGFIX (Nov 1 2026, round 3): confirmed directly in Studio's own
	-- Properties panel -- plain "rbxassetid://70705886597488" (this
	-- exact Decal id, no rbxthumb wrapper) works fine. The "round 2"
	-- theory above (Decal ids can't be used directly in ImageLabel.Image)
	-- was wrong -- matches this file's own older correction note further
	-- up ("Decal vs Image asset type does NOT matter"). Back to the
	-- plain id for full resolution instead of rbxthumb's 420x420 cap.
	-- Nov 1 2026: was the DECAL id 70705886597488, which loads nothing from
	-- code. This is its real underlying Image id (resolved in Studio).
	menuBackground = "rbxassetid://103951896085634",

	-- Shop.lua ("The Bar"): the wooden bar backdrop art.
	-- Fallback: Shop.lua's own flat Color3.fromRGB(40, 30, 22) panel.
	shopBackground = "rbxassetid://0",

	-- GameOver.lua: shown ONLY on an actual run win, behind the "you beat
	-- the tavern" panel. Fallback: the panel's own flat brown background.
	gameOverWinBackground = "rbxassetid://0",

	-- Single reusable card-face template (AI-generated, ChatGPT) -- no
	-- rank/suit baked in on purpose; the actual rank/suit renders as
	-- text on top of this in Client/init.client.lua's rebuildHand
	-- (cardRankSuitLabel), same template image reused for all 52 cards.
	cardFaceTemplate = "rbxassetid://104840515050032",

	-- Single reusable card-back design (AI-generated, ChatGPT), shown by
	-- Client/DeckWidget.lua's deck icon.
	cardBackTemplate = "rbxassetid://109450269406536",

	-- ----- Corner button icon set (re-uploaded via Decals Oct 29 2026) -----
	-- "Carved Golden Sound Emblem" -- see the header note above on why
	-- this is NOT wired into the Volume button yet.
	cornerIconVolume = "rbxassetid://137175647407889",
	-- "Golden Artist's Palette Emblem" -- the Themes corner button.
	cornerIconThemes = "rbxassetid://101781257967904",
	-- "Golden Treasure Map Emblem" -- the Journey corner button.
	cornerIconJourney = "rbxassetid://124013213287955",
	-- "Gilded Fantasy Cookbook Emblem" -- the Hand Reference corner button.
	cornerIconHandReference = "rbxassetid://112457122557520",
	-- "Golden Gear Emblem in Ornate Frame" -- the Settings corner button.
	cornerIconSettings = "rbxassetid://137113568426955",
	-- "Treasure Chest Emblem" -- the Collection corner button. This was
	-- the test case that confirmed the Oct 25 batch's problem was an
	-- asset-type mismatch, not permissions -- see the header note above.
	cornerIconCollection = "rbxassetid://71661444926552",
	-- "Carved Golden Trophy Emblem" -- Settings.lua's Leaderboards button.
	cornerIconLeaderboards = "rbxassetid://121791278585749",
	-- "Golden Chiseled Question Mark Emblem" -- Settings.lua's How to
	-- Play button.
	cornerIconHowToPlay = "rbxassetid://85597071814587",

	-- Sidebar.lua's left-side column background texture.
	-- "Ornate Golden Wood UI Panel". Fallback: the sidebar's own flat
	-- Color3.fromRGB(40, 30, 22) panel (shows through unaffected either
	-- way -- see Sidebar.lua's own comment on how this layers in).
	--
	-- BUGFIX (Nov 1 2026): this was "rbxassetid://93271412971604" --
	-- never threw an error, never rendered, because it was never
	-- actually this asset. Confirmed directly in Studio's Asset Manager:
	-- the real "Ornate Golden Wood UI Panel" Decal (thumbnail renders
	-- fine there) is 88167989239971, a completely different id --
	-- a transcription slip from when the re-upload batch ids were first
	-- relayed, not a moderation/type/permissions problem like the rest
	-- of that batch turned out to be.
	-- BUGFIX (Nov 1 2026, round 2): same story as menuBackground above --
	-- 88167989239971 is a Decal id, which ImageLabel.Image rejects
	-- outright regardless of permissions/moderation. rbxthumb sidesteps
	-- it. See menuBackground's own comment for the full explanation and
	-- the path to full quality later.
	--
	-- BUGFIX (Nov 1 2026, round 3): same correction as menuBackground
	-- above -- plain "rbxassetid://" works fine for this Decal id too,
	-- confirmed live in Studio's Properties panel. Back to full
	-- resolution instead of rbxthumb's 420x420 cap.
	-- Nov 1 2026: real Image id behind Decal 88167989239971 (resolved in
	-- Studio). Still unused unless sidebarColumnTextureEnabled is true.
	sidebarPanelTexture = "rbxassetid://93271412971604",

	-- init.client.lua's GameRoot ("root"): the actual gameplay/round
	-- screen backdrop -- the warm tavern room (round table, candle+mug,
	-- fireplace, big arched window) behind the card hand and side panels.
	-- NEW (Nov 1 2026): this screen never had a background art slot at
	-- all before now -- root was just a flat Color3.fromRGB(24,18,14)
	-- fill, no ImageLabel behind it, unlike Menu.lua which at least had
	-- menuBackgroundArt wired up. Fallback: that same flat color, still
	-- set on root directly, so leaving this at the placeholder is safe.
	--
	-- REFERENCE-MATCH PASS (Nov 1 2026): this was still the "rbxassetid://0"
	-- placeholder, so the whole gameplay screen was a flat brown fill --
	-- the single biggest reason it looked nothing like the reference. Now
	-- reuses menuBackground's tavern-interior art (already uploaded and
	-- confirmed rendering in Studio). NOTE: do NOT upload
	-- _upload_gameplay_background_reference.png for this slot -- that file
	-- is the full mockup with the sidebar, cards and buttons painted INTO it,
	-- so every UI element would show up twice. A clean, UI-free version of
	-- that room is what belongs here; paste its id in when you have one.
	--
	-- Round 2: the plain id above showed nothing in-game. 70705886597488 is a
	-- DECAL id; pasting it into Studio's Properties panel "works" only
	-- because Studio silently swaps it for the decal's underlying IMAGE id.
	-- From code there's no swap, so it loads nothing. rbxthumb renders any
	-- asset type (420px max, a bit soft but it's a dimmed backdrop). For
	-- full resolution, replace this with the real Image id (see chat).
	--
	-- Round 3: the real Image id behind Decal 70705886597488, resolved via
	-- InsertService in Studio's Command Bar (Nov 1 2026). Full resolution.
	-- init.client.lua and Menu.lua fall back to backgroundThumbnailFallback
	-- if this ever fails to load.
	gameplayBackground = "rbxassetid://103951896085634",
	backgroundThumbnailFallback = "rbxthumb://type=Asset&id=70705886597488&w=420&h=420",

	-- Sidebar.lua: whether to stretch sidebarPanelTexture over the whole
	-- left column. Off -- see Sidebar.lua's comment where it's read.
	sidebarColumnTextureEnabled = false,

	-- UPLOAD NOTE (Nov 1 2026, learned the hard way, twice): upload art
	-- through Roblox STUDIO (Toolbox > Create, or the Asset Manager's
	-- bulk import), never the Creator Dashboard website. The first upload
	-- of every piece below came through the website: correct owner,
	-- correct permissions, Image type, shows fine on the website -- and
	-- never loads in-game (AssetFetchStatus.Failure, indefinitely). The
	-- identical files re-uploaded through Studio loaded within minutes.
	-- A Studio *Decal* upload also needs its underlying Image id (the
	-- InsertService Command Bar trick) -- a Decal id itself never loads.
	--
	-- ----- Wood/gold UI skin (Nov 1 2026, ChatGPT-isolated from the
	-- reference mockup, cleaned + sized in art-wip/ui-*.png) -----
	-- Paste each one's real IMAGE id (not the Decal id -- resolve it with
	-- the InsertService Command Bar line) in place of the 0. Each slot is
	-- safe at 0: the current code-drawn look stays until the art loads.
	-- See Client/SkinArt.lua for how they're stretched.
	plaqueFrameArt = "rbxassetid://78909562411954", -- art-wip/ui-plaque.png -> every sidebar box
	sidebarColumnArt = "rbxassetid://87414443280073", -- art-wip/ui-sidebar-column.png -> left column
	deckHolderArt = "rbxassetid://128467552796637", -- art-wip/ui-deck-holder.png -> deck widget frame
	handTrayArt = "rbxassetid://72286265498452", -- art-wip/ui-hand-tray.png -> tray behind the hand
	actionButtonArt = "rbxassetid://86901819538729", -- art-wip/ui-button.png -> Play Hand/Discard/Rank/Suit

	-- ----- Sidebar icons (art-wip/icon-*.png) -----
	coinIconArt = "rbxassetid://119446978492480", -- Image id behind Decal 125552055302909;
	crownIconArt = "rbxassetid://121545338263241", -- art-wip/icon-crown.png -> boss round name
	tipsIconArt = "rbxassetid://87928213269322", -- art-wip/icon-tips.png -> Tips
	cardsIconArt = "rbxassetid://106811414477930", -- art-wip/icon-cards.png -> Hands/Discards -- next to "Reward" in the score box
}
