--[[
	Client/PanelTabs.lua
	Navigation for the account panels, built like the Menu's tavern furniture (groups in Engine/PanelGroups.lua):
	  row 1: three big hanging group tabs with a painted icon each: The Tome (leather brown), The Strongbox (deep
	         green) and The Coin Jar (brass). The tab of the open page's group glows gold.
	  row 2: small bookmark ribbons for the pages inside that group; the open page wears a gold ribbon, the others
	         sway a little on hover (off in calm mode).
	Opening any page shows its own group (every panel has its own strip, built from the page id). Back returns to
	the panel the player came from, or closes to the Menu. Both rows scroll sideways on phones. Each panel calls
	attach(backdrop, id) once after building its backdrop and registers its opener with
	OverlayManager.registerOpener(id, fn). The strip lives inside the panel's Backdrop (so InputGuard / InputLock
	still see the same overlay), is Active so a click on it never counts as "outside the panel", and hides with it.
	Painted icons: Menu art ids with emoji fallbacks (ArtIcon). The strip occupies y 3 to PanelLayout.STRIP_BOTTOM.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local OverlayManager = require(script.Parent.OverlayManager)
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PanelGroups = require(Engine:WaitForChild("PanelGroups"))
local PanelLayout = require(Engine:WaitForChild("PanelLayout"))
local ClientSettings = require(script.Parent.ClientSettings)

local PanelTabs = {}

PanelTabs.TABS = PanelGroups.pages() -- flat list in display order (group order, then page order)

local WOOD = Color3.fromRGB(92, 62, 36)
local WOOD_ACTIVE = Color3.fromRGB(150, 104, 52)
local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local INK = Color3.fromRGB(60, 40, 22)

local current, previous -- panel ids: the open one, and the one the player came from

-- Pure helper (unit-testable): which id Back should open, or nil for "close to the Menu".
function PanelTabs.backTarget(currentId, previousId)
	if previousId and previousId ~= currentId then return previousId end
	return nil
end

function PanelTabs.go(id)
	return OverlayManager.open(id)
end

-- Panels with levels (the Collection: detail card, section, gallery room) say how Escape steps back one level: fn() returns true when it
-- did. Escape closes the panel only when it did not (Client/PopupDismiss `step`).
local steps = {}
function PanelTabs.setStep(id, fn)
	steps[id] = fn
end

function PanelTabs.back(id)
	local target = PanelTabs.backTarget(id, previous)
	if target and OverlayManager.open(target) then return end
	OverlayManager.closeAllExcept(nil)
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function styleButton(button, active)
	button.BackgroundColor3 = active and WOOD_ACTIVE or WOOD
	button.TextColor3 = active and CREAM or Color3.fromRGB(226, 205, 160)
	local s = button:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = active and GOLD or INK
		s.Thickness = active and 2.5 or 1.5
	end
end

local function newButton(parent, text, width, order, height)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = UDim2.fromOffset(width, height or 30)
	b.LayoutOrder = order
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.ZIndex = 61
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	require(script.Parent.SetSkin).register(b, "tab") -- the equipped Card Set's tab plate or wash
	return b
end

local function newRow(parent, name, y, h)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.Position = UDim2.new(0, 92, 0, y)
	scroll.Size = UDim2.new(1, -92, 0, h)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.ZIndex = 60
	scroll.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = scroll
	return scroll
end

local function groupTab(parent, group, active, order)
	local b = newButton(parent, "", 168, order, 32)
	b.Name = "Group_" .. group.id
	b.AutoButtonColor = false
	b.BackgroundColor3 = active and rgb(group.glow) or rgb(group.color)
	local stroke = b:FindFirstChildOfClass("UIStroke")
	stroke.Color = active and GOLD or INK
	stroke.Thickness = active and 3 or 1.5
	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "Icon"
	iconFrame.Position = UDim2.fromOffset(6, 3)
	iconFrame.Size = UDim2.fromOffset(26, 26)
	iconFrame.BackgroundColor3 = Color3.fromRGB(46, 30, 18)
	iconFrame.BorderSizePixel = 0
	iconFrame.ZIndex = 62
	iconFrame.Parent = b
	local ic = Instance.new("UICorner")
	ic.CornerRadius = UDim.new(0.5, 0)
	ic.Parent = iconFrame
	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.fromScale(1, 1)
	emoji.BackgroundTransparency = 1
	emoji.Font = Enum.Font.GothamBold
	emoji.TextSize = 16
	emoji.TextColor3 = CREAM
	emoji.TextTransparency = 0
	emoji.TextStrokeTransparency = 1
	emoji.Text = group.emoji
	emoji.ZIndex = 63
	emoji.Parent = iconFrame
	pcall(require(script.Parent.ArtIcon).apply, iconFrame, group.art[1], group.art[2], emoji, { cornerRadius = 13 })
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Position = UDim2.fromOffset(38, 0)
	name.Size = UDim2.new(1, -42, 1, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 15
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = active and CREAM or Color3.fromRGB(226, 205, 160)
	name.TextTransparency = 0
	name.TextStrokeTransparency = 1
	name.Text = group.text
	name.ZIndex = 62
	name.Parent = b
	return b
end

local function ribbon(parent, group, page, active, order)
	local width = 34 + #page.text * 9
	local b = newButton(parent, page.text, width, order, 24)
	b.Name = "Tab_" .. page.id
	b.AutoButtonColor = false
	b.TextSize = 14
	b.BackgroundColor3 = active and GOLD or rgb(group.color)
	b.TextColor3 = active and INK or CREAM
	local stroke = b:FindFirstChildOfClass("UIStroke")
	stroke.Color = active and Color3.fromRGB(255, 232, 160) or INK
	stroke.Thickness = active and 2.5 or 1.5
	b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 5)
	if not active then -- gentle bookmark sway on hover
		b.MouseEnter:Connect(function()
			if ClientSettings.get("reduceShake") == true then return end
			TweenService:Create(b, TweenInfo.new(0.18, Enum.EasingStyle.Sine), { Rotation = 3 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Sine), { Rotation = 0 }):Play()
		end)
	end
	return b
end

function PanelTabs.attach(backdrop, id, playClick, panel)
	if not backdrop or backdrop:FindFirstChild("PanelTabs") then return end
	local activeGroup = PanelGroups.groupOf(id) or PanelGroups.GROUPS[1]
	local stripH = PanelLayout.STRIP_BOTTOM - 3
	local strip = Instance.new("Frame")
	strip.Name = "PanelTabs"
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, 3)
	strip.Size = UDim2.new(0.9, 0, 0, stripH)
	strip.BackgroundTransparency = 1
	strip.Active = true -- sinks clicks so the backdrop's "click outside closes" never fires from the strip
	strip.ZIndex = 60
	strip.Parent = backdrop
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(1100, stripH)
	sizeLimit.Parent = strip

	local back = newButton(strip, "< Back", 84, 0)
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 2)
	styleButton(back, false)

	local groupsRow = newRow(strip, "Groups", 0, 34)
	local pagesRow = newRow(strip, "Tabs", 36, 24)

	for i, group in ipairs(PanelGroups.GROUPS) do
		local active = group.id == activeGroup.id
		local g = groupTab(groupsRow, group, active, i)
		g.MouseButton1Click:Connect(function()
			if playClick then playClick() end
			if not active then PanelTabs.go(PanelGroups.defaultPage(group.id)) end
		end)
	end
	for i, page in ipairs(activeGroup.pages) do
		local b = ribbon(pagesRow, activeGroup, page, page.id == id, i)
		b.MouseButton1Click:Connect(function()
			if playClick then playClick() end
			if page.id ~= id then PanelTabs.go(page.id) end
		end)
	end
	back.MouseButton1Click:Connect(function()
		if playClick then playClick() end
		PanelTabs.back(id)
	end)

	-- The strip occupies y 3..STRIP_BOTTOM. Centered panels (up to 0.9 of the height) are nudged down once so their
	-- titles are never covered, and the top-right corner icon row is hidden while an account panel is open.
	local STRIP_CLEAR = PanelLayout.STRIP_NUDGE
	local function clearStrip()
		for _, child in ipairs(backdrop:GetChildren()) do
			if child:IsA("GuiObject") and child ~= strip and not child:GetAttribute("TabShifted")
				and child.AnchorPoint.Y == 0.5 and child.Position.Y.Scale == 0.5 then
				child:SetAttribute("TabShifted", true)
				child.Position = child.Position + UDim2.fromOffset(0, STRIP_CLEAR)
			end
		end
	end
	-- the dock is a function of which registered backdrops are visible (Client/CornerDock), never a remembered boolean
	pcall(function() require(script.Parent.CornerDock).register(backdrop) end)
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		if backdrop.Visible then
			pcall(clearStrip)
			if current ~= id then previous, current = current, id end
		elseif current == id then
			current = nil
		end
	end)
	if panel and PanelLayout.FULL_SCREEN[id] then pcall(require(script.Parent.PanelFullScreen).apply, backdrop, panel, id) end
	-- Escape and a click on the dark area close the panel too (Client/PopupDismiss, closing through the id the panel registers
	-- with OverlayManager). `panel` is the panel itself: a click on it is never "outside"; without it only Escape is wired.
	pcall(function()
		require(script.Parent.PopupDismiss).attach(backdrop, {
			id = id, panel = panel, button = true,
			step = function() -- a panel with levels (the Collection) registers PanelTabs.setStep(id, fn)
				local fn = steps[id]
				return fn ~= nil and fn() == true
			end,
		})
	end)
end

return PanelTabs
