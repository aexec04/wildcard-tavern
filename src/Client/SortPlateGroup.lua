--[[
	Client/SortPlateGroup.lua
	The Rank and Suit plates draw a small glyph (KitIcon) and a word (KitLabel). Other writers (ButtonLabelTop mirroring the button's
	alignment, a UIPadding, a late KitLabel) could leave the word centred while the glyph sat in the middle of it ("Ra" glyph "nk").
	This module owns the geometry: icon first, a 6 px gap, then the word, left aligned, as one group centred in the plate
	(Engine/IconLabelLayout.anchored). It re-applies after any change of the plate size, the word, its size or its alignment.
	SortPlateGroup.layout(w, h, textW, baseSize) is pure and tested; SortPlateGroup.attach(plate) wires a live plate.
]]
local SortPlateGroup = {}
SortPlateGroup.MIN_SIZE, SortPlateGroup.MIN_SIDE = 10, 4

local function engine(name)
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild(name))
end

-- pure: icon rect and word rect (plate pixels, resolved from the centre) plus the word size; never overlapping, always inside
function SortPlateGroup.layout(w, h, textW, baseSize, Layout)
	Layout = Layout or engine("IconLabelLayout")
	local a = Layout.anchored(w, h, textW, baseSize, SortPlateGroup.MIN_SIZE, SortPlateGroup.MIN_SIDE)
	local g = Layout.resolve(w, a)
	Layout.clampInside(w, h, g)
	return { icon = g.icon, label = g.label, size = a.size }
end

local function apply(plate)
	local icon, kl = plate:FindFirstChild("KitIcon"), plate:FindFirstChild("KitLabel")
	if not icon or not kl or not kl:IsA("TextLabel") or kl.Text == "" then return end
	local pw, ph = plate.AbsoluteSize.X, plate.AbsoluteSize.Y
	local sc, anc = 1, plate -- a UIScale on the plate or above scales offsets too: measure in the plate's own units
	while anc and anc:IsA("GuiObject") do
		local us = anc:FindFirstChildOfClass("UIScale")
		if us and us.Scale > 0 then sc = sc * us.Scale end
		anc = anc.Parent
	end
	pw, ph = math.floor(pw / sc + 0.5), math.floor(ph / sc + 0.5)
	if pw < 2 or ph < 2 then return end
	local pad = plate:FindFirstChild("KitIconPad")
	if pad and pad:IsA("UIPadding") then pad.PaddingLeft = UDim.new(0, 0) end -- a padding moves every child, the glyph too
	local base = kl:GetAttribute("KitBaseSize") or kl.TextSize
	kl:SetAttribute("KitBaseSize", base)
	local ok, bounds = pcall(function() return game:GetService("TextService"):GetTextSize(kl.Text, base, kl.Font, Vector2.new(10000, 10000)) end)
	if not ok or not bounds then return end
	local L = SortPlateGroup.layout(pw, ph, bounds.X, base)
	kl.TextSize = L.size
	kl.TextXAlignment = Enum.TextXAlignment.Left
	kl.AnchorPoint = Vector2.new(0, 0)
	kl.Position = UDim2.fromOffset(L.label.x, 0)
	kl.Size = UDim2.fromOffset(L.label.w + 4, ph)
	icon.AnchorPoint = Vector2.new(0, 0)
	icon.Position = UDim2.fromOffset(L.icon.x, L.icon.y)
	icon.Size = UDim2.fromOffset(L.icon.w, L.icon.h)
end

-- Wires a plate once (safe to call again). Re-applies after any change that could move the word or the glyph.
function SortPlateGroup.attach(plate)
	if not plate or plate:GetAttribute("SortGroupWired") then return end
	plate:SetAttribute("SortGroupWired", true)
	local busy = false
	local function run()
		if busy then return end
		busy = true
		pcall(apply, plate)
		busy = false
	end
	local function watch(kl)
		for _, prop in ipairs({ "Text", "TextSize", "TextXAlignment", "Position", "Size", "Font" }) do
			kl:GetPropertyChangedSignal(prop):Connect(function() task.defer(run) end)
		end
	end
	local kl = plate:FindFirstChild("KitLabel")
	if kl then watch(kl) end
	plate.ChildAdded:Connect(function(c)
		if c.Name == "KitLabel" then watch(c) end
		if c.Name == "KitLabel" or c.Name == "KitIcon" or c.Name == "KitIconPad" then task.defer(run) end
	end)
	plate:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() task.defer(run) end)
	task.defer(run)
end

return SortPlateGroup
