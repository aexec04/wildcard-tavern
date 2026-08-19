--[[
	Client/ConfirmDialog.lua
	A generic, reusable yes/no modal for anything destructive/irreversible.
	Right now just "discard this Patron?" (used by Shop.lua), but written
	generically so future confirmations (selling a special card, resetting
	something) can reuse it instead of each building their own popup.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. showConfirmDialog is passed as a dep
	into Shop.lua, so it comes back out of the require() call.

	deps fields:
		screenGui     -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel    -- function(instance, radius)
		polishButton   -- function(instance, radius)
		addSoftShadow  -- function(instance, radius)
		playClickSfx   -- function(volume?)

	Returns:
		{
			showConfirmDialog = function(message, onConfirm),
		}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx

	local confirmBackdrop = Instance.new("Frame")
	confirmBackdrop.Name = "ConfirmBackdrop"
	confirmBackdrop.Size = UDim2.fromScale(1, 1)
	confirmBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	confirmBackdrop.BackgroundTransparency = 0.35
	confirmBackdrop.Visible = false
	confirmBackdrop.ZIndex = 35
	confirmBackdrop.Parent = screenGui

	local confirmPanel = Instance.new("Frame")
	confirmPanel.Size = UDim2.new(0, 360, 0, 170)
	confirmPanel.Position = UDim2.fromScale(0.5, 0.5)
	confirmPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	confirmPanel.ZIndex = 35
	confirmPanel.Parent = confirmBackdrop
	polishPanel(confirmPanel, 14)
	addSoftShadow(confirmPanel, 16)

	local confirmMessageLabel = Instance.new("TextLabel")
	confirmMessageLabel.Size = UDim2.new(1, -30, 0, 90)
	confirmMessageLabel.Position = UDim2.new(0, 15, 0, 16)
	confirmMessageLabel.BackgroundTransparency = 1
	confirmMessageLabel.Font = Enum.Font.Gotham
	confirmMessageLabel.TextSize = 15
	confirmMessageLabel.TextWrapped = true
	confirmMessageLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	confirmMessageLabel.Text = ""
	confirmMessageLabel.ZIndex = 35
	confirmMessageLabel.Parent = confirmPanel

	local confirmYesButton = Instance.new("TextButton")
	confirmYesButton.Size = UDim2.new(0, 140, 0, 40)
	confirmYesButton.Position = UDim2.new(0, 20, 1, -55)
	confirmYesButton.Font = Enum.Font.GothamBold
	confirmYesButton.TextSize = 15
	confirmYesButton.Text = "Yes, discard it"
	confirmYesButton.BackgroundColor3 = Color3.fromRGB(140, 50, 45)
	confirmYesButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	confirmYesButton.ZIndex = 35
	confirmYesButton.Parent = confirmPanel
	polishButton(confirmYesButton, 10)

	local confirmNoButton = Instance.new("TextButton")
	confirmNoButton.Size = UDim2.new(0, 140, 0, 40)
	confirmNoButton.Position = UDim2.new(1, -160, 1, -55)
	confirmNoButton.Font = Enum.Font.GothamBold
	confirmNoButton.TextSize = 15
	confirmNoButton.Text = "Cancel"
	confirmNoButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	confirmNoButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	confirmNoButton.ZIndex = 35
	confirmNoButton.Parent = confirmPanel
	polishButton(confirmNoButton, 10)

	-- Reassigned on every showConfirmDialog call; Yes just calls whatever's
	-- currently pending, so there's only ever one live confirmation at a time.
	local pendingConfirmAction = nil

	confirmYesButton.MouseButton1Click:Connect(function()
		playClickSfx()
		confirmBackdrop.Visible = false
		if pendingConfirmAction then
			pendingConfirmAction()
			pendingConfirmAction = nil
		end
	end)

	confirmNoButton.MouseButton1Click:Connect(function()
		playClickSfx()
		confirmBackdrop.Visible = false
		pendingConfirmAction = nil
	end)

	local function showConfirmDialog(message, onConfirm)
		confirmMessageLabel.Text = message
		pendingConfirmAction = onConfirm
		confirmBackdrop.Visible = true
	end

	return {
		showConfirmDialog = showConfirmDialog,
	}
end
