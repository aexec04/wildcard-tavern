--[[
	Client/ShopHaggle.lua
	The Counter's two extra interactions, drawn from the state payload (the server decides everything):
	  * Haggle: a button beside Marlo. It lists the Patron and Pack offers, you pick one, a 3 second needle bar
	    opens and Stop (or the bar timing out) asks the server to read its own clock. The picture of the needle is
	    only measured from the moment the state arrived. Not drawn on ranked boards and in the tutorial; after the one
	    haggle of a visit it stays and reads "Haggled", and while a pack is open it is dimmed. A click that cannot open the
	    chooser says why in Marlo's bubble and on the Counter (Engine/ShopRefusal), never nothing.
	  * The Wandering Stranger: a parchment card with one Dealer's Bargain, its blessing and its curse written
	    plainly, a price, Accept and No thanks. Declining is free.
	Remotes: Haggle (action, kind, id) and Stranger (action). Text is 15px or larger.

	ShopHaggle.new({ shopFrame, playClickSfx, say }) -> { update = function(state) }
	`say(text)` shows a line in Marlo's speech bubble.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ShopRefusal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ShopRefusal"))
local ShopTrace = require(script.Parent.ShopTrace)

local ShopHaggle = {}

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(86, 56, 30)
local GREEN = Color3.fromRGB(86, 140, 70)
local CURSE = Color3.fromRGB(130, 40, 30)
local Z = 9

local function remote(name)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	return folder and folder:FindFirstChild(name)
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.font or Enum.Font.GothamBold
	l.TextSize = props.size or 16
	l.TextColor3 = props.color or INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextWrapped = true
	l.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Text = props.text or ""
	l.Size = props.sizeUdim or UDim2.fromScale(1, 1)
	l.Position = props.position or UDim2.new()
	l.ZIndex = Z + 1
	l.Parent = parent
	return l
end

local function button(parent, text, color, size, position)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = CREAM
	b.TextTransparency = 0
	b.TextStrokeTransparency = 1 -- crisp: a stroke made the letters look squeezed together
	b.Text = text
	b.Size = size
	b.Position = position or UDim2.new()
	b.ZIndex = Z + 1
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	return b
end

function ShopHaggle.new(deps)
	local shopFrame = deps.shopFrame
	local say = deps.say or function() end
	local playClickSfx = deps.playClickSfx or function() end
	local self = {}

	-- Haggle button beside Marlo (left of his portrait).
	local haggleButton = button(shopFrame, "Haggle", WOOD, UDim2.fromOffset(120, 40), UDim2.new(1, -140, 1, -72))
	haggleButton.Name = "HaggleButton"
	haggleButton.AnchorPoint = Vector2.new(1, 1)
	haggleButton.Visible = false

	-- Item chooser.
	local chooser = Instance.new("Frame")
	chooser.Name = "HaggleChooser"
	chooser.AnchorPoint = Vector2.new(0.5, 0.5)
	chooser.Position = UDim2.fromScale(0.5, 0.5)
	chooser.Size = UDim2.fromOffset(420, 120)
	chooser.BackgroundColor3 = PARCHMENT
	chooser.ZIndex = Z
	chooser.Visible = false
	chooser.Parent = shopFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = chooser
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(110, 76, 40)
		s.Thickness = 2
		s.Parent = chooser
	end
	local chooserTitle = label(chooser, { text = "Haggle for which item?", size = 18, sizeUdim = UDim2.new(1, 0, 0, 30), position = UDim2.fromOffset(0, 6) })
	local chooserList = Instance.new("Frame")
	chooserList.BackgroundTransparency = 1
	chooserList.Position = UDim2.fromOffset(10, 40)
	chooserList.Size = UDim2.new(1, -20, 1, -50)
	chooserList.ZIndex = Z
	chooserList.Parent = chooser
	local chooserLayout = Instance.new("UIListLayout")
	chooserLayout.FillDirection = Enum.FillDirection.Horizontal
	chooserLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chooserLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chooserLayout.Padding = UDim.new(0, 8)
	chooserLayout.Parent = chooserList

	-- Timing bar.
	local bar = Instance.new("Frame")
	bar.Name = "HaggleBar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromOffset(420, 130)
	bar.BackgroundColor3 = PARCHMENT
	bar.ZIndex = Z
	bar.Visible = false
	bar.Parent = shopFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = bar
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(110, 76, 40)
		s.Thickness = 2
		s.Parent = bar
	end
	local barTitle = label(bar, { text = "Stop in the green!", size = 18, sizeUdim = UDim2.new(1, 0, 0, 30), position = UDim2.fromOffset(0, 6) })
	local track = Instance.new("Frame")
	track.BackgroundColor3 = Color3.fromRGB(120, 90, 60)
	track.BorderSizePixel = 0
	track.Position = UDim2.fromOffset(20, 44)
	track.Size = UDim2.new(1, -40, 0, 26)
	track.ZIndex = Z
	track.Parent = bar
	local zone = Instance.new("Frame")
	zone.BackgroundColor3 = GREEN
	zone.BorderSizePixel = 0
	zone.AnchorPoint = Vector2.new(0.5, 0)
	zone.Size = UDim2.fromScale(70 / 360, 1)
	zone.Position = UDim2.fromScale(0.5, 0)
	zone.ZIndex = Z + 1
	zone.Parent = track
	local needle = Instance.new("Frame")
	needle.BackgroundColor3 = CREAM
	needle.BorderSizePixel = 0
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Size = UDim2.new(0, 5, 1, 12)
	needle.Position = UDim2.fromScale(0, 0.5)
	needle.ZIndex = Z + 2
	needle.Parent = track
	local stopButton = button(bar, "Stop", GREEN, UDim2.fromOffset(120, 40), UDim2.new(0.5, -60, 1, -50))

	-- Wandering Stranger card (bottom left, above the footer).
	local card = Instance.new("Frame")
	card.Name = "StrangerCard"
	card.AnchorPoint = Vector2.new(0, 1)
	card.Position = UDim2.new(0, 16, 1, -72)
	card.Size = UDim2.fromOffset(280, 190)
	card.BackgroundColor3 = PARCHMENT
	card.ZIndex = Z
	card.Visible = false
	card.Parent = shopFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = card
		local s = Instance.new("UIStroke")
		s.Color = GOLD
		s.Thickness = 2.5
		s.Parent = card
	end
	pcall(function() -- the Stranger peeks over the top right of the card once shop_stranger has a resolved Image id
		local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
		local id = ContentArt.getImageId("shop", "shop_stranger")
		if id then
			local img = Instance.new("ImageLabel")
			img.Name = "StrangerPortrait"
			img.AnchorPoint = Vector2.new(1, 1)
			img.Position = UDim2.new(1, -8, 0, 10)
			img.Size = UDim2.fromOffset(76, 76)
			img.BackgroundTransparency = 1
			img.Image = id
			img.ScaleType = Enum.ScaleType.Fit
			img.Active = false
			img.ZIndex = Z + 1
			img.Parent = card
		end
	end)
	local cardName = label(card, { size = 18, sizeUdim = UDim2.new(1, -12, 0, 26), position = UDim2.fromOffset(6, 4) })
	local cardBless = label(card, { size = 15, color = Color3.fromRGB(40, 90, 40), sizeUdim = UDim2.new(1, -16, 0, 40), position = UDim2.fromOffset(8, 32) })
	local cardCurse = label(card, { size = 15, color = CURSE, sizeUdim = UDim2.new(1, -16, 0, 40), position = UDim2.fromOffset(8, 74) })
	local acceptButton = button(card, "Accept", GREEN, UDim2.fromOffset(120, 36), UDim2.new(0, 10, 1, -46))
	local declineButton = button(card, "No thanks", WOOD, UDim2.fromOffset(120, 36), UDim2.new(1, -130, 1, -46))

	local view = { haggle = nil }
	local barConn, barToken = nil, 0

	local function closeBar()
		barToken += 1
		if barConn then
			barConn:Disconnect()
			barConn = nil
		end
		bar.Visible = false
	end

	local function fire(name, ...)
		local r = remote(name)
		if r then
			r:FireServer(...)
		end
	end

	local function openBar(h)
		if bar.Visible then
			return
		end
		bar.Visible = true
		chooser.Visible = false
		barToken += 1
		local token = barToken
		local t0 = os.clock()
		local speed, duration = h.speed or 240, h.duration or 3
		barConn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			local p = (t * speed) % 720
			local angle = p <= 360 and p or (720 - p)
			needle.Position = UDim2.fromScale(angle / 360, 0.5)
			if t > duration and token == barToken then
				closeBar()
				fire("Haggle", "stop")
			end
		end)
	end

	stopButton.MouseButton1Click:Connect(function()
		playClickSfx()
		closeBar()
		fire("Haggle", "stop")
	end)

	haggleButton.MouseButton1Click:Connect(function()
		playClickSfx()
		local denied = ShopRefusal.haggleDenied(view.haggle)
		ShopTrace.log("Haggle clicked: %s", denied or "chooser toggled")
		if denied then
			chooser.Visible = false
			say(denied)
			if deps.warn then deps.warn(denied) end
			return
		end
		chooser.Visible = not chooser.Visible
	end)

	acceptButton.MouseButton1Click:Connect(function()
		playClickSfx()
		fire("Stranger", "accept")
	end)
	declineButton.MouseButton1Click:Connect(function()
		playClickSfx()
		fire("Stranger", "decline")
	end)

	local lastShown = nil -- the last result line, so it is said once
	local function fillChooser(state)
		for _, child in ipairs(chooserList:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		local function add(kind, item)
			order += 1
			local b = button(chooserList, string.format("%s\n%d Tips", item.name or item.id, item.price or 0), WOOD, UDim2.fromOffset(120, 56))
			b.TextWrapped = true
			b.TextSize = 15
			b.LayoutOrder = order
			b.MouseButton1Click:Connect(function()
				playClickSfx()
				chooser.Visible = false
				fire("Haggle", "start", kind, item.id)
			end)
		end
		for _, offer in ipairs(state.shopOffers or {}) do
			add("patron", offer)
		end
		for _, pack in ipairs(state.packOffers or {}) do
			add("pack", pack)
		end
		chooser.Size = UDim2.fromOffset(math.max(260, order * 128 + 12), 120)
	end

	-- Called from rebuildShop on every render while the shop is open.
	function self.update(state)
		local h = state and state.haggle
		view.haggle = h
		-- Not drawn on ranked boards and in the tutorial; otherwise it stays: "Haggle", or "Haggled" once the visit's haggle is used,
		-- dimmed while it cannot be used (the label is the stage's gold tag, or the button's own text without the stage).
		haggleButton.Visible = h ~= nil and (h.available == true or not ShopRefusal.hiddenCodes[h.reason])
		local label = ShopRefusal.haggleLabel(h)
		haggleButton:SetAttribute("Label", label)
		local tagLabel = haggleButton:FindFirstChild("HaggleTag")
		local dim = (h and h.available) and 0 or 0.4
		if tagLabel then
			tagLabel.Text = label
			tagLabel.BackgroundTransparency = dim
		else
			haggleButton.Text = label
			haggleButton.BackgroundTransparency = dim
		end
		if not (h and h.available) then
			chooser.Visible = false
		else
			fillChooser(state)
		end
		if h and h.open then
			openBar(h)
		elseif bar.Visible then
			closeBar()
		end
		if h and h.used and h.delta and lastShown ~= tostring(h.id) .. h.delta then
			lastShown = tostring(h.id) .. h.delta
			say(h.delta < 0 and "Fair deal! One Tip off." or "Too slow! That costs one more.")
		elseif not (h and h.used) then
			lastShown = nil
		end

		local s = state and state.stranger
		card.Visible = s ~= nil
		if s then
			cardName.Text = string.format("%s %s (%d Tips)", s.icon or "", s.name or "", s.price or 0)
			cardBless.Text = "Blessing: " .. tostring(s.blessing)
			cardCurse.Text = "Curse: " .. tostring(s.curse)
			acceptButton.Active = (state.tips or 0) >= (s.price or 0)
			acceptButton.BackgroundColor3 = acceptButton.Active and GREEN or Color3.fromRGB(110, 110, 100)
		end
	end

	shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not shopFrame.Visible then
			closeBar()
			chooser.Visible = false
		end
	end)

	return self
end

return ShopHaggle
