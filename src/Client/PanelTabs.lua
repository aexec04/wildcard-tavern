--[[
	Client/PanelTabs.lua
	One shared tab strip for the account panels (Collection, Rewards, Badges, Legend, Flair, Stats, Season, Quests,
	Daily, Store): painted wood tabs along the top of the screen plus a Back button, so a player can jump straight
	from one panel to the next instead of closing and reopening. The active tab is highlighted; the strip scrolls
	sideways on phones. Each panel calls attach(backdrop, id) once after building its backdrop and registers its
	opener with OverlayManager.registerOpener(id, fn).

	Back returns to the panel the player came from, or closes to the Menu when the panel was opened directly.
	The strip lives inside the panel's Backdrop (so InputGuard / InputLock still see the same overlay), is Active
	so a click on it never counts as "outside the panel", and hides with its backdrop.
]]
local OverlayManager = require(script.Parent.OverlayManager)

local PanelTabs = {}

-- Display order of the tabs. Ids match OverlayManager.register / registerOpener names.
PanelTabs.TABS = {
	{ id = "collection", text = "Collection" },
	{ id = "collectionRewards", text = "Rewards" },
	{ id = "badges", text = "Badges" },
	{ id = "legend", text = "Legend" },
	{ id = "flair", text = "Flair" },
	{ id = "stats", text = "Stats" },
	{ id = "season", text = "Season" },
	{ id = "quests", text = "Quests" },
	{ id = "dailyRewards", text = "Daily" },
	{ id = "store", text = "Store" },
}

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

function PanelTabs.back(id)
	local target = PanelTabs.backTarget(id, previous)
	if target and OverlayManager.open(target) then return end
	OverlayManager.closeAllExcept(nil)
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

local function newButton(parent, text, width, order)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = UDim2.fromOffset(width, 30)
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
	return b
end

function PanelTabs.attach(backdrop, id, playClick)
	if not backdrop or backdrop:FindFirstChild("PanelTabs") then return end
	local strip = Instance.new("Frame")
	strip.Name = "PanelTabs"
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, 3)
	strip.Size = UDim2.new(0.9, 0, 0, 34)
	strip.BackgroundTransparency = 1
	strip.Active = true -- sinks clicks so the backdrop's "click outside closes" never fires from the strip
	strip.ZIndex = 60
	strip.Parent = backdrop
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(1100, 34)
	sizeLimit.Parent = strip

	local back = newButton(strip, "< Back", 84, 0)
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 2)
	styleButton(back, false)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Tabs"
	scroll.Position = UDim2.fromOffset(92, 0)
	scroll.Size = UDim2.new(1, -92, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.ZIndex = 60
	scroll.Parent = strip
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = scroll

	local buttons = {}
	for i, tab in ipairs(PanelTabs.TABS) do
		local b = newButton(scroll, tab.text, 18 + #tab.text * 9, i)
		b.Name = "Tab_" .. tab.id
		styleButton(b, tab.id == id)
		buttons[tab.id] = b
		b.MouseButton1Click:Connect(function()
			if playClick then playClick() end
			if tab.id ~= id then PanelTabs.go(tab.id) end
		end)
	end
	back.MouseButton1Click:Connect(function()
		if playClick then playClick() end
		PanelTabs.back(id)
	end)

	-- The strip occupies y 3..37. Centered panels (up to 0.9 of the height) are nudged down 24px once so their titles
	-- are never covered, and the top-right corner icon row is hidden while an account panel is open.
	local STRIP_CLEAR = 24
	local function clearStrip()
		for _, child in ipairs(backdrop:GetChildren()) do
			if child:IsA("GuiObject") and child ~= strip and not child:GetAttribute("TabShifted")
				and child.AnchorPoint.Y == 0.5 and child.Position.Y.Scale == 0.5 then
				child:SetAttribute("TabShifted", true)
				child.Position = child.Position + UDim2.fromOffset(0, STRIP_CLEAR)
			end
		end
	end
	local function cornerRow()
		local gui = backdrop:FindFirstAncestorWhichIsA("LayerCollector")
		local row = gui and gui:FindFirstChild("CornerIconRow", true)
		return row and row:IsA("GuiObject") and row or nil
	end
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		local row = cornerRow()
		if row then
			if backdrop.Visible then
				row.Visible = false
			elseif not (backdrop.Parent and backdrop.Parent:GetAttribute("BannerAtBottom")) then
				row.Visible = true -- Round Select (BannerAtBottom) keeps its own hide
			end
		end
		if backdrop.Visible then
			pcall(clearStrip)
			if current ~= id then previous, current = current, id end
			for tabId, b in pairs(buttons) do styleButton(b, tabId == id) end
		elseif current == id then
			current = nil
		end
	end)
end

return PanelTabs
