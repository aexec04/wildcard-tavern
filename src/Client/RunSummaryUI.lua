-- End-of-run summary: one screen shown over Game Over when state.runSummary arrives (server data,
-- Engine/RunSummary.lua). A rarity-framed badge card on the left (Night, title, best hand, route icons),
-- stats and Patrons on the right, buttons Save badge / Continue / Play Again. Display only.
local TweenService = game:GetService("TweenService")

local RunSummaryUI = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local PARCHMENT_DARK = Color3.fromRGB(199, 178, 137)
local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(92, 62, 36)
local GREEN = Color3.fromRGB(86, 140, 80)

local ui = {}
local lastKey
local dismissedKey

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextWrapped = true
	l.ZIndex = 72
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function button(parent, text, color, props)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 17
	b.TextColor3 = CREAM
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.ZIndex = 73
	for k, v in pairs(props) do
		b[k] = v
	end
	b.Parent = parent
	corner(b, 8)
	stroke(b, GOLD, 1.5)
	return b
end

local function clear(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- screenGui: parent; deps = { playClick, restart (function), saveBadge (function) }
function RunSummaryUI.init(screenGui, deps)
	ui.deps = deps
	local backdrop = Instance.new("Frame")
	backdrop.Name = "RunSummaryBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 8, 6)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.Visible = false
	backdrop.ZIndex = 70
	backdrop.Parent = screenGui
	ui.backdrop = backdrop

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 760, 0, 470)
	panel.BackgroundColor3 = PARCHMENT
	panel.BorderSizePixel = 0
	panel.ZIndex = 71
	panel.Parent = backdrop
	corner(panel, 10)
	stroke(panel, GOLD, 3)
	local fit = Instance.new("UIScale")
	fit.Parent = panel
	ui.fit = fit
	ui.panel = panel

	-- Badge card (left).
	local card = Instance.new("Frame")
	card.Name = "BadgeCard"
	card.Position = UDim2.new(0, 22, 0, 22)
	card.Size = UDim2.new(0, 270, 0, 426)
	card.BackgroundColor3 = PARCHMENT_DARK
	card.BorderSizePixel = 0
	card.ZIndex = 72
	card.Parent = panel
	corner(card, 10)
	ui.card = card
	ui.cardContent = Instance.new("Frame")
	ui.cardContent.Size = UDim2.fromScale(1, 1)
	ui.cardContent.BackgroundTransparency = 1
	ui.cardContent.ZIndex = 72
	ui.cardContent.Parent = card

	-- Right column.
	ui.heading = label(panel, {
		Position = UDim2.new(0, 312, 0, 22), Size = UDim2.new(1, -334, 0, 36), Text = "", TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	ui.stats = label(panel, {
		Position = UDim2.new(0, 312, 0, 64), Size = UDim2.new(1, -334, 0, 130), Text = "", TextSize = 18,
		Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	label(panel, {
		Position = UDim2.new(0, 312, 0, 200), Size = UDim2.new(1, -334, 0, 22), Text = "Patrons used", TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	ui.patrons = Instance.new("Frame")
	ui.patrons.Position = UDim2.new(0, 312, 0, 226)
	ui.patrons.Size = UDim2.new(1, -334, 0, 104)
	ui.patrons.BackgroundColor3 = PARCHMENT_DARK
	ui.patrons.BorderSizePixel = 0
	ui.patrons.ZIndex = 72
	ui.patrons.Parent = panel
	corner(ui.patrons, 8)
	stroke(ui.patrons, INK, 1.5)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 44, 0, 44)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = ui.patrons
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = ui.patrons
	ui.noPatrons = label(panel, {
		Position = UDim2.new(0, 322, 0, 250), Size = UDim2.new(1, -354, 0, 40), Text = "No Patrons this time.",
		TextSize = 15, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
	})

	ui.save = button(panel, "Save as my badge", GREEN, {
		Position = UDim2.new(0, 312, 0, 346), Size = UDim2.new(1, -334, 0, 40),
	})
	ui.continue = button(panel, "Continue", WOOD, {
		Position = UDim2.new(0, 312, 0, 400), Size = UDim2.new(0.5, -138, 0, 46),
	})
	ui.again = button(panel, "Play Again", WOOD, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 400), Size = UDim2.new(0.5, -138, 0, 46),
	})

	local function click()
		if deps.playClick then
			deps.playClick()
		end
	end
	ui.save.MouseButton1Click:Connect(function()
		if ui.save.Active then
			click()
			deps.saveBadge()
		end
	end)
	ui.continue.MouseButton1Click:Connect(function()
		click()
		dismissedKey = lastKey
		backdrop.Visible = false
	end)
	ui.again.MouseButton1Click:Connect(function()
		click()
		dismissedKey = lastKey
		backdrop.Visible = false
		deps.restart()
	end)
end

local function buildCard(summary)
	clear(ui.cardContent)
	local RarityFrame = require(script.Parent.RarityFrame)
	local CollectionBook = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CollectionBook"))
	if ui.rarityHandle then
		pcall(ui.rarityHandle.destroy)
	end
	ui.rarityHandle = RarityFrame.apply(ui.card, summary.rarity, { thickness = 4, radius = 10 })
	local rarityDef = CollectionBook.Rarities[summary.rarity]
	local parent = ui.cardContent
	label(parent, {
		Position = UDim2.new(0, 10, 0, 14), Size = UDim2.new(1, -20, 0, 22),
		Text = summary.won and "TAVERN CHAMPION" or "LAST CALL", TextSize = 17,
	})
	label(parent, {
		Position = UDim2.new(0, 10, 0, 40), Size = UDim2.new(1, -20, 0, 56),
		Text = "Night " .. tostring(math.floor(summary.night)), TextSize = 44,
	})
	label(parent, {
		Position = UDim2.new(0, 10, 0, 102), Size = UDim2.new(1, -20, 0, 24),
		Text = (summary.badgeIcon and (summary.badgeIcon .. " ") or "") .. (summary.titleText or "Wandering Guest"), TextSize = 18, Font = Enum.Font.GothamMedium,
	})
	label(parent, {
		Position = UDim2.new(0, 10, 0, 138), Size = UDim2.new(1, -20, 0, 20), Text = "Best hand", TextSize = 15,
		Font = Enum.Font.GothamMedium,
	})
	label(parent, {
		Position = UDim2.new(0, 10, 0, 158), Size = UDim2.new(1, -20, 0, 48),
		Text = summary.bestHand and string.format("%s\n%d", summary.bestHand.name, summary.bestHand.score) or "None",
		TextSize = 18,
	})
	label(parent, {
		Position = UDim2.new(0, 10, 0, 220), Size = UDim2.new(1, -20, 0, 20), Text = "Road taken", TextSize = 15,
		Font = Enum.Font.GothamMedium,
	})
	local routeRow = Instance.new("Frame")
	routeRow.Position = UDim2.new(0, 10, 0, 244)
	routeRow.Size = UDim2.new(1, -20, 0, 96)
	routeRow.BackgroundTransparency = 1
	routeRow.ZIndex = 72
	routeRow.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 36, 0, 36)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = routeRow
	for index, stop in ipairs(summary.route) do
		local chip = label(routeRow, {
			LayoutOrder = index, Text = stop.icon or "?", TextSize = 24, Font = Enum.Font.GothamMedium,
		})
		chip.TextWrapped = false
	end
	label(parent, {
		Position = UDim2.new(0, 10, 1, -64), Size = UDim2.new(1, -20, 0, 40),
		Text = string.upper(rarityDef and rarityDef.name or summary.rarity), TextSize = 20,
		TextColor3 = rarityDef and Color3.fromRGB(rarityDef.color[1], rarityDef.color[2], rarityDef.color[3]) or INK,
	})
end

local function buildPatrons(summary)
	clear(ui.patrons)
	local PatronPlaque = require(script.Parent.PatronPlaque)
	ui.noPatrons.Visible = #summary.patrons == 0
	for index, patron in ipairs(summary.patrons) do
		if index > 10 then
			break
		end
		local seat = Instance.new("Frame")
		seat.LayoutOrder = index
		seat.BackgroundColor3 = PARCHMENT
		seat.BorderSizePixel = 0
		seat.ZIndex = 73
		seat.Parent = ui.patrons
		corner(seat, 22)
		stroke(seat, INK, 2)
		local emoji = label(seat, {
			Size = UDim2.fromScale(1, 1), Text = patron.icon or "?", TextSize = 22, Font = Enum.Font.GothamMedium,
			ZIndex = 74,
		})
		emoji.TextWrapped = false
		PatronPlaque.apply(seat, patron.id, { zIndex = 75, cornerRadius = 22, emojiLabel = emoji })
	end
end

function RunSummaryUI.update(state)
	if not ui.backdrop or type(state) ~= "table" then
		return
	end
	local summary = state.runSummary
	if not summary then
		ui.backdrop.Visible = false
		lastKey = nil
		dismissedKey = nil
		return
	end
	local key = string.format("%d-%s-%d-%d", summary.night, tostring(summary.won), summary.handsPlayed, summary.bestHand and summary.bestHand.score or 0)
	if key ~= lastKey then
		lastKey = key
		local shown = pcall(function()
			buildCard(summary)
			buildPatrons(summary)
		end)
		if not shown then
			ui.backdrop.Visible = false -- a broken card must never block the plain Game Over screen
			dismissedKey = key
			return
		end
		ui.heading.Text = summary.won and "You beat the tavern!" or "Your run is over"
		ui.stats.Text = string.format(
			"Reached Night %d, Round %d\nHands played: %d\nBest hand: %s\nRoad: %d stop%s",
			math.floor(summary.night), summary.round or 1, summary.handsPlayed,
			summary.bestHand and string.format("%s (%d)", summary.bestHand.name, summary.bestHand.score) or "none",
			#summary.route, #summary.route == 1 and "" or "s"
		) .. ((state.nextUnlock and state.nextUnlock.label) and ("\nNext unlock: " .. state.nextUnlock.label) or "")
		if dismissedKey ~= key then
			-- Fit small screens (the panel is 760x470), then pop in.
			local size = ui.backdrop.Parent and ui.backdrop.Parent.AbsoluteSize or Vector2.new(1280, 720)
			local base = math.clamp(math.min(size.X / 800, size.Y / 510), 0.6, 1)
			ui.backdrop.Visible = true
			ui.fit.Scale = base * 0.85
			TweenService:Create(ui.fit, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
		end
	end
	local saved = summary.badgeSaved == true
	ui.save.Active = not saved
	ui.save.Text = saved and "Badge saved" or "Save as my badge"
	ui.save.BackgroundColor3 = saved and Color3.fromRGB(120, 110, 95) or GREEN
end

return RunSummaryUI
