--[[
	Client/PlayPlates.lua
	Paints Sort, Play Hand and Discard as the three plates of play_plates_b (one Image id, one ImageRectOffset and
	ImageRectSize per plate, boxes in Engine/PlayTableLayout). The real controls stay: same buttons, same hit areas, same
	Active and keyboard logic, same enabled state (Client/ActionButtonFX dims the hidden HudFace, which this follows).
	Only the look changes: a PlatePaint image under the text, a white 12 percent hover overlay with a 2 px lift, a 4 px press,
	50 percent when dim, and a cream label with a dark stroke on the plate face below its top bar.

	PlayPlates.apply(actionFrame, placement)   placement from PlayTableLayout.placement; nil puts the old buttons back
	Called by Client/PlayScenePaint. Everything is a child of the control it decorates, so Clone() keeps it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayTableLayout = require(Engine:WaitForChild("PlayTableLayout"))
local ImageSpace = require(Engine:WaitForChild("ImageSpace"))
local LayoutSwitch = require(script.Parent.LayoutSwitch)

local PlayPlates = {}

local CREAM = Color3.fromRGB(250, 240, 220)
local INK = Color3.fromRGB(30, 18, 8)

local function find(actionFrame)
	local sortFrame, play, discard
	for _, c in ipairs(actionFrame:GetChildren()) do
		if c:IsA("Frame") and c.LayoutOrder == 0 then sortFrame = c end
		if c:IsA("TextButton") and c.LayoutOrder == 1 then play = c end
		if c:IsA("TextButton") and c.LayoutOrder == 3 then discard = c end
	end
	return sortFrame, play, discard
end

local function ensure(parent, class, name, z)
	local inst = parent:FindFirstChild(name)
	if not inst then
		inst = Instance.new(class)
		inst.Name = name
		-- BorderSizePixel and Active exist only on GuiObjects: setting them on a UIStroke or UITextSizeConstraint throws, which
		-- aborted paintButton halfway (Play Hand half painted, Discard and Sort never reached)
		if inst:IsA("GuiObject") then
			inst.BorderSizePixel = 0
			inst.Active = false
		end
		inst.Parent = parent
	end
	if inst:IsA("GuiObject") then inst.ZIndex = z end
	return inst
end

-- the plate picture under a control, cropped to its box
local function plateImage(host, imageId, box)
	local img = ensure(host, "ImageLabel", "PlatePaint", 1)
	img.BackgroundTransparency = 1
	img.Image = imageId
	-- Roblox stores the 1536 px sheet at 1024: the rect is read in the stored texture
	local x, y, w, h = ImageSpace.rect(box.x, box.y, box.w, box.h, PlayTableLayout.PLATES_IMG_W, PlayTableLayout.PLATES_IMG_H)
	img.ImageRectOffset = Vector2.new(x, y)
	img.ImageRectSize = Vector2.new(w, h)
	img.ScaleType = Enum.ScaleType.Stretch
	img.Size = UDim2.fromScale(1, 1)
	img.Position = UDim2.fromOffset(0, 0)
	return img
end

local function paintButton(btn, imageId, box, rect)
	btn.Size = UDim2.fromOffset(rect.w, rect.h)
	local img = plateImage(btn, imageId, box)
	for _, n in ipairs({ "HudFace", "HudOuter", "EmberGlow" }) do
		local f = btn:FindFirstChild(n)
		if f then f.Visible = false end
	end
	local rim = btn:FindFirstChildOfClass("UIStroke")
	if rim and rim.Name ~= "PlateTextStroke" then rim.Enabled = false end
	btn.BackgroundTransparency = 1

	local F = PlayTableLayout.FACE
	-- No UIPadding on the button: it would also shrink the PlatePaint picture and the hidden HudFace (children of the button),
	-- which showed only the top bar or a dark box. The label is its own child placed on the board face by hand.
	local top, bottom = math.floor(rect.h * F.y + 0.5), math.floor(rect.h * (1 - F.y - F.h) + 0.5)
	local side = math.floor(rect.w * F.x + 0.5)
	local old = btn:FindFirstChild("PlateFace")
	if old then old:Destroy() end
	local lab = ensure(btn, "TextLabel", "PlateLabel", 3)
	lab.BackgroundTransparency = 1
	lab.Font = btn.Font
	lab.Text = btn.Text
	lab.TextScaled = false
	lab.TextSize = 21
	lab.TextWrapped = false
	lab.TextXAlignment = Enum.TextXAlignment.Center
	lab.TextYAlignment = Enum.TextYAlignment.Center
	lab.TextColor3 = CREAM
	lab.Position = UDim2.fromOffset(side, top)
	lab.Size = UDim2.new(1, -2 * side, 1, -(top + bottom))
	local oldCap = lab:FindFirstChild("PlateTextSize")
	if oldCap then oldCap:Destroy() end
	local ts = ensure(lab, "UIStroke", "PlateTextStroke", 1)
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Color, ts.Thickness, ts.Transparency = INK, 2, 0
	btn.TextTransparency, btn.TextStrokeTransparency = 1, 1

	local hover = ensure(btn, "Frame", "PlateHover", 2)
	hover.BackgroundColor3 = Color3.new(1, 1, 1)
	hover.BackgroundTransparency = 1
	hover.Position = UDim2.fromOffset(side, top)
	hover.Size = UDim2.new(1, -2 * side, 1, -(top + bottom))

	if btn:GetAttribute("PlateHooked") then return end
	btn:SetAttribute("PlateHooked", true)
	-- one label per button: keep the button's own text invisible even if a restyle resets it
	local function hideOwnText()
		if btn:GetAttribute("PlatePainted") then
			btn.TextTransparency, btn.TextStrokeTransparency = 1, 1
		end
	end
	btn:GetPropertyChangedSignal("TextTransparency"):Connect(hideOwnText)
	btn:GetPropertyChangedSignal("TextStrokeTransparency"):Connect(hideOwnText)
	local state = { hover = false, pressed = false }
	local function look()
		if not btn:GetAttribute("PlatePainted") then return end
		local dy = state.pressed and 4 or (state.hover and -2 or 0)
		local face = btn:FindFirstChild("HudFace")
		local dim = face ~= nil and face.BackgroundTransparency > 0.3
		local image = btn:FindFirstChild("PlatePaint")
		if image then
			image.ImageTransparency = dim and 0.5 or 0
			image.Position = UDim2.fromOffset(0, dy)
			image.ImageColor3 = state.pressed and Color3.fromRGB(190, 190, 190) or Color3.new(1, 1, 1)
		end
		local lb = btn:FindFirstChild("PlateLabel")
		if lb then
			lb.Position = UDim2.fromOffset(side, top + dy)
			lb.TextTransparency = dim and 0.5 or 0
		end
		local h = btn:FindFirstChild("PlateHover")
		if h then
			h.Position = UDim2.fromOffset(side, top + dy)
			h.BackgroundTransparency = (state.hover and not dim) and 0.88 or 1
		end
	end
	btn.MouseEnter:Connect(function() state.hover = true look() end)
	btn.MouseLeave:Connect(function() state.hover, state.pressed = false, false look() end)
	btn.MouseButton1Down:Connect(function() state.pressed = true look() end)
	btn.MouseButton1Up:Connect(function() state.pressed = false look() end)
	local face = btn:FindFirstChild("HudFace")
	if face then face:GetPropertyChangedSignal("BackgroundTransparency"):Connect(look) end
	btn:GetPropertyChangedSignal("Text"):Connect(function()
		local lb = btn:FindFirstChild("PlateLabel")
		if lb then lb.Text = btn.Text end
	end)
end

local function restoreButton(btn, w, h)
	for _, n in ipairs({ "PlatePaint", "PlateFace", "PlateLabel", "PlateHover" }) do
		local o = btn:FindFirstChild(n)
		if o then o:Destroy() end
	end
	for _, n in ipairs({ "HudFace", "HudOuter", "EmberGlow" }) do
		local f = btn:FindFirstChild(n)
		if f then f.Visible = true end
	end
	local rim = btn:FindFirstChildOfClass("UIStroke")
	if rim then rim.Enabled = true end
	btn.TextScaled = false
	btn.TextTransparency, btn.TextStrokeTransparency = 0, 0
	btn.Size = UDim2.new(0, w, 1, 0)
	btn.AnchorPoint = Vector2.new(0, 0)
end

function PlayPlates.apply(actionFrame, placement, imageId)
	local sortFrame, play, discard = find(actionFrame)
	if not (sortFrame and play and discard) then return false end
	local layout = actionFrame:FindFirstChildOfClass("UIListLayout") or LayoutSwitch.on(actionFrame)
	local toggle = sortFrame:FindFirstChild("SortToggle")
	local caption
	for _, c in ipairs(sortFrame:GetChildren()) do
		if c:IsA("TextLabel") then caption = c end
	end
	local on = placement ~= nil and type(imageId) == "string" and imageId ~= ""
	for _, c in ipairs({ sortFrame, play, discard }) do c:SetAttribute("PlatePainted", on or nil) end

	if not on then
		restoreButton(play, 200)
		restoreButton(discard, 200)
		local pi = sortFrame:FindFirstChild("PlatePaint")
		if pi then pi:Destroy() end
		LayoutSwitch.on(sortFrame)
		sortFrame.Size = UDim2.new(0, 214, 1, 0)
		if caption then caption.Visible = true end
		if toggle then
			toggle.Size = UDim2.fromOffset(150, 36)
			toggle.BackgroundTransparency = 0
			local st = toggle:FindFirstChildOfClass("UIStroke")
			if st then st.Enabled = true end
			local o = toggle:FindFirstChild("ToggleOuter")
			if o then o.Visible = true end
		end
		sortFrame.Position, play.Position, discard.Position = UDim2.new(), UDim2.new(), UDim2.new()
		if layout then
			LayoutSwitch.on(actionFrame)
			layout.Padding = UDim.new(0, 20)
			layout.VerticalAlignment = Enum.VerticalAlignment.Top
		end
		return false
	end

	local pl = placement.map.plates
	local B = PlayTableLayout.PLATE_BOXES
	-- the three plates are placed by hand from the tested rects (a list layout let them overlap); the layout comes back with the fallback
	LayoutSwitch.off(actionFrame)
	local ox, oy = pl.sort.x, pl.play.y
	for key, c in pairs({ sort = sortFrame, play = play, discard = discard }) do
		c.AnchorPoint = Vector2.new(0, 0)
		c.Position = UDim2.fromOffset(pl[key].x - ox, pl[key].y - oy)
	end
	paintButton(play, imageId, B.play, pl.play)
	paintButton(discard, imageId, B.discard, pl.discard)

	-- Sort: the plate carries the Rank | Suit toggle on its face; the toggle keeps its own hit areas and lit half
	sortFrame.Size = UDim2.fromOffset(pl.sort.w, pl.sort.h)
	plateImage(sortFrame, imageId, B.sort)
	local F = PlayTableLayout.FACE
	-- the sort frame's own layout would also lay the plate picture out as a sibling: switch it off and place by hand
	LayoutSwitch.off(sortFrame)
	if caption then caption.Visible = false end
	if toggle then
		toggle.Position = UDim2.fromOffset(math.floor(pl.sort.w * F.x + 0.5), math.floor(pl.sort.h * F.y + 0.5))
		toggle.Size = UDim2.fromOffset(math.floor(pl.sort.w * F.w + 0.5), math.floor(pl.sort.h * F.h + 0.5))
		toggle.BackgroundTransparency = 1
		local st = toggle:FindFirstChildOfClass("UIStroke")
		if st then st.Enabled = false end
		local o = toggle:FindFirstChild("ToggleOuter")
		if o then o.Visible = false end
		toggle.ZIndex = 2
	end
	return true
end

return PlayPlates
