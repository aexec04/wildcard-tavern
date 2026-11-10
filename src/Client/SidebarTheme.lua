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

local function remember(inst, attr, value)
	if inst:GetAttribute(attr) == nil then inst:SetAttribute(attr, value) end
	return inst:GetAttribute(attr)
end

local function paint(inst, p)
	if inst:IsA("GuiObject") and inst.BackgroundTransparency < 1 then
		local orig = remember(inst, "HudOrigBg", inst.BackgroundColor3)
		local role = FILL[key(orig)]
		if role then inst.BackgroundColor3 = p and c3(p[role]) or orig end
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
	for _, top in ipairs({ board, side }) do
		if top then
			paint(top, p)
			for _, d in ipairs(top:GetDescendants()) do
				paint(d, p)
			end
		end
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

function SidebarTheme.init(parent)
	root = parent
	HudTheme.onSkin(apply)
	task.defer(function() apply(HudTheme.skin()) end)
end

SidebarTheme.apply = apply

return SidebarTheme
