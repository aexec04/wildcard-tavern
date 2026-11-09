--[[
	Client/LegendPanel.lua
	LEGEND PRESTIGE (Engine/Legend.lua), opened from the "Legend" button in the Collection header. A gold crest with the
	Legend level, a hint on how to level up and ten reward tiles (title, card back, gold aura, table trinkets): reached ones
	glow, the rest are dimmed (never black). Display only: the server awards points and rewards when a standard stake 8 run
	is won and sends state.legend. Refreshes on every StateUpdated while open.

	LegendPanel.crestText(level) -> "👑 3" style text, used by other screens next to the player's name.
	init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, addTooltip,
	              popIn, popOut, addButtonHoverScale, getLatestState, StateUpdatedRemote }
]]

local LegendPanel = {}

function LegendPanel.crestText(level)
	level = math.floor(tonumber(level) or 0)
	if level <= 0 then
		return ""
	end
	return "👑" .. tostring(level)
end

function LegendPanel.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local ArtIcon = require(script.Parent.ArtIcon)

	local INK = Color3.fromRGB(60, 40, 22)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BRIGHT = Color3.fromRGB(255, 226, 140)
	local WOOD = Color3.fromRGB(86, 58, 34)
	local PARCH = Color3.fromRGB(222, 198, 150)

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 15
		l.ZIndex = 43
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "LegendBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.74, 0.8)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	label(panel, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), TextSize = 22, Text = "Legend" })

	-- crest: a gold round badge with the level
	local crest = Instance.new("Frame")
	crest.Size = UDim2.fromOffset(110, 110)
	crest.AnchorPoint = Vector2.new(0.5, 0)
	crest.Position = UDim2.new(0.5, 0, 0, 44)
	crest.BackgroundColor3 = WOOD
	crest.BorderSizePixel = 0
	crest.ZIndex = 42
	crest.Parent = panel
	deps.roundCorner(crest, 55)
	local crestStroke = Instance.new("UIStroke")
	crestStroke.Color = BRIGHT
	crestStroke.Thickness = 4
	crestStroke.Parent = crest
	label(crest, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 14), TextSize = 34, Text = "👑", TextColor3 = BRIGHT, ZIndex = 44 })
	local levelLabel = label(crest, { Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 58), TextSize = 26, Text = "0 / 10", TextColor3 = CREAM, ZIndex = 44 })
	local hintLabel = label(panel, {
		Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 160), TextSize = 15, Font = Enum.Font.GothamMedium, TextWrapped = true, Text = "",
	})

	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, -30, 1, -270)
	grid.Position = UDim2.fromOffset(15, 206)
	grid.BackgroundTransparency = 1
	grid.ZIndex = 41
	grid.Parent = panel
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(118, 120)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(110, 34)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -10)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	closeButton.Text = "Close"
	closeButton.ZIndex = 43
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	local function tile(row)
		local t = Instance.new("Frame")
		t.Name = "Level_" .. row.level
		t.LayoutOrder = row.level
		t.BackgroundColor3 = PARCH
		t.BorderSizePixel = 0
		t.ZIndex = 42
		t.Parent = grid
		deps.roundCorner(t, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = row.reached and BRIGHT or INK
		stroke.Thickness = row.reached and 3 or 1.5
		stroke.Parent = t
		label(t, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 3), TextSize = 16, Text = "Level " .. row.level })
		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(46, 46)
		well.Position = UDim2.fromOffset(36, 26)
		well.BackgroundColor3 = WOOD
		well.BorderSizePixel = 0
		well.ZIndex = 43
		well.Parent = t
		deps.roundCorner(well, 8)
		local emoji = row.icon or (row.kind == "cardBack" and "🂠" or "🏷️")
		local glyph = label(well, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextColor3 = CREAM, Text = emoji, ZIndex = 44 })
		local category = (row.kind == "cardBack" and "card_backs") or (row.kind == "title" and "titles") or nil
		if category then
			pcall(ArtIcon.apply, well, category, row.id, glyph, { cornerRadius = 8, zIndex = 45, dim = not row.reached })
		end
		if not row.reached then glyph.TextTransparency = 0.35 end
		label(t, { Size = UDim2.new(1, -6, 0, 40), Position = UDim2.fromOffset(3, 76), TextSize = 14, TextWrapped = true, Font = Enum.Font.GothamMedium, Text = row.text })
		deps.addTooltip(t, row.text .. (row.reached and "" or (" at Legend level " .. row.level)))
	end

	local function refresh()
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local state = deps.getLatestState and deps.getLatestState() or nil
		local view = state and state.legend
		if not view then
			levelLabel.Text = "0 / 10"
			hintLabel.Text = "Legend loads when you join."
			return
		end
		levelLabel.Text = view.level .. " / " .. view.max
		hintLabel.Text = view.open and view.hint or "Clear stake 8 to become a Legend. Rewards are cosmetic, never power."
		for _, row in ipairs(view.rewards) do
			tile(row)
		end
	end

	OverlayManager.register("legend", function()
		deps.popOut(backdrop, panel)
	end)
	deps.openButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("legend")
		refresh()
		deps.popIn(backdrop, panel)
	end)
	closeButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)
end

return LegendPanel
