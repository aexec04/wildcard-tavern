--[[
	Client/SeedRunDialog.lua
	SHAREABLE SEED CODES (Phase 16): a small modal for starting a run from
	a shared seed code -- type in a code a friend sent you (or roll a
	fresh one to send THEM), hit Start, and both of you get the exact
	same deterministic run (see Shared/Engine/SeededRng.lua's header for
	what "same" guarantees once your choices start diverging). No
	leaderboard involved -- this is for comparing one specific run on
	demand between the two of you, not a ranked board.

	Mirrors ConfirmDialog.lua's backdrop+panel+popIn/popOut shape, just
	swapping the Yes/No row for a TextBox + Roll button on one row and a
	Start/Cancel row below it.

	deps fields:
		screenGui        -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel       -- function(instance, radius)
		polishButton      -- function(instance, radius)
		addSoftShadow     -- function(instance, radius)
		playClickSfx      -- function(volume?)
		popIn             -- function(backdrop, content, opts?)
		popOut            -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)
		StartSeedRunRemote -- RemoteEvent, fired (code) on Start click
		SeededRng         -- Shared/Engine/SeededRng module, used for .randomCode() on Roll click

	Returns:
		{
			showSeedRunDialog = function(),
		}

	`showSeedRunDialog` is passed into Menu.lua as the `openSeedRunDialog`
	dep, so its "Seed Run..." button can open this without either module
	needing to know about the other directly.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local StartSeedRunRemote = deps.StartSeedRunRemote
	local SeededRng = deps.SeededRng or require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SeededRng"))

	local seedBackdrop = Instance.new("Frame")
	seedBackdrop.Name = "SeedRunBackdrop"
	seedBackdrop.Size = UDim2.fromScale(1, 1)
	seedBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	seedBackdrop.BackgroundTransparency = 0.35
	seedBackdrop.Visible = false
	seedBackdrop.ZIndex = 35
	seedBackdrop.Parent = screenGui
	require(script.Parent.MenuTitleHider).bind(screenGui, seedBackdrop)

	local seedPanel = Instance.new("Frame")
	seedPanel.Size = UDim2.new(0, 360, 0, 210)
	seedPanel.Position = UDim2.fromScale(0.5, 0.5)
	seedPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	seedPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	seedPanel.ZIndex = 35
	seedPanel.Parent = seedBackdrop
	polishPanel(seedPanel, 14, "wood")
	addSoftShadow(seedPanel, 16)

	local seedTitleLabel = Instance.new("TextLabel")
	seedTitleLabel.Size = UDim2.new(1, -30, 0, 26)
	seedTitleLabel.Position = UDim2.new(0, 15, 0, 14)
	seedTitleLabel.BackgroundTransparency = 1
	seedTitleLabel.Font = Enum.Font.GothamBold
	seedTitleLabel.TextSize = 17
	seedTitleLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	seedTitleLabel.Text = "\240\159\142\178 Seed Run"
	seedTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	seedTitleLabel.ZIndex = 35
	seedTitleLabel.Parent = seedPanel

	local seedHintLabel = Instance.new("TextLabel")
	seedHintLabel.Size = UDim2.new(1, -30, 0, 36)
	seedHintLabel.Position = UDim2.new(0, 15, 0, 40)
	seedHintLabel.BackgroundTransparency = 1
	seedHintLabel.Font = Enum.Font.Gotham
	seedHintLabel.TextSize = 15
	seedHintLabel.TextWrapped = true
	seedHintLabel.TextColor3 = Color3.fromRGB(200, 185, 165)
	seedHintLabel.TextXAlignment = Enum.TextXAlignment.Left
	seedHintLabel.Text = "Type a 6 character code from a friend, or roll one to send them. Same code, same run."
	seedHintLabel.ZIndex = 35
	seedHintLabel.Parent = seedPanel

	local seedCodeBox = Instance.new("TextBox")
	seedCodeBox.Size = UDim2.new(1, -110, 0, 40)
	seedCodeBox.Position = UDim2.new(0, 15, 0, 84)
	seedCodeBox.Font = Enum.Font.GothamBold
	seedCodeBox.TextSize = 18
	seedCodeBox.PlaceholderText = "e.g. STAR27"
	seedCodeBox.MaxVisibleGraphemes = 8
	seedCodeBox.Text = ""
	seedCodeBox.ClearTextOnFocus = false
	seedCodeBox.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	seedCodeBox.TextColor3 = Color3.fromRGB(250, 240, 220)
	seedCodeBox.ZIndex = 35
	seedCodeBox.Parent = seedPanel
	polishButton(seedCodeBox, 8)

	local seedRollButton = Instance.new("TextButton")
	seedRollButton.Size = UDim2.new(0, 80, 0, 40)
	seedRollButton.Position = UDim2.new(1, -95, 0, 84)
	seedRollButton.Font = Enum.Font.GothamBold
	seedRollButton.TextSize = 14
	seedRollButton.Text = "Roll"
	seedRollButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	seedRollButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	seedRollButton.ZIndex = 35
	seedRollButton.Parent = seedPanel
	polishButton(seedRollButton, 10)

	local seedStartButton = Instance.new("TextButton")
	seedStartButton.Size = UDim2.new(0, 140, 0, 40)
	seedStartButton.Position = UDim2.new(0, 20, 1, -55)
	seedStartButton.Font = Enum.Font.GothamBold
	seedStartButton.TextSize = 15
	seedStartButton.Text = "Start Run"
	seedStartButton.BackgroundColor3 = Color3.fromRGB(60, 110, 65)
	seedStartButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	seedStartButton.ZIndex = 35
	seedStartButton.Parent = seedPanel
	polishButton(seedStartButton, 10)

	local seedCancelButton = Instance.new("TextButton")
	seedCancelButton.Size = UDim2.new(0, 140, 0, 40)
	seedCancelButton.Position = UDim2.new(1, -160, 1, -55)
	seedCancelButton.Font = Enum.Font.GothamBold
	seedCancelButton.TextSize = 15
	seedCancelButton.Text = "Cancel"
	seedCancelButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	seedCancelButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	seedCancelButton.ZIndex = 35
	seedCancelButton.Parent = seedPanel
	polishButton(seedCancelButton, 10)

	-- the equipped Card Set's panel colours and ink (7:1) and button plates; classic keeps the wood panel
	local seedSkin
	pcall(function()
		local pStroke = seedPanel:FindFirstChildOfClass("UIStroke")
		seedSkin = require(script.Parent.PopupSkin).dark(seedPanel, pStroke,
			{ { seedTitleLabel, Color3.fromRGB(250, 240, 220) }, { seedHintLabel, Color3.fromRGB(200, 185, 165) } },
			{ plate = Color3.fromRGB(40, 30, 22), edge = pStroke and pStroke.Color })
		local Kit = require(script.Parent.TavernKit)
		Kit.setPlateButton(seedStartButton, "primary")
		Kit.setPlateButton(seedRollButton, "secondary")
		Kit.setPlateButton(seedCancelButton, "secondary")
	end)

	addButtonHoverScale(seedRollButton)
	addButtonHoverScale(seedStartButton)
	addButtonHoverScale(seedCancelButton)

	seedRollButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if SeededRng then
			seedCodeBox.Text = SeededRng.randomCode(6)
		end
	end)

	local function attemptStart()
		local okCode, code, message = SeededRng.validateCode(seedCodeBox.Text)
		if not okCode then
			-- a friendly message in the hint line instead of failing silently
			seedHintLabel.Text = message
			seedHintLabel.TextColor3 = Color3.fromRGB(255, 190, 150)
			return
		end
		playClickSfx()
		popOut(seedBackdrop, seedPanel)
		local CS = require(script.Parent.ChallengeStart)
		if CS.ready() then
			CS.start("seed", nil, code) -- same rules as Daily and Weekly: state check, confirm, show the table
		elseif StartSeedRunRemote then
			StartSeedRunRemote:FireServer(code)
		end
	end

	seedStartButton.MouseButton1Click:Connect(attemptStart)

	-- Hitting Enter in the box starts the run too -- `enterPressed` is the
	-- 2nd arg Roblox's TextBox.FocusLost always fires (true when Enter/
	-- Return specifically caused the focus loss, false for tab/click-away).
	seedCodeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			attemptStart()
		end
	end)

	seedCancelButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(seedBackdrop, seedPanel)
	end)
	-- Escape and a click on the dark area close it like Cancel (Client/PopupDismiss).
	require(script.Parent.PopupDismiss).attach(seedBackdrop, { panel = seedPanel, close = function() popOut(seedBackdrop, seedPanel) end, button = true })

	local function showSeedRunDialog()
		seedCodeBox.Text = ""
		seedHintLabel.Text = "Type a 6 character code from a friend, or roll one to send them. Same code, same run."
		seedHintLabel.TextColor3 = Color3.fromRGB(200, 185, 165)
		if seedSkin then seedSkin() end
		popIn(seedBackdrop, seedPanel)
	end

	return {
		showSeedRunDialog = showSeedRunDialog,
	}
end
