--[[
	Client/SidebarTheme.lua
	Recolors the left HUD panel (Client/Sidebar.lua, BlessingChip) for the equipped or previewed Card Set, live, without
	rebuilding anything. Palette: Engine/HudStyle.panelPalette (nil for Classic Tavern, which keeps the painted look exactly).

	Each recolored instance remembers its original colour in an attribute (HudOrig*), so switching back to Classic restores it.
	Pieces are found by their original colour, so Sidebar.lua needs no per-set code. Only Color3 values change, never
	Transparency. Init: SidebarTheme.init(root) once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudStyle"))
local HudKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudKit"))
local HudTheme = require(script.Parent.HudTheme)

local SidebarTheme = {}

local root

local function key(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- original colour (as written in Sidebar.lua / BlessingChip.lua) -> palette field
local FILL = {
	["226,202,156"] = "paper", -- board
	["236,216,172"] = "tag", -- name tags and the blessing chip
	["199,178,137"] = "inset", -- status strips, Patron inset, score preview
	["104,66,36"] = "header", -- Night and Round plate
	["96,64,36"] = "track", -- score bar track
	["236,184,70"] = "fill", -- score bar fill
	["196,168,118"] = "medallion", -- empty Patron seat
	["150,48,40"] = "accent", -- ribbon tails
}
local INK = { ["60,40,22"] = "ink" }
local STROKE = {
	["96,66,38"] = "edge", ["110,80,45"] = "edge", ["96,64,36"] = "edge", ["150,108,40"] = "accent",
	["222,182,104"] = "accent", ["240,222,180"] = "stroke",
}

-- sidebar pieces (by their fill role) that wear a painted kit plate when the set has one (Engine/HudKit); layout parents are skipped
local KIT_PLATE = { header = "banner", track = "score_track" }

local function layoutParent(inst)
	return inst:FindFirstChildOfClass("UIListLayout") or inst:FindFirstChildOfClass("UIGridLayout") or inst:FindFirstChildOfClass("UIPageLayout")
end

-- Draws or removes the painted plate on a role frame. The flat fill hides under it (BackgroundTransparency) and returns on removal.
local function kitPlate(inst, piece, kit)
	local plate = inst:FindFirstChild("HudKitPlate")
	local id = kit and kit[piece]
	if id and not layoutParent(inst) then
		if not plate then
			plate = Instance.new("ImageLabel")
			plate.Name = "HudKitPlate"
			plate.BackgroundTransparency = 1
			plate.BorderSizePixel = 0
			plate.Active = false
			plate.ScaleType = Enum.ScaleType.Stretch
			plate.Size = UDim2.fromScale(1, 1)
			plate.Parent = inst
		end
		plate.ZIndex = inst.ZIndex -- equal z draws above the parent's own fill, below its labels
		plate.Image = id
		if inst:GetAttribute("HudKitBgT") == nil then inst:SetAttribute("HudKitBgT", inst.BackgroundTransparency) end
		inst.BackgroundTransparency = 1
		for _, d in ipairs(inst:GetChildren()) do
			if d:IsA("UIStroke") then d.Enabled = false end
		end
	elseif plate or inst:GetAttribute("HudKitBgT") ~= nil then
		if plate then plate:Destroy() end
		local bg = inst:GetAttribute("HudKitBgT")
		if bg ~= nil then
			inst.BackgroundTransparency = bg
			inst:SetAttribute("HudKitBgT", nil)
		end
		for _, d in ipairs(inst:GetChildren()) do
			if d:IsA("UIStroke") then d.Enabled = true end
		end
	end
end

-- Hides (or restores) a frame's own fill and strokes while a painted plate behind it does the job.
local function hideFill(inst, on)
	if on then
		if inst:GetAttribute("HudKitBgT") == nil then inst:SetAttribute("HudKitBgT", inst.BackgroundTransparency) end
		inst.BackgroundTransparency = 1
	else
		local bg = inst:GetAttribute("HudKitBgT")
		if bg ~= nil then
			inst.BackgroundTransparency = bg
			inst:SetAttribute("HudKitBgT", nil)
		end
	end
	for _, d in ipairs(inst:GetChildren()) do
		if d:IsA("UIStroke") then d.Enabled = not on end
	end
end

-- Swaps a stock icon holder's picture for the kit icon (the stock children hide and come back when the set has no kit).
local function kitIcon(holder, piece, kit)
	local id = kit and kit[piece]
	local img = holder:FindFirstChild("HudKitIcon")
	if id then
		if not img then
			img = Instance.new("ImageLabel")
			img.Name = "HudKitIcon"
			img.BackgroundTransparency = 1
			img.BorderSizePixel = 0
			img.Active = false
			img.ScaleType = Enum.ScaleType.Fit
			img.Size = UDim2.fromScale(1, 1)
			img.ZIndex = holder.ZIndex + 1
			img.Parent = holder
		end
		img.Image = id
		for _, c in ipairs(holder:GetChildren()) do
			if c ~= img and c:IsA("GuiObject") then
				if c:GetAttribute("HudKitWasVisible") == nil then c:SetAttribute("HudKitWasVisible", c.Visible) end
				c.Visible = false
			end
		end
	else
		if img then img:Destroy() end
		for _, c in ipairs(holder:GetChildren()) do
			local was = c:GetAttribute("HudKitWasVisible")
			if was ~= nil then
				c.Visible = was
				c:SetAttribute("HudKitWasVisible", nil)
			end
		end
	end
end

local function remember(inst, attr, value)
	if inst:GetAttribute(attr) == nil then inst:SetAttribute(attr, value) end
	return inst:GetAttribute(attr)
end

local function paint(inst, p, kit)
	if inst:IsA("GuiObject") and (inst.BackgroundTransparency < 1 or inst:GetAttribute("HudKitBgT") ~= nil) then
		local orig = remember(inst, "HudOrigBg", inst.BackgroundColor3)
		local role = FILL[key(orig)]
		if role then
			inst.BackgroundColor3 = p and c3(p[role]) or orig
			if KIT_PLATE[role] then kitPlate(inst, KIT_PLATE[role], p and kit or nil) end
		end
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		local orig = remember(inst, "HudOrigText", inst.TextColor3)
		local role = INK[key(orig)]
		if role then inst.TextColor3 = p and c3(p.ink) or orig end
		local so = remember(inst, "HudOrigTextStroke", inst.TextStrokeColor3)
		if STROKE[key(so)] == "stroke" then inst.TextStrokeColor3 = p and c3(p.stroke) or so end
	end
	if inst:IsA("UIStroke") then
		local orig = remember(inst, "HudOrigStroke", inst.Color)
		local role = STROKE[key(orig)]
		if role then inst.Color = p and c3(p[role]) or orig end
	end
	if inst:IsA("UIGradient") and inst.Parent and inst.Parent:GetAttribute("HudOrigBg") ~= nil
		and FILL[key(inst.Parent:GetAttribute("HudOrigBg"))] == "header" then
		local seq = remember(inst, "HudOrigGradTop", Color3.fromRGB(128, 84, 46))
		if p then
			inst.Color = ColorSequence.new(c3(p.headerGrainTop), c3(p.headerGrainBottom))
		else
			inst.Color = ColorSequence.new(seq, Color3.fromRGB(86, 54, 28))
		end
	end
	if inst:IsA("ImageLabel") and inst.Parent and inst.Parent.Name == "SidebarBoard" then
		-- the painted brown board art steps aside; the flat themed paper shows instead
		inst.Visible = p == nil
	end
end

local function apply(skin)
	if not root or not root.Parent then return end
	local p = HudStyle.panelPalette(skin and skin.colors)
	local board = root:FindFirstChild("SidebarBoard")
	local side = root:FindFirstChild("Sidebar")
	local kit = HudKit.images(skin and skin.id)
	for _, top in ipairs({ board, side }) do
		if top then
			paint(top, p, kit)
			for _, d in ipairs(top:GetDescendants()) do
				paint(d, p, kit)
			end
		end
	end
	if board then SidebarTheme.paintBoardDepth(board, p, kit) end
	-- phase 1b: the rest of the left panel wears the set's painted plates and icons (themed kit sets only)
	local themedKit = p and kit or nil
	for name, piece in pairs(HudKit.PLATES) do
		local inst = root:FindFirstChild(name, true)
		if inst then kitPlate(inst, piece, themedKit) end
	end
	local tray = root:FindFirstChild("PatronsInset", true)
	if tray then hideFill(tray, themedKit ~= nil and themedKit.patron_tray ~= nil) end
	for name, piece in pairs(HudKit.ICONS) do
		local holder = root:FindFirstChild(name, true)
		if holder then kitIcon(holder, piece, themedKit) end
	end
	-- the round header's red tail tabs and side bars take the accent; the plate itself stays dark
	local ribbon = side and side:FindFirstChild("HeaderRibbon", true)
	if ribbon then
		for _, d in ipairs(ribbon:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.TextColor3 = p and c3(p.headerText) or Color3.fromRGB(240, 222, 180)
			end
		end
	end
end

-- Panel depth, drawn in code for every themed set: soft inner shade (one gradient frame per edge), an inner highlight stroke, and
-- the painted kit frame when the set has one. All are children of the board; Classic (p == nil) gets none of it.
function SidebarTheme.paintBoardDepth(board, p, kit)
	local depth = board:FindFirstChild("HudDepth")
	local frame = board:FindFirstChild("HudKitFrame")
	if not p then
		if depth then depth:Destroy() end
		if frame then frame:Destroy() end
		return
	end
	if not depth then
		depth = Instance.new("Frame")
		depth.Name = "HudDepth"
		depth.Size = UDim2.fromScale(1, 1)
		depth.BackgroundTransparency = 1
		depth.BorderSizePixel = 0
		depth.Active = false
		depth.ZIndex = 1
		depth.Parent = board
		local hi = Instance.new("UIStroke") -- inner highlight
		hi.Name = "InnerHighlight"
		hi.Thickness = 2
		hi.Transparency = 0.6
		hi.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		hi.Parent = depth
		require(script.Parent.SmoothVignette).build(depth, { zIndex = 1, color = Color3.fromRGB(20, 14, 8), name = "HudInnerShade",
			top = { strength = 0.18, extent = 0.06 }, bottom = { strength = 0.26, extent = 0.08 },
			left = { strength = 0.18, extent = 0.1 }, right = { strength = 0.22, extent = 0.1 } })
	end
	depth:FindFirstChild("InnerHighlight").Color = c3(p.stroke)
	local id = kit and kit.panel_frame
	if id then
		if not frame then
			frame = Instance.new("ImageLabel")
			frame.Name = "HudKitFrame"
			frame.BackgroundTransparency = 1
			frame.BorderSizePixel = 0
			frame.Active = false
			frame.ScaleType = Enum.ScaleType.Stretch
			frame.Size = UDim2.fromScale(1, 1)
			frame.ZIndex = 1
			frame.Parent = board
		end
		frame.Image = id
	elseif frame then
		frame:Destroy()
	end
end

function SidebarTheme.init(parent)
	root = parent
	HudTheme.onSkin(apply)
	task.defer(function() apply(HudTheme.skin()) end)
end

SidebarTheme.apply = apply

return SidebarTheme
