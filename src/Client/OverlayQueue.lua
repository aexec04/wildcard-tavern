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
local ToastRules = require(Engine:WaitForChild("CornerToastRules"))
local ClientSettings = require(script.Parent.ClientSettings)
local HudKit = require(Engine:WaitForChild("HudKit"))
local HudTheme = require(script.Parent.HudTheme)

local OverlayQueue = {}

local PARCHMENT = Color3.fromRGB(46, 34, 24)
local BRASS = Color3.fromRGB(200, 160, 84)
local CREAM = Color3.fromRGB(250, 238, 212)
local GOLD_TEXT = Color3.fromRGB(255, 214, 130)
local INK = Color3.fromRGB(52, 34, 18) -- text on the painted parchment
local INK_TITLE = Color3.fromRGB(104, 54, 12)
local SETTLE = 0.3 -- seconds to wait for sibling items so the priority order holds

local q = Rules.new()
local gui, backdrop, plate, title, body, button, rowsHolder, iconArt, plateStroke, plateCorner, platePad, plateLimit, customHolder
local token = 0
local activeItem
local pressCurrent -- what Escape does for the plate on screen: its button, or just closing it (Client/PopupDismiss)
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
	-- Escape presses the plate's Continue (or closes a notice) via Client/PopupDismiss, policy "button".
	require(script.Parent.PopupDismiss).attach(backdrop, { policy = "button", press = function() if pressCurrent then pressCurrent() end end, button = true })

	plate = Instance.new("ImageLabel") -- Image is the kit plate when the set has one, else the parchment fill shows
	plate.Name = "Plate"
	plate.ScaleType = Enum.ScaleType.Stretch
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.BackgroundColor3 = PARCHMENT
	plate.BackgroundTransparency = 0
	plate.Active = true
	plate.ZIndex = 151
	plate.Parent = backdrop
	plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 14)
	plateCorner.Parent = plate
	plateStroke = Instance.new("UIStroke")
	plateStroke.Color = BRASS
	plateStroke.Thickness = 3
	plateStroke.Parent = plate
	plateLimit = Instance.new("UISizeConstraint")
	plateLimit.MaxSize = Vector2.new(Rules.MAX_WIDTH, math.huge)
	plateLimit.Parent = plate

	platePad = Instance.new("UIPadding")
	platePad.PaddingTop, platePad.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18)
	platePad.PaddingLeft, platePad.PaddingRight = UDim.new(0, 20), UDim.new(0, 20)
	platePad.Parent = plate
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center -- text-only plates sit in the middle of the parchment, not at its top edge
	list.Padding = UDim.new(0, 8)
	list.Parent = plate

	iconArt = Instance.new("ImageLabel") -- painted icon (item.artId or a kit icon), never an emoji
	iconArt.Name = "IconArt"
	iconArt.LayoutOrder = 1
	iconArt.Size = UDim2.fromOffset(56, 56)
	iconArt.BackgroundTransparency = 1
	iconArt.ScaleType = Enum.ScaleType.Fit
	iconArt.Visible = false
	iconArt.ZIndex = 152
	iconArt.Parent = plate
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

	customHolder = Instance.new("Frame") -- item.custom(holder, painted) builds extra content here (the daily ladder)
	customHolder.Name = "Custom"
	customHolder.BackgroundTransparency = 1
	customHolder.LayoutOrder = 5
	customHolder.Size = UDim2.new(1, 0, 0, 0)
	customHolder.Visible = false
	customHolder.ZIndex = 152
	customHolder.Parent = plate

	button = Instance.new("TextButton")
	button.Name = "Continue"
	button.LayoutOrder = 6
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
	local closed = activeItem
	activeItem = nil
	pressCurrent = nil
	if closed and closed.onClose then pcall(closed.onClose) end
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

-- Dress the plate for the equipped Card Set: kit plate art with dark ink on its parchment, or the dark code-drawn plate.
local function dress(kitId)
	local painted = kitId ~= nil
	plate.Image = kitId or ""
	plate.BackgroundTransparency = painted and 1 or 0
	plateStroke.Enabled = not painted
	plateCorner.CornerRadius = UDim.new(0, painted and 0 or 14)
	local k = Rules.KIT_PAD
	platePad.PaddingTop, platePad.PaddingBottom = UDim.new(0, painted and k.top or 18), UDim.new(0, painted and k.bottom or 18)
	platePad.PaddingLeft, platePad.PaddingRight = UDim.new(0, painted and k.x or 20), UDim.new(0, painted and k.x or 20)
	plateLimit.MinSize = Vector2.new(0, painted and k.minH or 0)
	title.TextColor3 = painted and INK_TITLE or GOLD_TEXT
	body.TextColor3 = painted and INK or CREAM
	for _, c in ipairs(rowsHolder:GetChildren()) do
		if c:IsA("TextLabel") then c.TextColor3 = painted and INK or CREAM end
	end
end

