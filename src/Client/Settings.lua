--[[
	Client/Settings.lua
	FEATURE 10: a simple audio-only settings panel, reachable via the gear
	corner button. Scoped down to just Master Volume -- game options like
	animation speed/screenshake have no consumer code yet, so they're
	deliberately left out to keep this one piece small.

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
		makeSliderRow     -- function(parent, labelText, min, max, getValue,
		                       setValue, formatValue) -- reusable drag-slider row
		backgroundMusic   -- Sound instance, for reading/writing .Volume
		volumeButton      -- TextButton, the corner "♪/♩/×" volume-cycle button --
		                       its icon is kept roughly in sync (loud vs muted)
		                       whenever the slider is dragged, so the corner icon
		                       doesn't go stale next to this panel's real value
		VOLUME_ICONS      -- { "♪", "♩", "×" }, same table Sound.lua hands out
		popIn             -- function(backdrop, content, opts?)
		popOut            -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)

	Returns: {}

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut; the Close button gets addButtonHoverScale.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local settingsButton = deps.settingsButton
	local makeSliderRow = deps.makeSliderRow
	local backgroundMusic = deps.backgroundMusic
	local volumeButton = deps.volumeButton
	local VOLUME_ICONS = deps.VOLUME_ICONS
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale

	local settingsBackdrop = Instance.new("Frame")
	settingsBackdrop.Name = "SettingsBackdrop"
	settingsBackdrop.Size = UDim2.fromScale(1, 1)
	settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	settingsBackdrop.BackgroundTransparency = 0.4
	settingsBackdrop.Visible = false
	settingsBackdrop.ZIndex = 20
	settingsBackdrop.Parent = screenGui

	local settingsPanel = Instance.new("Frame")
	settingsPanel.Size = UDim2.fromScale(0.4, 0.3)
	settingsPanel.Position = UDim2.fromScale(0.3, 0.35)
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

	local settingsBody = Instance.new("Frame")
	settingsBody.Size = UDim2.new(1, -40, 1, -110)
	settingsBody.Position = UDim2.new(0, 20, 0, 50)
	settingsBody.BackgroundTransparency = 1
	settingsBody.ZIndex = 21
	settingsBody.Parent = settingsPanel

	-- A real click-and-drag slider (see VisualHelpers.lua's makeSliderRow) --
	-- continuous 0-100 control over the same Sound instance's Volume, in
	-- place of the old +/-10%-per-click stepper. Dragging it also nudges
	-- the corner volumeButton's icon between loud/muted so that button
	-- doesn't sit there showing a stale state right after you've just
	-- changed the volume from in here.
	local masterVolumeValue = math.floor(backgroundMusic.Volume * 100 + 0.5)

	makeSliderRow(
		settingsBody,
		"Master Volume",
		0,
		100,
		function()
			return masterVolumeValue
		end,
		function(newValue)
			masterVolumeValue = newValue
			backgroundMusic.Volume = newValue / 100
			if newValue <= 0 then
				backgroundMusic:Stop()
			elseif backgroundMusic.SoundId ~= "rbxassetid://0" and not backgroundMusic.IsPlaying then
				backgroundMusic:Play()
			end
			if volumeButton and VOLUME_ICONS then
				volumeButton.Text = (newValue <= 0) and VOLUME_ICONS[3] or VOLUME_ICONS[1]
			end
		end,
		function(value)
			return tostring(value) .. "%"
		end
	)

	local settingsCloseButton = Instance.new("TextButton")
	settingsCloseButton.Size = UDim2.new(0, 140, 0, 40)
	settingsCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
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

	settingsButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popIn(settingsBackdrop, settingsPanel)
	end)

	return {}
end
