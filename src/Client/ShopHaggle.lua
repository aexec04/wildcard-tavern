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
local ScrollLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ScrollOfferLayout"))
local ContentArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
local ImageSpace = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ImageSpace"))
local ClientSettings = require(script.Parent.ClientSettings)
local ShopTrace = require(script.Parent.ShopTrace)

local ShopHaggle = {}

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(86, 56, 30)
local GREEN = Color3.fromRGB(86, 140, 70)
local CURSE = Color3.fromRGB(130, 40, 30)
local Z = 60 -- ZIndexBehavior is Global: above every card, price tag and tilted body (ShopCards uses 6 to 10, ShopScene tokens 10)

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
	pcall(function() require(script.Parent.TavernKit).paintedButton(haggleButton, "secondary") end)

	-- Item chooser.
	local chooser = Instance.new("Frame")
	chooser.Name = "HaggleChooser"
	chooser.AnchorPoint = Vector2.new(0.5, 0.5)
	chooser.Position = UDim2.fromScale(0.5, 0.5)
	chooser.Size = UDim2.fromOffset(420, 164)
	chooser.BackgroundColor3 = PARCHMENT
	chooser.BackgroundTransparency = 0 -- opaque: nothing behind may show through
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
	chooserList.Size = UDim2.new(1, -20, 0, 60)
	chooserList.ZIndex = Z
	chooserList.Parent = chooser
	local chooserLayout = Instance.new("UIListLayout")
	chooserLayout.FillDirection = Enum.FillDirection.Horizontal
	chooserLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chooserLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chooserLayout.Padding = UDim.new(0, 8)
	chooserLayout.Parent = chooserList

	-- Cancel (text button under the items), plus a dim click-catcher behind the plate: both close the chooser.
	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "HaggleCancel"
	cancelButton.AnchorPoint = Vector2.new(0.5, 1)
	cancelButton.Position = UDim2.new(0.5, 0, 1, -8)
	cancelButton.Size = UDim2.fromOffset(110, 34)
	cancelButton.BackgroundTransparency = 1
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.TextSize = 16
	cancelButton.TextColor3 = INK
	cancelButton.TextTransparency = 0
	cancelButton.TextStrokeTransparency = 1
	cancelButton.Text = "Cancel"
	cancelButton.ZIndex = Z + 1
	cancelButton.Parent = chooser
	local dim = Instance.new("TextButton")
	dim.Name = "HaggleDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.6
	dim.BorderSizePixel = 0
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.ZIndex = Z - 1
	dim.Visible = false
	dim.Parent = shopFrame
	chooser:GetPropertyChangedSignal("Visible"):Connect(function()
		dim.Visible = chooser.Visible
	end)
	cancelButton.MouseButton1Click:Connect(function()
		playClickSfx()
		chooser.Visible = false
	end)
	dim.MouseButton1Click:Connect(function()
		chooser.Visible = false
	end)
	-- Escape and the click on the dim area go through the one shared PopupDismiss (panel = the plate, so a click on it is not outside).
	pcall(function()
		require(script.Parent.PopupDismiss).attach(dim, {
			panel = chooser,
			close = function() chooser.Visible = false end,
			policy = "dismiss",
			button = true,
		})
	end)

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

	-- The Stranger's offer as a tavern SCROLL (shop_offer_scroll_a, or _b for a harsh offer): the painted picture is the card, with the
	-- Stranger in a brass ringed medallion at the top, the title, the blessing and the curse in dark ink on the paper, and Accept and
	-- No thanks as wooden plates above the seal. Every rect comes from the tested Engine/ScrollOfferLayout (mapped from the picture, so
	-- text never touches the rods or the seal). Without the art ids, or in a window too small for 15 px text, the flat card above shows.
	local SCROLL_INK = Color3.fromRGB(60, 40, 22)
	local scrollRoot = Instance.new("Frame")
	scrollRoot.Name = "StrangerScroll"
	-- centred low so Marlo (left) and the cards stay visible around it; sized at 0.8 of the old maximum
	scrollRoot.AnchorPoint = Vector2.new(0.5, 1)
	scrollRoot.Position = UDim2.new(0.5, 0, 1, -24)
	scrollRoot.BackgroundTransparency = 1
	scrollRoot.Active = true -- sinks clicks on the paper
	scrollRoot.ZIndex = Z
	scrollRoot.Visible = false
	scrollRoot.Parent = shopFrame
	local scrollScale = Instance.new("UIScale")
	scrollScale.Parent = scrollRoot
	local scrollShadow = Instance.new("Frame") -- a soft shadow under the sheet
	scrollShadow.Name = "Shadow"
	scrollShadow.BackgroundColor3 = Color3.new(0, 0, 0)
	scrollShadow.BackgroundTransparency = 0.78
	scrollShadow.BorderSizePixel = 0
	scrollShadow.Active = false
	scrollShadow.ZIndex = Z
	scrollShadow.Parent = scrollRoot
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 18)
	shadowCorner.Parent = scrollShadow
	local scrollImage = Instance.new("ImageLabel")
	scrollImage.Name = "ScrollPicture"
	scrollImage.BackgroundTransparency = 1
	scrollImage.BorderSizePixel = 0
	scrollImage.Active = false
	scrollImage.ScaleType = Enum.ScaleType.Crop -- the card is the art's own box, cropped out of the transparent canvas
	scrollImage.ZIndex = Z + 1
	scrollImage.Parent = scrollRoot
	local medallion = Instance.new("Frame")
	medallion.Name = "StrangerMedallion"
	medallion.BackgroundColor3 = Color3.fromRGB(86, 56, 30)
	medallion.BorderSizePixel = 0
	medallion.ZIndex = Z + 2
	medallion.Parent = scrollRoot
	local medallionCorner = Instance.new("UICorner")
	medallionCorner.CornerRadius = UDim.new(0.5, 0)
	medallionCorner.Parent = medallion
	local medallionRing = Instance.new("UIStroke")
	medallionRing.Color = Color3.fromRGB(200, 160, 84)
	medallionRing.Thickness = 3
	medallionRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	medallionRing.Parent = medallion
	local medallionPortrait = Instance.new("ImageLabel") -- the Stranger's portrait when the art exists (shop_stranger), else the offer icon
	medallionPortrait.Name = "Portrait"
	medallionPortrait.BackgroundTransparency = 1
	medallionPortrait.BorderSizePixel = 0
	medallionPortrait.Size = UDim2.fromScale(1, 1)
	medallionPortrait.ScaleType = Enum.ScaleType.Crop
	medallionPortrait.ZIndex = Z + 3
	medallionPortrait.Visible = false
	medallionPortrait.Parent = medallion
	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(0.5, 0)
	portraitCorner.Parent = medallionPortrait
	local medallionIcon = label(medallion, { size = 36, color = CREAM })
	medallionIcon.ZIndex = Z + 3
	medallionIcon.TextWrapped = false
	local scrollTitle = label(scrollRoot, { size = ScrollLayout.TEXT_TITLE, color = SCROLL_INK, font = Enum.Font.Garamond })
	scrollTitle.Name = "OfferTitle"
	scrollTitle.ZIndex = Z + 2
	local scrollBless = label(scrollRoot, { size = ScrollLayout.TEXT_BODY, color = Color3.fromRGB(34, 84, 40) })
	scrollBless.Name = "OfferBlessing"
	scrollBless.ZIndex = Z + 2
	local scrollCurse = label(scrollRoot, { size = ScrollLayout.TEXT_BODY, color = Color3.fromRGB(130, 38, 30) })
	scrollCurse.Name = "OfferCurse"
	scrollCurse.ZIndex = Z + 2
	local ACCEPT_GREEN = Color3.fromRGB(70, 120, 60)
	local scrollAccept = button(scrollRoot, "Accept", ACCEPT_GREEN, UDim2.fromOffset(100, 36))
	scrollAccept.Name = "Accept"
	scrollAccept.TextSize = ScrollLayout.TEXT_BUTTON
	scrollAccept.TextWrapped = false
	scrollAccept.ZIndex = Z + 3
	local scrollDecline = button(scrollRoot, "No thanks", WOOD, UDim2.fromOffset(100, 36))
	scrollDecline.Name = "NoThanks"
	scrollDecline.TextSize = ScrollLayout.TEXT_BUTTON
	scrollDecline.TextWrapped = false
	-- wooden plates like every other button (polishButton adds the set skin plate and caps); Accept keeps a green tint
	if deps.polishButton then
		for _, b in ipairs({ scrollAccept, scrollDecline }) do
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then stroke:Destroy() end
			pcall(deps.polishButton, b, 10)
		end
	end
	scrollDecline.ZIndex = Z + 3
	local scrollMode = nil -- the layout in use while a scroll is showing
	local function box(inst, r)
		inst.Position = UDim2.fromOffset(r.x, r.y)
		inst.Size = UDim2.fromOffset(r.w, r.h)
	end
	local function scrollArt(key)
		return ContentArt.getImageId("shop_scene", "shop_offer_scroll_" .. key)
	end
	local function showScroll(s, state)
		local key = ScrollLayout.pick(s)
		local id = scrollArt(key) or scrollArt(key == "a" and "b" or "a")
		local size = shopFrame.AbsoluteSize
		local maxW, maxH = math.min(size.X - 32, 620), math.min(0.8 * size.Y, 760)
			-- 0.8 of the old size when that still reads (15 px text), else the full size
			local r = id and size.X > 0 and (ScrollLayout.layout(key, maxW * 0.8, maxH * 0.8) or ScrollLayout.layout(key, maxW, maxH)) or nil
		if not r then
			scrollRoot.Visible = false
			scrollMode = nil
			return false
		end
		local newKey = scrollMode == nil or scrollMode.key ~= r.key or scrollMode.w ~= r.w
		scrollMode = r
		scrollRoot.Size = UDim2.fromOffset(r.w, r.h)
		scrollImage.Image = id
		-- the art's box inside the 1024 x 1536 canvas: the crop that removes the empty margin (Roblox keeps a 1536 px side at 1024)
		local a = ScrollLayout.ART[r.key]
		local ix, iy, iw, ih = ImageSpace.rect(a.x, a.y, a.w, a.h, 1024, 1536)
		scrollImage.ImageRectOffset = Vector2.new(ix, iy)
		scrollImage.ImageRectSize = Vector2.new(iw, ih)
		scrollImage.ScaleType = Enum.ScaleType.Stretch
		box(scrollImage, { x = 0, y = 0, w = r.w, h = r.h })
		box(scrollShadow, { x = 6, y = 10, w = r.w - 12, h = r.h - 14 })
		box(medallion, r.medallion)
		local portrait = ContentArt.getImageId("shop", "shop_stranger")
		medallionPortrait.Image = portrait or ""
		medallionPortrait.Visible = portrait ~= nil
		medallionIcon.Text = portrait and "" or (s.icon or "?")
		box(scrollTitle, r.title)
		box(scrollBless, r.blessing)
		box(scrollCurse, r.curse)
		box(scrollAccept, r.accept)
		box(scrollDecline, r.decline)
		scrollTitle.Text = string.format("%s (%d Tips)", s.name or "", s.price or 0)
		scrollBless.Text = "Blessing: " .. tostring(s.blessing)
		scrollCurse.Text = "Curse: " .. tostring(s.curse)
		scrollAccept.Active = (state.tips or 0) >= (s.price or 0)
		scrollAccept.BackgroundColor3 = scrollAccept.Active and ACCEPT_GREEN or Color3.fromRGB(110, 110, 100)
		if not scrollRoot.Visible then
			scrollRoot.Visible = true
			if newKey and ClientSettings.get("reduceShake") ~= true and ClientSettings.get("animSpeed") ~= "fast" then
				-- unrolls with a quick 0.25 s scale and fade (none in calm mode)
				scrollScale.Scale = 0.9
				scrollImage.ImageTransparency = 1
				local ts = game:GetService("TweenService")
				ts:Create(scrollScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				ts:Create(scrollImage, TweenInfo.new(0.25), { ImageTransparency = 0 }):Play()
			else
				scrollScale.Scale = 1
				scrollImage.ImageTransparency = 0
			end
		end
		return true
	end

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
	scrollAccept.MouseButton1Click:Connect(function()
		if not scrollAccept.Active then return end
		playClickSfx()
		fire("Stranger", "accept")
	end)
	scrollDecline.MouseButton1Click:Connect(function()
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
		chooser.Size = UDim2.fromOffset(math.max(260, order * 128 + 12), 164)
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
		-- the scroll when the art and the window allow it, else the flat card
		local scrolled = s ~= nil and showScroll(s, state)
		if not s then
			scrollRoot.Visible = false
		end
		card.Visible = s ~= nil and not scrolled
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
