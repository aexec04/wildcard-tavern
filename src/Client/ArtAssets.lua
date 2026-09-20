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

	cardFaceTemplate is deliberately UNUSED by any module yet, even once
	filled in -- see its own comment for why.
]]

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

	-- NOT wired into any card rendering yet on purpose. Cards change
	-- BackgroundColor3 on hover/select (see init.client.lua's rebuildHand)
	-- -- that color change is a real gameplay signal (which cards you've
	-- selected to play), not just decoration. Dropping an opaque card-face
	-- image on top of the button would hide that color change entirely.
	-- Using this properly needs the selection cue redesigned first (e.g.
	-- a colored border/glow instead of a full background-color swap) --
	-- worth doing once there's a real budget for that, not as a drive-by
	-- addition here. Left here so the id has a home the moment that
	-- redesign happens. Already uploaded (Sep 20, 2026, as
	-- "card-face-template-ace-of-spades", asset id 125245906808033) but
	-- deliberately left at the placeholder here until the selection-cue
	-- redesign above actually happens and a real call site exists to use
	-- it -- recorded in this comment so the id isn't lost in the meantime:
	-- rbxassetid://125245906808033
	cardFaceTemplate = "rbxassetid://0",
}
