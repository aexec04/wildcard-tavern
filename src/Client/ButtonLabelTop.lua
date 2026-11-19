-- ButtonLabelTop: a button's word is drawn by its own TextLabel child "KitLabel" that sits ABOVE every decorative child
-- (SetSkinPlate, InnerRim, brackets). Children draw over their parent's own text at an equal ZIndex, so a skin plate dimmed every
-- label (Run Over, Counter). One shared helper, used by SetSkin and VisualHelpers, so every screen is fixed at once.
-- The button keeps its own Text and look untouched (code reads and sets it, some modules guard its transparency); the label
-- copies it one way and draws the same word on top, so there is no property fight and the dimmed copy underneath is covered.
local ButtonLabelTop = {}

ButtonLabelTop.PAD, ButtonLabelTop.MAX_SCALED = 12, 26 -- a TextScaled word: side padding and the largest size
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

-- A screen that draws its own word (Gameplay2's Play Hand and Discard: the button is a see-through hit box, its Text is blank and its
-- TextTransparency 1) takes the label over: the label keeps its own text and stays fully visible whatever the button does. Without
-- this the mirror copied the hit box's TextTransparency 1 onto the word and the plates read blank (Nov 19). Returns the label.
function ButtonLabelTop.own(button, text, size, z, color)
	local label = ButtonLabelTop.attach(button) or button:FindFirstChild("KitLabel")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "KitLabel"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Active = false
		label.Parent = button
	end
	label:SetAttribute("OwnLabel", true)
	label.Visible = true
	label.BackgroundTransparency = 1
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.3
	label.Text = text
	if size then label.TextSize = size end
	if z then label.ZIndex = z end
	if color then label.TextColor3 = color end
	button.Text = ""
	return label
end

-- pure rule, tested: a drawn word below this transparency can be read; a disabled look may dim it to 0.35, never hide it
ButtonLabelTop.MAX_TRANSPARENCY = 0.5

-- every KitLabel under root that has a word, is shown and cannot be read (Studio prints these, a test expects none)
function ButtonLabelTop.audit(root)
	local bad = {}
	if not root then return bad end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == "KitLabel" and d:IsA("TextLabel") and d.Text ~= "" and d.Visible ~= false and (d.TextTransparency or 0) >=ButtonLabelTop.MAX_TRANSPARENCY then
			bad[#bad + 1] = d
		end
	end
	return bad
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
	local want, wantStroke = button.TextTransparency or 0, button.TextStrokeTransparency or 1 -- what the button's owner asked for; the label draws it
	local function sync()
		if busy or label:GetAttribute("OwnLabel") == true then return end -- an owned label (ButtonLabelTop.own) is never overwritten by its button
		busy = true
		for _, p in ipairs(MIRROR) do
			local ok, v = pcall(function() return button[p] end)
			if ok and v ~= nil and label[p] ~= v then label[p] = v end
		end
		-- the word is drawn once: the label shows it and the button's own copy is hidden (it stays the hit box, and its Text is kept)
		if (button.TextTransparency or 0) ~= 1 then want = button.TextTransparency or 0 end
		if (button.TextStrokeTransparency or 1) ~= 1 then wantStroke = button.TextStrokeTransparency end
		label.TextTransparency = want
		label.TextStrokeTransparency = wantStroke
		button.TextTransparency = 1
		button.TextStrokeTransparency = 1
		label.ZIndex = topZ(button, label)
		if button.TextScaled and not label:FindFirstChildOfClass("UITextSizeConstraint") then -- a scaled word keeps 12 px clear of the plate edge and never grows past 26
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft, pad.PaddingRight = UDim.new(0, ButtonLabelTop.PAD), UDim.new(0, ButtonLabelTop.PAD)
			pad.Parent = label
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = ButtonLabelTop.MAX_SCALED
			cap.Parent = label
		end
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