local function show(item)
	if not backdrop then build() end
	token += 1
	local mine = token
	local setId = HudTheme.setId()
	local kitId = setId and HudKit.piece(setId, Rules.KIT_PLATE) or nil
	local iconId = type(item.artId) == "string" and item.artId ~= "" and item.artId or nil
	if not iconId and setId then
		local piece = Rules.iconPiece(item.icon)
		iconId = piece and HudKit.piece(setId, piece) or nil
	end
	iconArt.Visible = iconId ~= nil
	iconArt.Image = iconId or ""
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
		local isTable = type(r) == "table"
		row.Text = isTable and r.text or r
		if isTable and r.total then
			row.TextSize = 24
			row.Font = Enum.Font.GothamBold
		end
		if isTable and (item.stagger or 0) > 0 and not calm() then
			row.TextTransparency, row.TextStrokeTransparency = 1, 1
			task.delay(item.stagger * (i - 1), function()
				if token ~= mine or not row.Parent then return end
				TweenService:Create(row, TweenInfo.new(0.2), { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
			end)
		end
	end
	button.Visible = item.button ~= nil
	if item.button then
		button.Text = type(item.button) == "string" and item.button or "Continue"
	end
	for _, c in ipairs(customHolder:GetChildren()) do c:Destroy() end
	customHolder.Visible = type(item.custom) == "function"
	customHolder.Size = UDim2.new(1, 0, 0, type(item.customHeight) == "number" and item.customHeight or 0)
	dress(kitId)
	activeItem = item
	if customHolder.Visible then pcall(item.custom, customHolder, kitId ~= nil) end
	plate.Size = UDim2.new(1, -2 * Rules.MIN_EDGE, 0, 0)
	plate.AutomaticSize = Enum.AutomaticSize.Y
	-- the big Round Complete plate (the Night cleared headline, Tag rewards) is at most 55 percent of the screen width
	plateLimit.MaxSize = Vector2.new(Rules.plateMaxWidth(item.id, gui and gui.AbsoluteSize.X or 0), math.huge)
	backdrop.Visible = true
	if item.sound then pcall(function() require(script.Parent.Cue).play(item.sound, 2) end) end
	if not calm() then
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.15), { BackgroundTransparency = 0.45 }):Play()
	end
	local function dismiss() close(mine) end
	pressCurrent = dismiss -- Escape closes a pure toast
	if item.button then
		local conn
		conn = button.Activated:Once(function()
			if item.onButton then pcall(item.onButton) end
			dismiss()
		end)
		-- Escape presses the plate's one button (Continue); the pending click handler is dropped so it cannot fire again on a later plate
		pressCurrent = function()
			if conn then conn:Disconnect() end
			if item.onButton and not item.escapeDismisses then pcall(item.onButton) end -- the daily reward: Escape is Not now, never Claim
			dismiss()
		end
		local secs = Rules.autoSeconds(item)
		if secs then task.delay(secs, dismiss) end
		-- a click anywhere (the dark area or the plate) closes the Round Complete plate; nothing stays blocked behind it
		if item.id == "roundComplete" then
			local function anywhere(input)
				if token == mine and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
					if pressCurrent then pressCurrent() end
				end
			end
			backdrop.InputBegan:Once(anywhere)
			plate.InputBegan:Once(anywhere)
		end
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

-- A plate never opens over the Round Select cards or the first Patron and blessing cards: while one of those screens is up (and
-- really on screen, not just flagged visible under a hidden Menu) the plate waits and is looked at again until it is gone.
local function screenBlocksPlates()
	if not gui then return false end
	local function up(inst)
		while inst and inst:IsA("GuiObject") do
			if not inst.Visible then return false end
			inst = inst.Parent
		end
		return inst ~= nil
	end
	local choice = gui:FindFirstChild("ChoiceBackdrop")
	if choice and up(choice) then return true end
	local roundSelect = gui:FindFirstChild("RoundSelect", true)
	return roundSelect ~= nil and up(roundSelect)
end

local function startIfIdle()
	if q:current() then return end
	if screenBlocksPlates() then
		if not flushScheduled then
			flushScheduled = true
			task.delay(0.3, function()
				flushScheduled = false
				startIfIdle()
			end)
		end
		return
	end
	local nextItem = q:advance()
	if nextItem then flush(nextItem) end
end

function OverlayQueue.init(screenGui)
	gui = screenGui
	pcall(function() require(script.Parent.CornerToast).init(screenGui) end)
end

-- Every item is a corner toast unless it says plate = true: only the daily reward and Round Complete are plates.
function OverlayQueue.enqueue(item)
	if not gui then return false end
	if ToastRules.styleOf(item) == "toast" then
		local okToast, taken = pcall(function() return require(script.Parent.CornerToast).show(item) end)
		return okToast and taken == true
	end
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

-- Close the visible plate when it is the item with this id (e.g. the daily reward was claimed elsewhere).
function OverlayQueue.closeIfCurrent(id)
	if activeItem and activeItem.id == id then
		task.spawn(close, token)
	end
end

function OverlayQueue.newRound()
	q:newRound()
	pcall(function() require(script.Parent.CornerToast).newRound() end)
end

OverlayQueue.rules = Rules

return OverlayQueue
