--[[
	Client/VolumePanel.lua
	The corner volume button's small popup: a Music slider, an SFX slider
	and a Mute toggle, nothing else. Values live in Client/ClientSettings.lua
	(saved to the player's profile); Sound.lua applies them.

	The corner button shows VOLUME_ICONS[3] ("×") while muted or with the
	music at 0, VOLUME_ICONS[1] ("♪") otherwise.

	deps fields:
		screenGui, polishPanel, polishButton, addSoftShadow, playClickSfx
		volumeButton        -- TextButton, the corner button; this module wires its click
		makeSliderRow       -- see VisualHelpers.lua
		VOLUME_ICONS        -- see Sound.lua
		popIn, popOut, addButtonHoverScale

	Returns:
		{ volumeBackdrop = Frame }
]]

local ClientSettings = require(script.Parent.ClientSettings)
local OverlayManager = require(script.Parent.OverlayManager)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Detents = require(Engine:WaitForChild("VolumeDetents"))
local PlayerProfile = require(Engine:WaitForChild("PlayerProfile"))

return function(deps)
	local polishButton = deps.polishButton
	local playClickSfx = deps.playClickSfx
	local volumeButton = deps.volumeButton
	local VOLUME_ICONS = deps.VOLUME_ICONS
	local popIn = deps.popIn
	local popOut = deps.popOut

	local volumeBackdrop = Instance.new("Frame")
	volumeBackdrop.Name = "VolumeBackdrop"
	volumeBackdrop.Size = UDim2.fromScale(1, 1)
	volumeBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	volumeBackdrop.BackgroundTransparency = 0.4
	volumeBackdrop.Visible = false
	volumeBackdrop.ZIndex = 20
	volumeBackdrop.Parent = deps.screenGui
	require(script.Parent.MenuTitleHider).bind(deps.screenGui, volumeBackdrop)

	local volumePanel = Instance.new("Frame")
	local AudioRows = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("AudioRows"))
	local audioCam = workspace.CurrentCamera
	local audioView = audioCam and audioCam.ViewportSize or Vector2.new(1280, 720)
	local audioLayout = AudioRows.layout(audioView.X, audioView.Y)
	volumePanel.Size = UDim2.new(0, audioLayout.panel.w, 0, audioLayout.panel.h)
	volumePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	volumePanel.Position = UDim2.fromScale(0.5, 0.5)
	volumePanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	volumePanel.ZIndex = 21
	volumePanel.Parent = volumeBackdrop
	deps.polishPanel(volumePanel, 16, "wood")
	-- Painted background (PanelArt): flat panel color if the art id is missing.
	local volumePanelArt = require(script.Parent.PanelArt).add(volumePanel, {
		key = "settings_bg", scrim = { position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 1) },
		scrimTransparency = 0.35,
	})
	deps.addSoftShadow(volumePanel, 18)

	local volumeTitle = Instance.new("TextLabel")
	volumeTitle.Size = UDim2.new(1, 0, 0, 40)
	volumeTitle.BackgroundTransparency = 1
	volumeTitle.Font = Enum.Font.GothamBold
	volumeTitle.TextSize = 22
	volumeTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	volumeTitle.Text = "Volume"
	volumeTitle.ZIndex = 21
	volumeTitle.Parent = volumePanel
	do -- Concept T board look, the same serif cream title and plate buttons as Settings
		local CS = require(script.Parent.ConceptTSkin)
		CS.title(volumeTitle)
		volumeTitle.TextSize = 26
	end

	-- Holds only the layout and its rows (no decorative frames).
	local rows = Instance.new("Frame")
	rows.Size = UDim2.new(1, -40, 0, audioLayout.contentH)
	rows.Position = UDim2.new(0, 20, 0, 44)
	rows.BackgroundTransparency = 1
	rows.ZIndex = 21
	rows.Parent = volumePanel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = rows

	local percent = Detents.label

	local function refreshIcon()
		if volumeButton then
			local silent = ClientSettings.get("muted") or ClientSettings.get("musicVolume") <= 0
			local unavailable = deps.isMusicUnavailable and deps.isMusicUnavailable()
			local dimmed = silent or unavailable
			local icon = volumeButton:FindFirstChild("Icon")
			if icon then
				-- Image icon: dim it and draw a slash for muted / no track.
				icon.ImageTransparency = dimmed and 0.6 or 0
				local slash = volumeButton:FindFirstChild("MuteSlash")
				if not slash then
					slash = Instance.new("Frame")
					slash.Name = "MuteSlash"
					slash.AnchorPoint = Vector2.new(0.5, 0.5)
					slash.Position = UDim2.fromScale(0.5, 0.5)
					slash.Size = UDim2.fromOffset(3, 38)
					slash.Rotation = 45
					slash.BackgroundColor3 = Color3.fromRGB(222, 182, 104)
					slash.BorderSizePixel = 0
					slash.Active = false
					slash.ZIndex = 8
					slash.Parent = volumeButton
				end
				slash.Visible = dimmed and true or false
			elseif VOLUME_ICONS then
				volumeButton.Text = dimmed and VOLUME_ICONS[3] or VOLUME_ICONS[1]
				volumeButton.TextTransparency = 0
				volumeButton.TextStrokeTransparency = 1
			end
		end
	end

	local refreshMusic = deps.makeSliderRow(rows, "Music", 0, 100, function()
		return math.floor(ClientSettings.get("musicVolume") * 100 + 0.5)
	end, function(newValue)
		ClientSettings.set("musicVolume", newValue / 100)
	end, percent, 1, Detents.snap)
	local function addLine(order, text)
		local l = Instance.new("TextLabel")
		l.Name = "Line" .. order
		l.Size = UDim2.new(1, 0, 0, AudioRows.LINE_H)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Merriweather
		l.TextSize = 14
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = Color3.fromRGB(215, 200, 175)
		l.Text = text
		l.LayoutOrder = order
		l.ZIndex = 21
		l.Parent = rows
	end
	addLine(2, AudioRows.LINES.music)

	local refreshSfx = deps.makeSliderRow(rows, "SFX", 0, 100, function()
		return math.floor(ClientSettings.get("sfxVolume") * 100 + 0.5)
	end, function(newValue)
		ClientSettings.set("sfxVolume", newValue / 100)
	end, percent, 3, Detents.snap)
	addLine(4, AudioRows.LINES.sfx)

	-- Mute and Reset share one 44 px row (two plates, 8 px apart)
	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "SoundButtons"
	buttonRow.Size = UDim2.new(1, 0, 0, 44)
	buttonRow.BackgroundTransparency = 1
	buttonRow.LayoutOrder = 5
	buttonRow.ZIndex = 21
	buttonRow.Parent = rows
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.Parent = buttonRow

	addLine(6, AudioRows.LINES.mute)

	local muteButton = Instance.new("TextButton")
	muteButton.Size = UDim2.new(0.5, -4, 1, 0)
	muteButton.LayoutOrder = 1
	muteButton.Font = Enum.Font.Merriweather
	muteButton.TextSize = 16
	muteButton.BackgroundColor3 = Color3.fromRGB(70, 45, 25)
	muteButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	muteButton.ZIndex = 21
	muteButton.Parent = buttonRow
	polishButton(muteButton, 8)
	pcall(function() require(script.Parent.ConceptTSkin).plateButton(muteButton) end)
	deps.addButtonHoverScale(muteButton)

	local function refreshMute()
		muteButton.Text = ClientSettings.get("muted") and "Muted" or "Mute: Off"
	end

	muteButton.MouseButton1Click:Connect(function()
		ClientSettings.set("muted", not ClientSettings.get("muted"))
		playClickSfx()
	end)

	local resetButton = Instance.new("TextButton")
	resetButton.Name = "ResetSound"
	resetButton.Size = UDim2.new(0.5, -4, 1, 0)
	resetButton.LayoutOrder = 2
	resetButton.Font = Enum.Font.Merriweather
	resetButton.TextSize = 16
	resetButton.Text = Detents.RESET_LABEL
	resetButton.BackgroundColor3 = Color3.fromRGB(70, 45, 25)
	resetButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	resetButton.ZIndex = 21
	resetButton.Parent = buttonRow
	polishButton(resetButton, 8)
	pcall(function() require(script.Parent.ConceptTSkin).plateButton(resetButton) end)
	pcall(function() require(script.Parent.TavernKit).setPlateButton(resetButton, "secondary") end)
	deps.addButtonHoverScale(resetButton)
	resetButton.MouseButton1Click:Connect(function()
		playClickSfx()
		local defaults = PlayerProfile.defaultSettings()
		if not Detents.needsReset(ClientSettings.get, defaults) then return end -- nothing to undo, no popup
		local function doReset()
			for _, key in ipairs(Detents.RESET_KEYS) do
				ClientSettings.set(key, defaults[key])
			end
		end
		if deps.showConfirmDialog then
			deps.showConfirmDialog(Detents.CONFIRM_MESSAGE, doReset, { yesText = Detents.CONFIRM_YES, noText = Detents.CONFIRM_NO })
		else
			doReset()
		end
	end)

	ClientSettings.onChanged(function(key)
		if key == "musicVolume" then
			refreshMusic()
		elseif key == "sfxVolume" then
			refreshSfx()
		elseif key == "muted" then
			refreshMute()
		end
		refreshIcon()
	end)
	refreshMute()
	refreshIcon()
	if deps.onMusicAvailability then
		deps.onMusicAvailability(refreshIcon)
	end

	local volumeCloseButton = Instance.new("TextButton")
	volumeCloseButton.Size = UDim2.new(0, 140, 0, 44)
	volumeCloseButton.Position = UDim2.new(0.5, -70, 1, -56)
	volumeCloseButton.Font = Enum.Font.Merriweather
	volumeCloseButton.TextSize = 16
	volumeCloseButton.Text = "Close"
	volumeCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	volumeCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	volumeCloseButton.ZIndex = 21
	volumeCloseButton.Parent = volumePanel
	polishButton(volumeCloseButton, 12)
	deps.addButtonHoverScale(volumeCloseButton)

	require(script.Parent.CloseX).retire(volumeCloseButton)
	require(script.Parent.CloseX).attach(volumePanel, function()
		playClickSfx()
		popOut(volumeBackdrop, volumePanel)
	end)

	OverlayManager.register("volume", function()
		popOut(volumeBackdrop, volumePanel)
	end)
	-- Escape and a click on the dark area close it (Client/PopupDismiss).
	require(script.Parent.PopupDismiss).attach(volumeBackdrop, { id = "volume", panel = volumePanel, button = true })

	local function openVolume()
		playClickSfx()
		OverlayManager.closeAllExcept("volume")
		popIn(volumeBackdrop, volumePanel)
	end
	volumeButton.MouseButton1Click:Connect(openVolume)
	OverlayManager.registerOpener("volume", openVolume) -- the Menu's jukebox hotspot

	return {
		volumeBackdrop = volumeBackdrop,
	}
end
