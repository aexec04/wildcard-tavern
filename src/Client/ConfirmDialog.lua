--[[
	Client/ConfirmDialog.lua
	A generic, reusable yes/no modal. Used by Shop.lua (use a Recipe, sell a Patron) and the Discard button; written generically so any
	confirmation can reuse it. The labels come with the call (Engine/ConfirmCopy): a missing label is "Yes" / "Cancel", never a
	destructive word, so an action can not inherit another action's "discard".

	Look: a parchment sheet in a dark wood frame with four brass studs (the Choose a Patron cards), a bold ink title line (the first
	line of the message), an ink body under it, two plates, at most 520 px wide, 16 px text. No dark flat box and no gold corner brackets.

	deps fields:
		screenGui     -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishButton   -- function(instance, radius)
		addSoftShadow  -- function(instance, radius)
		playClickSfx   -- function(volume?)
		popIn          -- function(backdrop, content, opts?)
		popOut         -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)

	Returns:
		{
			showConfirmDialog = function(message, onConfirm, opts),
		}
	opts = { yesText, noText, danger }: danger makes the Yes plate red (destructive actions only); the default is a calm brass plate.

	The modal shows and hides with the shared popIn/popOut helpers (VisualHelpers.lua).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfirmCopy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ConfirmCopy"))

local INK = Color3.fromRGB(46, 32, 20)
local WOOD = Color3.fromRGB(82, 54, 30)
local WOOD_EDGE = Color3.fromRGB(38, 24, 12)
local BRASS_PLATE = Color3.fromRGB(122, 86, 38)
local RED_PLATE = Color3.fromRGB(140, 50, 45)
local WOOD_PLATE = Color3.fromRGB(78, 58, 40)
local CREAM = Color3.fromRGB(250, 240, 220)

return function(deps)
	local screenGui = deps.screenGui
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale

	local confirmBackdrop = Instance.new("Frame")
	confirmBackdrop.Name = "ConfirmBackdrop"
	confirmBackdrop.Size = UDim2.fromScale(1, 1)
	confirmBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	confirmBackdrop.BackgroundTransparency = 0.35
	confirmBackdrop.Visible = false
	confirmBackdrop.ZIndex = 35
	confirmBackdrop.Parent = screenGui

	local function corner(inst, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = inst
	end

	-- the dark wood frame
	local confirmPanel = Instance.new("Frame")
	confirmPanel.Name = "ConfirmPanel"
	confirmPanel.Size = UDim2.fromOffset(ConfirmCopy.MAX_WIDTH, 200)
	confirmPanel.Position = UDim2.fromScale(0.5, 0.5)
	confirmPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmPanel.BackgroundColor3 = WOOD
	confirmPanel.BorderSizePixel = 0
	confirmPanel.Active = true -- sinks clicks: the dark area behind is the only thing that cancels
	confirmPanel.ZIndex = 35
	confirmPanel.Parent = confirmBackdrop
	corner(confirmPanel, 14)
	local edge = Instance.new("UIStroke")
	edge.Color = WOOD_EDGE
	edge.Thickness = 2
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = confirmPanel
	addSoftShadow(confirmPanel, 16)
	for i, at in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local stud = Instance.new("Frame")
		stud.Name = "WoodStud" .. i
		stud.AnchorPoint = Vector2.new(0.5, 0.5)
		stud.Position = UDim2.new(at[1], at[1] == 0 and 8 or -8, at[2], at[2] == 0 and 8 or -8)
		stud.Size = UDim2.fromOffset(9, 9)
		stud.BackgroundColor3 = Color3.fromRGB(205, 164, 84)
		stud.BorderSizePixel = 0
		stud.Active = false
		stud.ZIndex = 39
		stud.Parent = confirmPanel
		corner(stud, 5)
	end

	-- the parchment sheet inside it
	local sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	sheet.Position = UDim2.fromOffset(8, 8)
	sheet.Size = UDim2.new(1, -16, 1, -16)
	sheet.BackgroundColor3 = Color3.fromRGB(238, 222, 186)
	sheet.BorderSizePixel = 0
	sheet.Active = false
	sheet.ZIndex = 36
	sheet.Parent = confirmPanel
	corner(sheet, 10)
	local sheetEdge = Instance.new("UIStroke")
	sheetEdge.Color = Color3.fromRGB(200, 160, 84)
	sheetEdge.Thickness = 2
	sheetEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sheetEdge.Parent = sheet
	local paper = Instance.new("UIGradient") -- warm paper, colour stops only
	paper.Rotation = 90
	paper.Color = ColorSequence.new(Color3.fromRGB(246, 232, 198), Color3.fromRGB(228, 210, 172))
	paper.Parent = sheet

	local function text(name, size, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextSize = size
		l.TextWrapped = true
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.Text = ""
		l.ZIndex = 37
		l.Parent = sheet
		return l
	end
	local confirmTitleLabel = text("Title", 20, Enum.Font.GothamBold)
	local confirmMessageLabel = text("Body", 16, Enum.Font.GothamMedium)
	confirmMessageLabel.TextYAlignment = Enum.TextYAlignment.Top

	local function plate(name)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(190, 44)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.TextWrapped = false
		b.TextColor3 = CREAM
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		b.ZIndex = 38
		b.Parent = sheet
		polishButton(b, 10)
		addButtonHoverScale(b)
		return b
	end
	local confirmYesButton = plate("Yes")
	local confirmNoButton = plate("No")
	confirmNoButton.BackgroundColor3 = WOOD_PLATE

	-- Reassigned on every showConfirmDialog call; Yes just calls whatever's
	-- currently pending, so there's only ever one live confirmation at a time.
	local pendingConfirmAction = nil

	confirmYesButton.MouseButton1Click:Connect(function()
		playClickSfx()
		-- The action itself fires immediately (it's a remote call / game
		-- logic, not tied to how the dialog looks going away) -- only the
		-- VISUAL dismiss is animated.
		if pendingConfirmAction then
			pendingConfirmAction()
			pendingConfirmAction = nil
		end
		popOut(confirmBackdrop, confirmPanel)
	end)

	local function cancelConfirm()
		pendingConfirmAction = nil
		popOut(confirmBackdrop, confirmPanel)
	end
	confirmNoButton.MouseButton1Click:Connect(function()
		playClickSfx()
		cancelConfirm()
	end)
	-- Escape and a click on the dark area mean Cancel, never Yes (Client/PopupDismiss, policy "cancel").
	require(script.Parent.PopupDismiss).attach(confirmBackdrop, { policy = "cancel", close = cancelConfirm, panel = confirmPanel, button = true })

	-- opts: { yesText, noText, danger }
	local function showConfirmDialog(message, onConfirm, opts)
		local o = ConfirmCopy.options(opts)
		local title, body = ConfirmCopy.split(message)
		local hostW = screenGui.AbsoluteSize.X
		local W = math.min(ConfirmCopy.MAX_WIDTH, math.max(280, (hostW > 0 and hostW or 800) - 24)) -- never wider than the window (phones)
		local pad = 28
		local innerW = W - 16 - 2 * pad
		local bodyH = body ~= "" and ConfirmCopy.bodyLines(body, innerW, 16) * 22 or 0
		local titleH = ConfirmCopy.bodyLines(title, innerW, 20) * 26
		local y = 20
		confirmTitleLabel.Text = title
		confirmTitleLabel.Position = UDim2.fromOffset(pad, y)
		confirmTitleLabel.Size = UDim2.fromOffset(innerW, titleH)
		y = y + titleH + (body ~= "" and 8 or 0)
		confirmMessageLabel.Text = body
		confirmMessageLabel.Visible = body ~= ""
		confirmMessageLabel.Position = UDim2.fromOffset(pad, y)
		confirmMessageLabel.Size = UDim2.fromOffset(innerW, bodyH)
		y = y + bodyH + 20
		confirmYesButton.Text = o.yesText
		confirmNoButton.Text = o.noText
		confirmYesButton.BackgroundColor3 = o.danger and RED_PLATE or BRASS_PLATE
		confirmYesButton.Position = UDim2.fromOffset(pad, y)
		confirmNoButton.Position = UDim2.fromOffset(innerW + pad - 190, y)
		y = y + 44 + 20
		confirmPanel.Size = UDim2.fromOffset(W, y + 16)
		pendingConfirmAction = onConfirm
		popIn(confirmBackdrop, confirmPanel)
	end

	return {
		showConfirmDialog = showConfirmDialog,
	}
end
