--[[
	Client/HudTheme.lua
	Code-drawn, Card Set themed HUD buttons (colours from Engine/HudStyle, which keeps text at 4.5:1).

	  HudTheme.styleAction(button, role)  Play Hand / Discard: a solid rounded base, two rings (dark outer, accent inner), a
	                                      subtle Color-only gradient, hover and pressed states. Text sits on the solid base.
	  HudTheme.styleIcon(button)          the round top-right icon buttons: set ring, glow, tinted disc and a small motif
	  HudTheme.setSkin(skin)              called by SetSkin.set; restyles everything built here, live on equip or Preview
	  HudTheme.skin()                     the skin in force (CosmeticSets.skinOf shape)
	  HudTheme.onSkin(fn)                 SortToggle and DeckWidgetSkin register their restyle here

	Art hook: if skin.images.hudAccent exists it is drawn as a small, non-text corner accent clipped inside the button.
	Marked buttons carry the attribute HudThemed so SetSkin leaves them alone. All decoration is a child of the button, so
	Clone() keeps it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HudStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudStyle"))
local HudKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudKit"))
local ClientSettings = require(script.Parent.ClientSettings)

local HudTheme = {}

local current = { images = {}, colors = nil, neutral = true }
local actions = setmetatable({}, { __mode = "k" }) -- [button] = { role, hover, pressed }
local icons = setmetatable({}, { __mode = "k" })
local listeners = {}

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function calm()
	return ClientSettings.get("reduceShake") == true
end

local function ease(inst, props)
	if calm() then
		for k, v in pairs(props) do inst[k] = v end
		return
	end
	TweenService:Create(inst, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

function HudTheme.skin()
	return current
end

-- Id of the set whose kit art to use: the applied skin's, else the default set (no skin is applied before the first equip).
function HudTheme.setId()
	return current.id or "classic_tavern"
end

function HudTheme.onSkin(fn)
	table.insert(listeners, fn)
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function child(button, class, name, z)
	local inst = button:FindFirstChild(name)
	if not inst then
		inst = Instance.new(class)
		inst.Name = name
		inst.BorderSizePixel = 0
		inst.Active = false
		inst.Parent = button
	end
	inst.ZIndex = z
	return inst
end

local function dropOldChrome(button)
	-- the painted plate and the older gold chrome step aside: one frame, not two
	for _, n in ipairs({ "SetSkinPlate", "SkinArt", "InnerRim", "BracketH", "BracketV", "Gloss" }) do
		local old = button:FindFirstChild(n)
		if old then old:Destroy() end
	end
end

-- light text gets a soft dark shadow so it holds on painted plates (the 4.5:1 maths only knows the flat fill underneath)
local function softShadow(label, textColor)
	local lum = (textColor[1] * 0.299 + textColor[2] * 0.587 + textColor[3] * 0.114) / 255
	label.TextTransparency = 0
	if lum > 0.55 then
		label.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
		label.TextStrokeTransparency = 0.55
	else
		label.TextStrokeTransparency = 1
	end
end

local function paintAction(button, entry)
	local p = HudStyle.buttonPalette(current.colors, entry.role)
	local face = button:FindFirstChild("HudFace")
	local rim = button:FindFirstChildOfClass("UIStroke")
	local base = entry.pressed and p.pressed or (entry.hover and p.hover or p.fill)
	if face then
		face.BackgroundColor3 = c3(base)
		local g = face:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(228, 228, 228)) -- multiplies the fill; Color stops only
		end
	end
	if rim then
		rim.Color = c3(entry.hover and p.innerHover or p.inner)
	end
	local outer = button:FindFirstChild("HudOuter")
	if outer then
		local s = outer:FindFirstChildOfClass("UIStroke")
		if s then s.Color = c3(p.outer) end
	end
	button.TextColor3 = c3(p.text)
	softShadow(button, p.text)
	local art = button:FindFirstChild("HudAccentArt")
	local image = current.images and current.images.hudAccent
	if image then
		if not art then
			art = child(button, "ImageLabel", "HudAccentArt", button.ZIndex)
			art.BackgroundTransparency = 1
			art.Size = UDim2.fromOffset(28, 28)
			art.ScaleType = Enum.ScaleType.Fit
			art.ImageTransparency = 0.2
			corner(art, UDim.new(0, 6))
		end
		art.Image = image
	elseif art then
		art:Destroy()
	end
end

function HudTheme.styleAction(button, role)
	if actions[button] then return end
	local entry = { role = role, hover = false, pressed = false }
	actions[button] = entry
	button:SetAttribute("HudThemed", true)
	dropOldChrome(button)
	local z = button.ZIndex
	button.BackgroundTransparency = 1 -- the solid base is the HudFace child, below the text
	button.AutoButtonColor = false
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 2
		stroke.Transparency = 0
	end
	local outer = child(button, "Frame", "HudOuter", math.max(0, z - 1))
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.new(1, 6, 1, 6)
	outer.BackgroundTransparency = 1
	corner(outer, UDim.new(0, 11))
	local os = Instance.new("UIStroke")
	os.Thickness = 3
	os.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	os.Parent = outer
	local face = child(button, "Frame", "HudFace", math.max(0, z - 1))
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 0
	corner(face, UDim.new(0, 8))
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = face
	button.MouseEnter:Connect(function() entry.hover = true paintAction(button, entry) end)
	button.MouseLeave:Connect(function() entry.hover, entry.pressed = false, false paintAction(button, entry) end)
	button.MouseButton1Down:Connect(function() entry.pressed = true paintAction(button, entry) end)
	button.MouseButton1Up:Connect(function() entry.pressed = false paintAction(button, entry) end)
	paintAction(button, entry)
end

-- Painted per-set kit button (Engine/HudKit piece btn_*): replaces the tinted disc, ring, glow and motif. Hover and pressed are
-- brightness and scale only (no tween in calm mode). Returns true when the kit button is showing.
local function paintKitButton(button, piece)
	local art = type(piece) == "string" and HudKit.piece(current.id, piece) or nil
	local face = button:FindFirstChild("HudKitBtn")
	local rim = button:FindFirstChildOfClass("UIStroke")
	local pic = button:FindFirstChild("Icon")
	local glow, motif = button:FindFirstChild("HudGlow"), button:FindFirstChild("HudMotif")
	if not art then
		if face then
			face:Destroy()
			local bg = button:GetAttribute("HudKitBgT")
			if bg ~= nil then button.BackgroundTransparency = bg end
			if rim then rim.Enabled = true end
			if pic then pic.Visible = true end
			if glow then glow.Visible = true end
			if motif then motif.Visible = true end
		end
		return false
	end
	if not face then
		face = child(button, "ImageLabel", "HudKitBtn", button.ZIndex + 1)
		face.AnchorPoint = Vector2.new(0.5, 0.5)
		face.Position = UDim2.fromScale(0.5, 0.5)
		face.BackgroundTransparency = 1
		face.ScaleType = Enum.ScaleType.Fit
		face.Size = UDim2.fromScale(1, 1)
	end
	if button:GetAttribute("HudKitBgT") == nil then button:SetAttribute("HudKitBgT", button.BackgroundTransparency) end
	face.Image = art
	button.BackgroundTransparency = 1
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	if rim then rim.Enabled = false end
	if pic then pic.Visible = false end
	if glow then glow.Visible = false end
	if motif then motif.Visible = false end
	local hover, pressed = button:GetAttribute("HudHover") == true, button:GetAttribute("HudPressed") == true
	local scale = pressed and 0.95 or (hover and 1.1 or 1)
	local shade = pressed and 200 or (hover and 255 or 238)
	ease(face, { Size = UDim2.fromScale(scale, scale), ImageColor3 = Color3.fromRGB(shade, shade, shade) })
	return true
end

local function paintIcon(button)
	if paintKitButton(button, icons[button]) then return end
	local p = HudStyle.iconPalette(current.colors)
	button.BackgroundColor3 = c3(p.disc)
	button.TextColor3 = c3(p.text)
	button.TextTransparency = 0
	button.TextStrokeTransparency = 1
	local rim = button:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = c3(p.ring)
		rim.Thickness = 3
		rim.Transparency = 0
	end
	local pic = button:FindFirstChild("Icon")
	if pic and pic:IsA("ImageLabel") then
		pic.Size = UDim2.fromOffset(36, 36) -- the tinted disc shows as a ring around the painted icon
		pic.ImageColor3 = c3(button:GetAttribute("HudHover") and p.tintHover or p.tint)
	end
	local glow = button:FindFirstChild("HudGlow")
	if glow then
		glow:FindFirstChildOfClass("UIStroke").Color = c3(p.glow)
	end
	local motif = button:FindFirstChild("HudMotif")
	if motif then
		motif.BackgroundColor3 = c3(p.motif)
		local s = motif:FindFirstChildOfClass("UIStroke")
		if s then s.Color = c3(p.outer) end
	end
end

function HudTheme.styleIcon(button, piece)
	if icons[button] then return end
	icons[button] = piece or true -- piece (btn_volume ...) picks the painted kit button; none = the tinted disc only
	button:SetAttribute("HudThemed", true)
	local plate = button:FindFirstChild("SetSkinPlate")
	if plate then plate:Destroy() end
	local glow = child(button, "Frame", "HudGlow", math.max(0, button.ZIndex - 1))
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 8, 1, 8)
	glow.BackgroundTransparency = 1
	corner(glow, UDim.new(0.5, 0))
	local gs = Instance.new("UIStroke")
	gs.Thickness = 3
	gs.Transparency = 0.6 -- a soft halo; Transparency of a stroke, not of a gradient
	gs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gs.Parent = glow
	local motif = child(button, "Frame", "HudMotif", button.ZIndex + 3)
	motif.AnchorPoint = Vector2.new(0.5, 0.5)
	motif.Position = UDim2.new(0.5, 0, 0, 1)
	motif.Size = UDim2.fromOffset(9, 9)
	motif.Rotation = 45
	local ms = Instance.new("UIStroke")
	ms.Thickness = 1.5
	ms.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ms.Parent = motif
	button.MouseEnter:Connect(function() button:SetAttribute("HudHover", true) paintIcon(button) end)
	button.MouseLeave:Connect(function() button:SetAttribute("HudHover", nil) button:SetAttribute("HudPressed", nil) paintIcon(button) end)
	button.MouseButton1Down:Connect(function() button:SetAttribute("HudPressed", true) paintIcon(button) end)
	button.MouseButton1Up:Connect(function() button:SetAttribute("HudPressed", nil) paintIcon(button) end)
	paintIcon(button)
end

function HudTheme.setSkin(skin)
	current = skin or { images = {}, colors = nil, neutral = true }
	for button, entry in pairs(actions) do
		if button.Parent then paintAction(button, entry) else actions[button] = nil end
	end
	for button in pairs(icons) do
		if button.Parent then paintIcon(button) else icons[button] = nil end
	end
	for _, fn in ipairs(listeners) do
		pcall(fn, current)
	end
end

return HudTheme
