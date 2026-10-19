--[[
	Client/Settings.lua
	The "⚙" corner button's panel. Used to also hold the whole audio
	section (Volume slider, per-SFX sliders, Custom Jukebox) -- Ahmed's
	own correction moved all of that out into Client/VolumePanel.lua,
	wired to the dedicated "🔊" volume corner button instead: "I said to
	put those sounds settings under the Music Volume Icon, and to rename
	that Music Volume Icon to just Volume." This panel is left with just
	what's actually a game setting: the way back to the Main Menu.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Fully self-contained -- nothing outside
	this module needs anything it builds, so it returns an empty table.

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

	local settingsBackdrop = Instance.new("Frame")
	settingsBackdrop.Name = "SettingsBackdrop"
	settingsBackdrop.Size = UDim2.fromScale(1, 1)
	settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	settingsBackdrop.BackgroundTransparency = 0.4
	settingsBackdrop.Visible = false
	settingsBackdrop.ZIndex = 20
	settingsBackdrop.Parent = screenGui

	local settingsPanel = Instance.new("Frame")
	settingsPanel.Size = UDim2.fromScale(0.35, 0.3)
	settingsPanel.Position = UDim2.fromScale(0.325, 0.35)
	settingsPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	settingsPanel.ZIndex = 21
	settingsPanel.Parent = settingsBackdrop
	polishPanel(settingsPanel, 16)
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
	}
end
