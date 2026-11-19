-- ButtonLabelTop: a button's word is drawn by its own TextLabel child "KitLabel" that sits ABOVE every decorative child
-- (SetSkinPlate, InnerRim, brackets). Children draw over their parent's own text at an equal ZIndex, so a skin plate dimmed every
-- label (Run Over, Counter). One shared helper, used by SetSkin and VisualHelpers, so every screen is fixed at once.
-- The button keeps its own Text and look untouched (code reads and sets it, some modules guard its transparency); the label
-- copies it one way and draws the same word on top, so there is no property fight and the dimmed copy underneath is covered.
local ButtonLabelTop = {}

ButtonLabelTop.LIFT = 3 -- the label's ZIndex above the button
local MIRROR = { "Text", "TextColor3", "TextSize", "Font", "TextStrokeColor3", "TextWrapped", "TextXAlignment", "TextYAlignment", "TextScaled", "RichText", "LineHeight" }

-- pure rule, tested: the label must draw above every decorative sibling
function ButtonLabelTop.zFor(buttonZ, siblingZs)
	local top = buttonZ
	for _, z in ipairs(siblingZs or {}) do
		if z > top then top = z end
	end
	return top + ButtonLabelTop.LIFT
end

local function topZ(button, label)
	local zs = {}
	for _, c in ipairs(button:GetChildren()) do
		if c ~= label and c:IsA("GuiObject") then zs[#zs + 1] = c.ZIndex end
	end
	return ButtonLabelTop.zFor(button.ZIndex, zs)
end

-- pure rule, tested: a button needs the label when it has a word and some decorative child draws at or above its own ZIndex
function ButtonLabelTop.needs(buttonZ, text, siblingZs)
	if text == nil or text == "" then return false end
	for _, z in ipairs(siblingZs or {}) do
		if z >= buttonZ then return true end
	end
	return false
end

-- Safety net for any screen: attach the label to every TextButton under root that needs it. Returns how many were fixed.
function ButtonLabelTop.sweep(root)
	local fixed = 0
	if not root then return fixed end
	for _, b in ipairs(root:GetDescendants()) do
		if b:IsA("TextButton") and not b:FindFirstChild("KitLabel") and b.Text ~= "" then
			local zs = {}
			for _, c in ipairs(b:GetChildren()) do
				if c:IsA("GuiObject") then zs[#zs + 1] = c.ZIndex end
			end
			if ButtonLabelTop.needs(b.ZIndex, b.Text, zs) and ButtonLabelTop.attach(b) then fixed = fixed + 1 end
		end
	end
	return fixed
end

function ButtonLabelTop.attach(button)
	if not button or not button:IsA("TextButton") then return nil end
	local existing = button:FindFirstChild("KitLabel")
	if existing then return existing end -- Gameplay2 draws its own
	local label = Instance.new("TextLabel")
	label.Name = "KitLabel"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Active = false
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	local busy = false
	local function sync()
		if busy then return end
		busy = true
		for _, p in ipairs(MIRROR) do
			local ok, v = pcall(function() return button[p] end)
			if ok and v ~= nil and label[p] ~= v then label[p] = v end
		end
		label.TextTransparency = button.TextTransparency
		label.TextStrokeTransparency = button.TextStrokeTransparency
		label.ZIndex = topZ(button, label)
		busy = false
	end
	label.Parent = button
	sync()
	for _, p in ipairs(MIRROR) do
		button:GetPropertyChangedSignal(p):Connect(sync)
	end
	button:GetPropertyChangedSignal("TextTransparency"):Connect(sync)
	button:GetPropertyChangedSignal("TextStrokeTransparency"):Connect(sync)
	button:GetPropertyChangedSignal("ZIndex"):Connect(sync)
	button.ChildAdded:Connect(function(c)
		if c ~= label and c:IsA("GuiObject") then task.defer(sync) end
	end)
	return label
end

return ButtonLabelTop
