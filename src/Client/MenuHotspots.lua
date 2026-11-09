--[[
	Client/MenuHotspots.lua
	The Menu's painted objects ("hotspots", positions in Engine/MenuLayout.lua) and the carved wooden plaques.

	Every Menu action is ONE real TextButton made by newAction(). Other scripts (the hub, HowToPlay, Journey, RunSetup, the
	tutorial) connect their click handlers to those buttons, so they are never cloned or replaced, only moved between homes:
	  * a hotspot with one action: the button covers the hotspot like a transparent click surface; its plaque slides up on hover;
	  * a hotspot with several actions: the hotspot has its own surface, a click fans the action buttons out as plaques;
	  * the "All actions" list (and phones, which show only the list): every button as a plaque row.
	closeAll() docks every button back to its home. Plaque look: dark carved wood, brass corner studs, cream text.

	build{ menuFrame, layer, buttons, calm, onHover, tutorialRibbon } returns
	  { startLoops(), stopLoops(), entry(), applyViewport(w, h), closeAll(), hotspotFrames, animatedCount }
]]

local TweenService = game:GetService("TweenService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("MenuLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local Hotspots = {}

local WOOD = Color3.fromRGB(62, 42, 26)
local WOOD_LIGHT = Color3.fromRGB(96, 66, 38)
local BRASS = Color3.fromRGB(214, 172, 88)
local CREAM = Color3.fromRGB(250, 240, 220)
local CREAM_DIM = Color3.fromRGB(226, 208, 170)
local GLOW = Color3.fromRGB(255, 190, 90)

local Z_SCENE, Z_FAN, Z_LIST = 16, 32, 46

-- Sets the ZIndex of a button and everything inside it (children carry a ZOff attribute so the plaque stacks correctly).
local function applyZ(button, z)
	button.ZIndex = z
	for _, d in ipairs(button:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = z + (d:GetAttribute("ZOff") or 1)
		end
	end
end

local function off(instance, n)
	instance:SetAttribute("ZOff", n)
	return instance
end

local function newPlaque(parent)
	local plaque = Instance.new("Frame")
	plaque.Name = "Plaque"
	plaque.BackgroundColor3 = WOOD
	plaque.BorderSizePixel = 0
	plaque.Active = false
	plaque.Parent = parent
	off(plaque, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = plaque
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Rim"
	stroke.Color = BRASS
	stroke.Thickness = 2
	stroke.Parent = plaque
	for i = 1, 4 do -- brass corner studs
		local stud = Instance.new("Frame")
		stud.Name = "Stud"
		stud.AnchorPoint = Vector2.new((i % 2 == 1) and 0 or 1, (i <= 2) and 0 or 1)
		stud.Position = UDim2.new((i % 2 == 1) and 0 or 1, (i % 2 == 1) and 4 or -4, (i <= 2) and 0 or 1, (i <= 2) and 4 or -4)
		stud.Size = UDim2.fromOffset(6, 6)
		stud.BackgroundColor3 = BRASS
		stud.BorderSizePixel = 0
		stud.Active = false
		stud.Parent = plaque
		off(stud, 2)
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(1, 0)
		sc.Parent = stud
	end
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 18
	name.TextColor3 = CREAM
	name.TextTransparency = 0
	name.TextStrokeTransparency = 1
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Active = false
	name.Parent = plaque
	off(name, 3)
	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 14
	desc.TextColor3 = CREAM_DIM
	desc.TextTransparency = 0
	desc.TextStrokeTransparency = 1
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.Active = false
	desc.Parent = plaque
	off(desc, 3)
	return plaque, name, desc
end

-- One real, long-lived button per Menu action. `info` = { actionLabel, hotspotLabel, desc }.
function Hotspots.newAction(id, info)
	local button = Instance.new("TextButton")
	button.Name = "Action_" .. id
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(220, 44)
	button:SetAttribute("ActionId", id)
	button:SetAttribute("ActionLabel", info.actionLabel or id)
	button:SetAttribute("HotspotLabel", info.hotspotLabel or info.actionLabel or id)
	button:SetAttribute("Desc", info.desc or "")
	newPlaque(button)
	return button
end

-- mode "plaque": a fixed size wooden row (fan, list, inline). mode "surface": a transparent click area that fills its hotspot.
local function setMode(button, mode, z, size)
	local plaque = button:FindFirstChild("Plaque")
	local name, desc = plaque.Title, plaque.Desc
	button:SetAttribute("Mode", mode)
	name.TextSize = 18
	if mode == "plaque" then
		button.Size = size or UDim2.fromOffset(220, 44)
		button.Position = UDim2.new()
		button.AnchorPoint = Vector2.new(0, 0)
		plaque.Visible = true
		plaque.AnchorPoint = Vector2.new(0, 0)
		plaque.Position = UDim2.new()
		plaque.Size = UDim2.fromScale(1, 1)
		name.Text = button:GetAttribute("ActionLabel")
		name.Position = UDim2.fromOffset(10, 0)
		name.Size = UDim2.new(1, -20, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Center
		desc.Visible = false
	else
		button.Size = UDim2.fromScale(1, 1)
		button.Position = UDim2.new()
		button.AnchorPoint = Vector2.new(0, 0)
		plaque.Visible = false
		plaque.AnchorPoint = Vector2.new(0.5, 0)
		plaque.Position = UDim2.new(0.5, 0, 1, 10)
		plaque.Size = UDim2.fromOffset(230, 56)
		name.Text = button:GetAttribute("HotspotLabel")
		name.Position = UDim2.fromOffset(10, 3)
		name.Size = UDim2.new(1, -20, 0, 26)
		name.TextXAlignment = Enum.TextXAlignment.Center
		desc.Text = button:GetAttribute("Desc")
		desc.Position = UDim2.fromOffset(10, 29)
		desc.Size = UDim2.new(1, -20, 0, 22)
		desc.TextXAlignment = Enum.TextXAlignment.Center
		desc.Visible = true
	end
	applyZ(button, z)
end

function Hotspots.build(opts)
	local menuFrame, layer, buttons = opts.menuFrame, opts.layer, opts.buttons
	local calm = opts.calm
	local result = { hotspotFrames = {}, animatedCount = 0 }

	-- Hidden home for buttons that are not on screen right now.
	local stash = Instance.new("Frame")
	stash.Name = "ActionStash"
	stash.Visible = false
	stash.BackgroundTransparency = 1
	stash.Size = UDim2.fromOffset(1, 1)
	stash.Parent = menuFrame

	local state = { phone = false, openFan = nil, listOpen = false }
	local homes = {} -- actionId -> function(button) that puts it where it lives when nothing is open
	local fans = {} -- hotspotId -> Frame
	local lanterns = {} -- tweens for the primary sign
	local hotspotUI = {} -- hotspotId -> { frame, lift, rim }

	-- Click catcher behind open fans / the list: a click anywhere else closes them.
	local catcher = Instance.new("TextButton")
	catcher.Name = "FanCatcher"
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.Visible = false
	catcher.ZIndex = Z_FAN - 2
	catcher.Parent = menuFrame

	local list = Instance.new("ScrollingFrame")
	list.Name = "AllActions"
	list.BackgroundColor3 = Color3.fromRGB(30, 21, 14)
	list.BackgroundTransparency = 0.15
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = BRASS
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Visible = false
	list.ZIndex = Z_LIST - 1
	list.Parent = menuFrame
	do
		local lc = Instance.new("UICorner")
		lc.CornerRadius = UDim.new(0, 10)
		lc.Parent = list
		local ls = Instance.new("UIStroke")
		ls.Color = BRASS
		ls.Thickness = 2
		ls.Parent = list
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.Parent = list
		local ll = Instance.new("UIListLayout")
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Padding = UDim.new(0, 6)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.Parent = list
	end

	local function dock(id)
		local button = buttons[id]
		if not button then return end
		if state.phone then
			setMode(button, "plaque", Z_LIST)
			button.Parent = list
			return
		end
		local home = homes[id]
		if home then home(button) else
			setMode(button, "plaque", Z_FAN)
			button.Parent = stash
		end
	end

	local function closeAll()
		local wasOpen = state.openFan ~= nil or state.listOpen
		for _, fan in pairs(fans) do fan.Visible = false end
		state.openFan = nil
		if state.listOpen and not state.phone then
			state.listOpen = false
			list.Visible = false
		end
		catcher.Visible = false
		for _, action in ipairs(Layout.Actions) do dock(action.id) end
		return wasOpen
	end
	result.closeAll = closeAll
	catcher.MouseButton1Click:Connect(closeAll)

	local function fillList()
		for i, action in ipairs(Layout.Actions) do
			local button = buttons[action.id]
			if button then
				setMode(button, "plaque", Z_LIST)
				button.LayoutOrder = i
				button.Parent = list
			end
		end
	end

	local allButton = Instance.new("TextButton")
	allButton.Name = "AllActionsButton"
	allButton.AnchorPoint = Vector2.new(1, 1)
	allButton.Position = UDim2.new(1, -16, 1, -16)
	allButton.Size = UDim2.fromOffset(150, 38)
	allButton.AutoButtonColor = false
	allButton.BackgroundColor3 = WOOD
	allButton.Font = Enum.Font.GothamBold
	allButton.TextSize = 16
	allButton.TextColor3 = CREAM
	allButton.TextTransparency = 0
	allButton.TextStrokeTransparency = 1
	allButton.Text = "All actions"
	allButton.ZIndex = Z_LIST
	allButton.Parent = menuFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 7)
		c.Parent = allButton
		local s = Instance.new("UIStroke")
		s.Color = BRASS
		s.Thickness = 2
		s.Parent = allButton
	end
	allButton.MouseButton1Click:Connect(function()
		if state.listOpen then
			closeAll()
			return
		end
		closeAll()
		state.listOpen = true
		list.Visible = true
		catcher.Visible = true
		fillList()
	end)

	-- ===== Hotspot objects =====
	local function hover(hotspot, on)
		local ui = hotspotUI[hotspot.id]
		if not ui then return end
		TweenService:Create(ui.rim, TweenInfo.new(0.15), { Transparency = on and 0.1 or 0.7 }):Play()
		if not calm() then
			TweenService:Create(ui.lift, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = on and 1.04 or 1 }):Play()
		end
		local button = ui.surface
		local plaque = button and button:FindFirstChild("Plaque")
		if plaque and button:GetAttribute("Mode") == "surface" and not hotspot.lit then
			if on then
				plaque.Visible = true
				plaque.Position = UDim2.new(0.5, 0, 1, calm() and 10 or 24)
				if not calm() then
					TweenService:Create(plaque, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, 10) }):Play()
				end
			else
				plaque.Visible = false
			end
		end
		if opts.onHover then opts.onHover(on) end
	end

	local function openFanFor(hotspot)
		closeAll()
		local fan = fans[hotspot.id]
		if not fan then return end
		state.openFan = hotspot.id
		fan.Visible = true
		catcher.Visible = true
		for i, id in ipairs(hotspot.actions) do
			local button = buttons[id]
			if button then
				setMode(button, "plaque", Z_FAN)
				button.LayoutOrder = i
				button.Parent = fan
			end
		end
	end

	for _, hotspot in ipairs(Layout.Hotspots) do
		local frame = Instance.new("Frame")
		frame.Name = "Hotspot_" .. hotspot.id
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(hotspot.x, hotspot.y)
		frame.Size = UDim2.fromScale(1, hotspot.s)
		frame.BackgroundTransparency = 1
		frame.ZIndex = 13
		frame.Parent = layer
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = hotspot.asp
		aspect.Parent = frame
		result.hotspotFrames[hotspot.id] = frame

		-- The object: a soft wood medallion with the painted art, emoji until the art exists.
		local object = Instance.new("Frame")
		object.Name = "Object"
		object.AnchorPoint = Vector2.new(0.5, 0.5)
		object.Position = UDim2.fromScale(0.5, 0.5)
		object.Size = UDim2.fromScale(1, 1)
		object.BackgroundColor3 = Color3.fromRGB(44, 30, 20)
		object.BackgroundTransparency = 0.45
		object.BorderSizePixel = 0
		object.ZIndex = 14
		object.Parent = frame
		local oc = Instance.new("UICorner")
		oc.CornerRadius = UDim.new(0, 16)
		oc.Parent = object
		local rim = Instance.new("UIStroke")
		rim.Name = "Glow"
		rim.Color = GLOW
		rim.Thickness = hotspot.lit and 3 or 2
		rim.Transparency = 0.7
		rim.Parent = object
		local lift = Instance.new("UIScale")
		lift.Parent = object
		local artId = hotspot.art and ContentArt.getImageId("menu_icons", hotspot.art) or nil
		if artId then
			local img = Instance.new("ImageLabel")
			img.Name = "Art"
			img.Size = UDim2.fromScale(0.94, 0.94)
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.BackgroundTransparency = 1
			img.Image = artId
			img.ScaleType = Enum.ScaleType.Fit
			img.Active = false
			img.ZIndex = 15
			img.Parent = object
		else
			local glyph = Instance.new("TextLabel")
			glyph.Name = "Glyph"
			glyph.Size = UDim2.fromScale(0.8, 0.7)
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.46)
			glyph.BackgroundTransparency = 1
			glyph.Font = Enum.Font.Gotham
			glyph.TextScaled = true
			glyph.Text = hotspot.glyph
			glyph.TextTransparency = 0
			glyph.TextStrokeTransparency = 1
			glyph.Active = false
			glyph.ZIndex = 15
			glyph.Parent = object
		end
		local ui = { frame = frame, lift = lift, rim = rim }
		hotspotUI[hotspot.id] = ui

		if #hotspot.actions == 1 or hotspot.id == "play" then
			-- single action (Play too): the real button is the click surface
			local primary = buttons[hotspot.actions[1]]
			ui.surface = primary
			homes[hotspot.actions[1]] = function(button)
				setMode(button, "surface", Z_SCENE)
				button.Parent = frame
			end
			if hotspot.id == "play" then
				homes.newRun = function(button) -- the smaller New Run plaque sits under the sign
					setMode(button, "plaque", Z_SCENE + 2, UDim2.fromOffset(150, 34))
					button.AnchorPoint = Vector2.new(0.5, 1)
					button.Position = UDim2.new(0.5, 0, 1, -4)
					button:FindFirstChild("Plaque").Title.TextSize = 16
					button.Parent = frame
				end
			end
			if primary then
				primary.MouseEnter:Connect(function() hover(hotspot, true) end)
				primary.MouseLeave:Connect(function() hover(hotspot, false) end)
			end
		else
			-- several actions: own surface, a click fans the plaques out
			local surface = Instance.new("TextButton")
			surface.Name = "Surface"
			surface.Text = ""
			surface.BackgroundTransparency = 1
			surface.AutoButtonColor = false
			surface.Size = UDim2.fromScale(1, 1)
			surface.ZIndex = Z_SCENE
			surface.Parent = frame
			local plaque, name, desc = newPlaque(surface) -- hover plaque for the fan itself
			plaque.AnchorPoint = Vector2.new(0.5, 0)
			plaque.Position = UDim2.new(0.5, 0, 1, 10)
			plaque.Size = UDim2.fromOffset(230, 56)
			plaque.Visible = false
			name.Text = hotspot.label
			name.Position = UDim2.fromOffset(10, 3)
			name.Size = UDim2.new(1, -20, 0, 26)
			desc.Text = hotspot.desc
			desc.Position = UDim2.fromOffset(10, 29)
			desc.Size = UDim2.new(1, -20, 0, 22)
			applyZ(surface, Z_SCENE)
			surface:SetAttribute("Mode", "surface")
			ui.surface = surface
			surface.MouseEnter:Connect(function() hover(hotspot, true) end)
			surface.MouseLeave:Connect(function() hover(hotspot, false) end)
			surface.MouseButton1Click:Connect(function()
				if state.openFan == hotspot.id then closeAll() else openFanFor(hotspot) end
			end)
			for _, id in ipairs(hotspot.actions) do
				homes[id] = nil -- stays in the stash until the fan opens
			end
			local fan = Instance.new("Frame")
			fan.Name = "Fan_" .. hotspot.id
			fan.AnchorPoint = Vector2.new(hotspot.x < 0.3 and 0 or (hotspot.x > 0.7 and 1 or 0.5), hotspot.y < 0.6 and 0 or 1)
			local below = hotspot.y < 0.6
			fan.Position = UDim2.new(hotspot.x, 0, hotspot.y + (below and hotspot.s / 2 or -hotspot.s / 2), below and 12 or -12)
			fan.Size = UDim2.fromOffset(236, #hotspot.actions * 50 + 8)
			fan.BackgroundTransparency = 1
			fan.Visible = false
			fan.ZIndex = Z_FAN
			fan.Parent = layer
			local fl = Instance.new("UIListLayout")
			fl.SortOrder = Enum.SortOrder.LayoutOrder
			fl.Padding = UDim.new(0, 6)
			fl.HorizontalAlignment = Enum.HorizontalAlignment.Center
			fl.Parent = fan
			fans[hotspot.id] = fan
		end

		if hotspot.id == "book" and opts.tutorialRibbon then
			local source = opts.tutorialRibbon
			local ribbon = Instance.new("TextLabel") -- mirrors the tutorial's New ribbon until it is done
			ribbon.Name = "NewRibbon"
			ribbon.AnchorPoint = Vector2.new(1, 0)
			ribbon.Position = UDim2.new(1, -2, 0, 2)
			ribbon.Size = UDim2.fromOffset(44, 22)
			ribbon.BackgroundColor3 = Color3.fromRGB(176, 52, 40)
			ribbon.Font = Enum.Font.GothamBold
			ribbon.Text = "New"
			ribbon.TextSize = 15
			ribbon.TextColor3 = Color3.fromRGB(250, 235, 200)
			ribbon.TextTransparency = 0
			ribbon.TextStrokeTransparency = 1
			ribbon.Rotation = 8
			ribbon.Active = false
			ribbon.ZIndex = 20
			ribbon.Visible = source.Visible
			ribbon.Parent = frame
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 5)
			rc.Parent = ribbon
			source:GetPropertyChangedSignal("Visible"):Connect(function() ribbon.Visible = source.Visible end)
			if source.Visible then
				table.insert(lanterns, TweenService:Create(rim, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = 0.1, Thickness = 4 }))
				result.animatedCount += 1
			end
		end

		if hotspot.lit then
			-- the pulsing lantern of the Deal Me In sign
			table.insert(lanterns, TweenService:Create(rim, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Thickness = 7, Transparency = 0.1 }))
			rim.Transparency = 0.4
			result.animatedCount += 1
			-- the Deal Me In plaque stays visible on the sign
			local button = buttons.play
			if button then
				local prior = homes.play
				homes.play = function(b)
					prior(b)
					local plaque = b:FindFirstChild("Plaque")
					plaque.Visible = true
					plaque.AnchorPoint = Vector2.new(0.5, 1)
					plaque.Position = UDim2.new(0.5, 0, 1, -44)
					plaque.Size = UDim2.fromOffset(210, 38)
					plaque.Desc.Visible = false
					plaque.Title.Size = UDim2.new(1, -20, 1, 0)
					plaque.Title.Position = UDim2.fromOffset(10, 0)
					plaque.Title.TextSize = 22
				end
			end
		end
	end

	-- Dock everything where it lives.
	for _, action in ipairs(Layout.Actions) do dock(action.id) end

	function result.applyViewport(w, h)
		local phone = Layout.isPhone(w)
		if phone == state.phone and result._applied then return end
		result._applied = true
		state.phone = phone
		layer.Visible = not phone
		allButton.Visible = not phone
		catcher.Visible = false
		if phone then
			list.AnchorPoint = Vector2.new(0.5, 0)
			list.Position = UDim2.new(0.5, 0, 0, 334) -- below the news and rank strips
			list.Size = UDim2.new(0, 252, 1, -346)
			list.Visible = true
			fillList()
			if buttons.play then buttons.play.LayoutOrder = 0 end
		else
			list.AnchorPoint = Vector2.new(1, 1)
			list.Position = UDim2.new(1, -16, 1, -62)
			list.Size = UDim2.new(0, 252, 0.7, 0)
			list.Visible = false
			state.listOpen = false
			for _, action in ipairs(Layout.Actions) do dock(action.id) end
		end
	end

	-- Entry: hotspots drop in with a 0.06s stagger (skipped in calm mode).
	local entered = false
	function result.entry()
		if entered or calm() then
			entered = true
			return
		end
		entered = true
		for i, hotspot in ipairs(Layout.Hotspots) do
			local frame = result.hotspotFrames[hotspot.id]
			local target = frame.Position
			frame.Position = target - UDim2.fromOffset(0, 40)
			task.delay(0.06 * (i - 1), function()
				TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = target }):Play()
			end)
		end
	end

	function result.startLoops()
		if calm() then return end
		for _, t in ipairs(lanterns) do t:Play() end
	end
	function result.stopLoops()
		for _, t in ipairs(lanterns) do t:Cancel() end
		for _, hotspot in ipairs(Layout.Hotspots) do
			local ui = hotspotUI[hotspot.id]
			if ui then
				ui.rim.Thickness = hotspot.lit and 3 or 2
				ui.rim.Transparency = hotspot.lit and 0.4 or 0.7
			end
		end
	end

	return result
end

return Hotspots
