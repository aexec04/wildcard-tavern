--[[
	Client/OverlayQueue.lua
	ONE calm queue for everything that pops up when a round ends (Round Complete, Unlocks, Rank up, quest toasts).
	Systems call OverlayQueue.enqueue({ id, priority, title, text, rows, icon, tab, artId, button, group }) instead of
	parenting their own frame. One solid dark parchment plate with a brass edge, centred, at most 520 px wide, at
	least 24 px from every edge, is shown at a time; the map behind is dimmed and inert (the backdrop is named
	"...Backdrop" so PopupShield and InputGuard treat it as a popup). Rules and order: Engine/OverlayQueueRules.

	OverlayQueue.init(screenGui)
	OverlayQueue.enqueue(item) -> bool
	OverlayQueue.isBusy() -> bool
	OverlayQueue.onIdle(key, fn)   run fn once when the queue is empty (keyed, a repeat replaces the earlier fn)
	OverlayQueue.newRound()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("OverlayQueueRules"))
local ClientSettings = require(script.Parent.ClientSettings)

local OverlayQueue = {}

local PARCHMENT = Color3.fromRGB(46, 34, 24)
local BRASS = Color3.fromRGB(200, 160, 84)
local CREAM = Color3.fromRGB(250, 238, 212)
local GOLD_TEXT = Color3.fromRGB(255, 214, 130)
local SETTLE = 0.3 -- seconds to wait for sibling items so the priority order holds

local q = Rules.new()
local gui, backdrop, plate, title, body, button, iconLabel, rowsHolder
local token = 0
local idleFns = {}
local idleOrder = {}
local flushScheduled = false

local function calm()
	return ClientSettings.get("animSpeed") == "fast" or ClientSettings.get("reduceShake") == true
end

local function label(parent, name, size, font, color, z)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextWrapped = true
	l.ZIndex = z
	l.Parent = parent
	return l
end

local function build()
	backdrop = Instance.new("Frame")
	backdrop.Name = "OverlayQueueBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 6, 4)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.Visible = false
	backdrop.ZIndex = 150
	backdrop.Parent = gui

	plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.BackgroundColor3 = PARCHMENT
	plate.BackgroundTransparency = 0
	plate.Active = true
	plate.ZIndex = 151
	plate.Parent = backdrop
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = BRASS
	stroke.Thickness = 3
	stroke.Parent = plate
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(Rules.MAX_WIDTH, math.huge)
	limit.Parent = plate

	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 20), UDim.new(0, 20)
	pad.Parent = plate
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.Parent = plate

	iconLabel = label(plate, "Icon", 34, Enum.Font.GothamBold, CREAM, 152)
	iconLabel.LayoutOrder = 1
	iconLabel.Size = UDim2.new(1, 0, 0, 40)
	title = label(plate, "Title", 22, Enum.Font.GothamBold, GOLD_TEXT, 152)
	title.LayoutOrder = 2
	title.Size = UDim2.new(1, 0, 0, 30)
	body = label(plate, "Body", 18, Enum.Font.GothamBold, CREAM, 152)
	body.LayoutOrder = 3
	body.Size = UDim2.new(1, 0, 0, 28)
	body.AutomaticSize = Enum.AutomaticSize.Y
	rowsHolder = Instance.new("Frame")
	rowsHolder.Name = "Rows"
	rowsHolder.BackgroundTransparency = 1
	rowsHolder.LayoutOrder = 4
	rowsHolder.Size = UDim2.new(1, 0, 0, 0)
	rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
	rowsHolder.ZIndex = 152
	rowsHolder.Parent = plate
	local rowList = Instance.new("UIListLayout")
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 4)
	rowList.Parent = rowsHolder

	button = Instance.new("TextButton")
	button.Name = "Continue"
	button.LayoutOrder = 5
	button.Size = UDim2.new(0, 180, 0, 40)
	button.BackgroundColor3 = BRASS
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(40, 28, 16)
	button.Text = "Continue"
	button.AutoButtonColor = true
	button.ZIndex = 153
	button.Parent = plate
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = button
end

local flush

local function close(mine)
	if mine ~= token then return end
	token += 1
	local fade = calm() and 0 or 0.15
	if backdrop then
		backdrop.Visible = false
	end
	if fade > 0 and plate then
		-- the backdrop is already hidden; the next plate (if any) opens after the fade gap
		task.wait(fade)
	end
	local nextItem = q:advance()
	if nextItem then
		flush(nextItem)
	else
		local fns = idleFns
		local order = idleOrder
		idleFns, idleOrder = {}, {}
		for _, key in ipairs(order) do
			local fn = fns[key]
			if fn then pcall(fn) end
		end
	end
end

local function show(item)
	if not backdrop then build() end
	token += 1
	local mine = token
	iconLabel.Text = item.icon or ""
	iconLabel.Visible = item.icon ~= nil and item.icon ~= ""
	title.Text = item.title or ""
	title.Visible = item.title ~= nil and item.title ~= ""
	body.Text = item.text or ""
	body.Visible = item.text ~= nil and item.text ~= ""
	for _, c in ipairs(rowsHolder:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for i, r in ipairs(item.rows or {}) do
		local row = label(rowsHolder, "Row" .. i, 17, Enum.Font.Gotham, CREAM, 152)
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 24)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Text = r
	end
	button.Visible = item.button ~= nil
	if item.button then
		button.Text = type(item.button) == "string" and item.button or "Continue"
	end
	plate.Size = UDim2.new(1, -2 * Rules.MIN_EDGE, 0, 0)
	plate.AutomaticSize = Enum.AutomaticSize.Y
	backdrop.Visible = true
	if item.sound then pcall(function() require(script.Parent.Cue).play(item.sound, 2) end) end
	if not calm() then
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.15), { BackgroundTransparency = 0.45 }):Play()
	end
	local function dismiss() close(mine) end
	if item.button then
		button.Activated:Once(dismiss)
	end
	-- a click anywhere on a pure toast closes it too; plates with a button close only from the button
	if not item.button then
		backdrop.InputBegan:Once(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dismiss()
			end
		end)
		local secs = Rules.autoSeconds(item)
		if secs then task.delay(secs, dismiss) end
	end
end

flush = function(item)
	show(item)
end

local function startIfIdle()
	if q:current() then return end
	local nextItem = q:advance()
	if nextItem then flush(nextItem) end
end

function OverlayQueue.init(screenGui)
	gui = screenGui
end

function OverlayQueue.enqueue(item)
	if not gui then return false end
	local ok = q:enqueue(item)
	if ok and not q:current() and not flushScheduled then
		flushScheduled = true
		task.delay(SETTLE, function()
			flushScheduled = false
			startIfIdle()
		end)
	end
	return ok
end

function OverlayQueue.isBusy()
	return q:isBusy()
end

function OverlayQueue.onIdle(key, fn)
	if not q:isBusy() then
		pcall(fn)
		return
	end
	if not idleFns[key] then idleOrder[#idleOrder + 1] = key end
	idleFns[key] = fn
end

function OverlayQueue.newRound()
	q:newRound()
end

OverlayQueue.rules = Rules

return OverlayQueue
