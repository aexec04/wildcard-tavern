--[[
	Client/Settings.lua
	The "⚙" corner button's panel. Used to also hold the whole audio
	section (Volume slider, per-SFX sliders, Custom Jukebox) -- Ahmed's
	own correction moved all of that out into Client/VolumePanel.lua,
	wired to the dedicated "🔊" volume corner button instead: "I said to
	put those sounds settings under the Music Volume Icon, and to rename
	that Music Volume Icon to just Volume." This panel is left with just
	what's actually a game setting: the way back to the Main Menu -- plus
	(CORNER ROW CLEANUP) How to Play and Leaderboards, which used to be
	their own "?" / "🏆" corner icons and now live here instead.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. The How to Play / Leaderboards buttons
	only close this panel themselves -- HowToPlay.lua/DailyLeaderboard.lua
	wire the actual "open" on them (handed in as their helpButton/
	leaderboardButton deps), so both buttons come back out of the require().

	deps fields:
		screenGui        -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel       -- function(instance, radius)
		polishButton      -- function(instance, radius)
		addSoftShadow     -- function(instance, radius)
		playClickSfx      -- function(volume?)
		settingsButton    -- TextButton, the in-game "⚙" corner button
		popIn             -- function(backdrop, content, opts?)
		popOut            -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)
		menuFrame           -- Frame, the main menu screen (see Menu.lua) -- shown
		                        by the Main Menu button below
		root                -- Frame, the in-game gameplay root -- hidden by the
		                        Main Menu button below (exact mirror of what
		                        menuPlayButton's handler does in init.client.lua,
		                        just in reverse)

	Returns:
		{
			settingsBackdrop = Frame,
			settingsHowToPlayButton = TextButton,
			settingsLeaderboardButton = TextButton,
		}

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut; the Close button gets addButtonHoverScale.

	MAIN MENU BUTTON (requested fix): before this, there was no way to get
	back to the main menu once a run started -- GameOver.lua only offers
	Play Again, and quitting meant literally leaving the game. Settings is
	reachable from both the menu screen and mid-run (it's the corner "⚙"
	button, parented straight to screenGui, not gated by root/menuFrame
	visibility), so it's the natural place for a way out. The handler is
	the exact mirror of menuPlayButton's in init.client.lua: hide root,
	show menuFrame. Nothing server-side is touched -- Phase 10's
	persistence already means whatever run was in progress just picks back
	up next time Play is pressed, same as it would after a disconnect.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local settingsButton = deps.settingsButton
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local menuFrame = deps.menuFrame
	local root = deps.root
	-- BUGFIX (overlapping overlays): see Client/OverlayManager.lua's own
	-- header comment for the full story.
	local OverlayManager = require(script.Parent.OverlayManager)
	-- CORNER ICON SET (Oct 25 2026): feeds the 2 icon images added to
	-- settingsHowToPlayButton/settingsLeaderboardButton below. Same
	-- module init.client.lua's own corner buttons read from.
	local ArtAssetsModule = require(script.Parent.ArtAssets)
	-- BUGFIX (Oct 29 2026): the How to Play/Leaderboards icon badges
	-- below were square-cornered against a rounded button -- same fix as
	-- init.client.lua's corner buttons, see makeCornerButton there for
	-- the full explanation. Pulled from deps (init.client.lua's own
	-- top-level roundCorner local, passed in alongside polishButton/
	-- polishPanel), NOT a fresh require(script.Parent.VisualHelpers)
	-- here -- that module's require() returns a FACTORY FUNCTION
	-- (return function(deps) ... end), not the helpers table, so
	-- indexing .roundCorner off it directly (an earlier version of this
	-- fix did exactly that) threw "attempt to index a function value"
	-- and aborted this file's whole require() call -- which took down
	-- init.client.lua's entire startup with it, including every button
	-- wired after this point (Play included).
	local roundCorner = deps.roundCorner

	local settingsBackdrop = Instance.new("Frame")
	settingsBackdrop.Name = "SettingsBackdrop"
	settingsBackdrop.Size = UDim2.fromScale(1, 1)
	settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	settingsBackdrop.BackgroundTransparency = 0.4
	settingsBackdrop.Visible = false
	settingsBackdrop.ZIndex = 20
	settingsBackdrop.Parent = screenGui

	local settingsPanel = Instance.new("Frame")
	-- 0.3 -> 0.4 tall (re-centered, 0.35 -> 0.3) for the How to Play /
	-- Leaderboards row added above Main Menu/Close.
	settingsPanel.Size = UDim2.fromScale(0.35, 0.4)
	settingsPanel.Position = UDim2.fromScale(0.325, 0.3)
	settingsPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	settingsPanel.ZIndex = 21
	settingsPanel.Parent = settingsBackdrop
	polishPanel(settingsPanel, 16, "wood")
	addSoftShadow(settingsPanel, 18)

	local settingsTitle = Instance.new("TextLabel")
	settingsTitle.Size = UDim2.new(1, 0, 0, 40)
	settingsTitle.BackgroundTransparency = 1
	settingsTitle.Font = Enum.Font.GothamBold
	settingsTitle.TextSize = 22
	settingsTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsTitle.Text = "Settings"
	settingsTitle.ZIndex = 21
	settingsTitle.Parent = settingsPanel

	-- How to Play + Leaderboards: same 140px-pair layout as the bottom row
	-- below, one row (40px + 10px gap) above it.
	local settingsHowToPlayButton = Instance.new("TextButton")
	settingsHowToPlayButton.Size = UDim2.new(0, 140, 0, 40)
	settingsHowToPlayButton.Position = UDim2.new(0.5, -146, 1, -110)
	settingsHowToPlayButton.Font = Enum.Font.GothamBold
	settingsHowToPlayButton.TextSize = 16
	settingsHowToPlayButton.Text = "How to Play"
	settingsHowToPlayButton.BackgroundColor3 = Color3.fromRGB(70, 45, 25)
	settingsHowToPlayButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsHowToPlayButton.ZIndex = 21
	settingsHowToPlayButton.Parent = settingsPanel
	polishButton(settingsHowToPlayButton, 12)
	addButtonHoverScale(settingsHowToPlayButton)

	-- CORNER ICON SET: a small icon badge on the left edge, text stays as
	-- the button's own Text (unlike the corner buttons in init.client.lua,
	-- these keep real words, not just an emoji, so the icon sits beside
	-- the label instead of covering it).
	if ArtAssetsModule.cornerIconHowToPlay ~= "rbxassetid://0" then
		local howToPlayIcon = Instance.new("ImageLabel")
		howToPlayIcon.Size = UDim2.new(0, 22, 0, 22)
		howToPlayIcon.AnchorPoint = Vector2.new(0, 0.5)
		howToPlayIcon.Position = UDim2.new(0, 10, 0.5, 0)
		howToPlayIcon.BackgroundTransparency = 1
		howToPlayIcon.Image = ArtAssetsModule.cornerIconHowToPlay
		howToPlayIcon.ScaleType = Enum.ScaleType.Crop
		howToPlayIcon.ZIndex = 22
		howToPlayIcon.Parent = settingsHowToPlayButton
		roundCorner(howToPlayIcon, 11)
	end

	local settingsLeaderboardButton = Instance.new("TextButton")
	settingsLeaderboardButton.Size = UDim2.new(0, 140, 0, 40)
	settingsLeaderboardButton.Position = UDim2.new(0.5, 6, 1, -110)
	settingsLeaderboardButton.Font = Enum.Font.GothamBold
	settingsLeaderboardButton.TextSize = 16
	settingsLeaderboardButton.Text = "Leaderboards"
	settingsLeaderboardButton.BackgroundColor3 = Color3.fromRGB(70, 45, 25)
	settingsLeaderboardButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsLeaderboardButton.ZIndex = 21
	settingsLeaderboardButton.Parent = settingsPanel
	polishButton(settingsLeaderboardButton, 12)
	addButtonHoverScale(settingsLeaderboardButton)

	-- CORNER ICON SET: same left-edge badge treatment as How to Play
	-- above -- replaces the old inline "🏆 " emoji that used to be part
	-- of this button's own Text string.
	if ArtAssetsModule.cornerIconLeaderboards ~= "rbxassetid://0" then
		local leaderboardIcon = Instance.new("ImageLabel")
		leaderboardIcon.Size = UDim2.new(0, 22, 0, 22)
		leaderboardIcon.AnchorPoint = Vector2.new(0, 0.5)
		leaderboardIcon.Position = UDim2.new(0, 10, 0.5, 0)
		leaderboardIcon.BackgroundTransparency = 1
		leaderboardIcon.Image = ArtAssetsModule.cornerIconLeaderboards
		leaderboardIcon.ScaleType = Enum.ScaleType.Crop
		leaderboardIcon.ZIndex = 22
		leaderboardIcon.Parent = settingsLeaderboardButton
		roundCorner(leaderboardIcon, 11)
	end

	-- Close + Main Menu sit side by side along the bottom edge -- 140px
	-- each with a 12px gap, the pair centered as a unit: [-146, -6] and
	-- [6, 146] around the panel's horizontal middle.
	local settingsMainMenuButton = Instance.new("TextButton")
	settingsMainMenuButton.Size = UDim2.new(0, 140, 0, 40)
	settingsMainMenuButton.Position = UDim2.new(0.5, -146, 1, -60)
	settingsMainMenuButton.Font = Enum.Font.GothamBold
	settingsMainMenuButton.TextSize = 16
	settingsMainMenuButton.Text = "Main Menu"
	settingsMainMenuButton.BackgroundColor3 = Color3.fromRGB(70, 45, 25)
	settingsMainMenuButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsMainMenuButton.ZIndex = 21
	settingsMainMenuButton.Parent = settingsPanel
	polishButton(settingsMainMenuButton, 12)
	addButtonHoverScale(settingsMainMenuButton)

	local settingsCloseButton = Instance.new("TextButton")
	settingsCloseButton.Size = UDim2.new(0, 140, 0, 40)
	settingsCloseButton.Position = UDim2.new(0.5, 6, 1, -60)
	settingsCloseButton.Font = Enum.Font.GothamBold
	settingsCloseButton.TextSize = 16
	settingsCloseButton.Text = "Close"
	settingsCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	settingsCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsCloseButton.ZIndex = 21
	settingsCloseButton.Parent = settingsPanel
	polishButton(settingsCloseButton, 12)
	addButtonHoverScale(settingsCloseButton)

	settingsCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel)
	end)

	-- Mirrors menuPlayButton's handler in init.client.lua in reverse: hide
	-- root, show menuFrame, only once the panel has actually finished
	-- fading out (popOut's onHidden), same as RunSetup's Begin Run handoff.
	settingsMainMenuButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel, nil, function()
			root.Visible = false
			menuFrame.Visible = true
		end)
	end)

	-- Close Settings first; the panel these open is wired by its own
	-- module (see this file's header).
	for _, button in ipairs({ settingsHowToPlayButton, settingsLeaderboardButton }) do
		button.MouseButton1Click:Connect(function()
			playClickSfx()
			popOut(settingsBackdrop, settingsPanel)
		end)
	end

	OverlayManager.register("settings", function()
		popOut(settingsBackdrop, settingsPanel)
	end)

	settingsButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("settings")
		popIn(settingsBackdrop, settingsPanel)
	end)

	return {
		settingsBackdrop = settingsBackdrop,
		settingsHowToPlayButton = settingsHowToPlayButton,
		settingsLeaderboardButton = settingsLeaderboardButton,
	}
end
