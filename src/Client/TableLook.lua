--[[
	Client/TableLook.lua
	The code-drawn look of the gameplay table, stacked above the scene painting (GameplayScene) and
	below the UI. It only draws what Engine/TableStyle.resolve returns:

	  Grade     flat biome colour wash (BackgroundTransparency = 1 - strength; never UIGradient Transparency)
	  Warm      a faint warm wash that grows with the Night
	  Darken    a black wash that grows with the Night (and on boss rounds)
	  TableLook the host the equipped Cosmetic Set's backdropStyle is drawn on (CosmeticSetsView attaches
	            Client/BackdropStyles to the frame named "TableLook"), so a set is visible on the table
	  Vignette  stepped dark strips behind the card row (bottom) and at the sides; heavier on boss rounds

	Changes crossfade (0.7s) so the travel transition shows no pop; Fast / Reduce shake apply at once.
	Nothing here is ever red. Click-through (Active = false). Everything sits at ZIndex 0.

	new(root) -> { apply(look, instant) }
]]

local TweenService = game:GetService("TweenService")
local ClientSettings = require(script.Parent.ClientSettings)

local TableLook = {}

local BOTTOM_STEPS, SIDE_STEPS = 8, 4
local FADE = 0.7

local function solid(parent, name, color)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 0
	f.Parent = parent
	return f
end

function TableLook.new(root)
	local layers = Instance.new("Frame")
	layers.Name = "TableLookLayers"
	layers.Size = UDim2.fromScale(1, 1)
	layers.BackgroundTransparency = 1
	layers.BorderSizePixel = 0
	layers.Active = false
	layers.ZIndex = 0
	layers.Parent = root

	local grade = solid(layers, "Grade", Color3.fromRGB(150, 100, 60))
	local warm = solid(layers, "Warm", Color3.fromRGB(255, 190, 110))
	local darken = solid(layers, "Darken", Color3.fromRGB(10, 6, 4))
	local styleHost = solid(layers, "TableLook", Color3.new(1, 1, 1)) -- BackdropStyles host (transparent itself)

	local bottomStrips, sideStrips = {}, {}
	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.Active = false
	vignette.ZIndex = 0
	vignette.Parent = layers
	local function strip(anchor, pos, size, list)
		local f = Instance.new("Frame")
		f.AnchorPoint = anchor
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = Color3.fromRGB(10, 6, 4)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 0
		f.Parent = vignette
		table.insert(list, f)
	end
	for i = 1, BOTTOM_STEPS do
		strip(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.6 * (1 - (i - 1) / BOTTOM_STEPS)), bottomStrips)
	end
	for i = 1, SIDE_STEPS do
		local w = 0.16 * (1 - (i - 1) / SIDE_STEPS)
		strip(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(w, 1), sideStrips)
		strip(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(w, 1), sideStrips)
	end

	local M = { layers = layers, styleHost = styleHost }

	local function set(inst, props, instant)
		if instant then
			for k, v in pairs(props) do inst[k] = v end
		else
			TweenService:Create(inst, TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
		end
	end

	-- look: the table returned by TableStyle.resolve
	function M.apply(look, instant)
		if type(look) ~= "table" then return end
		instant = instant or ClientSettings.get("animSpeed") == "fast" or ClientSettings.get("reduceShake") == true
		local c = look.grade.color
		grade.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
		set(grade, { BackgroundTransparency = 1 - look.grade.strength }, instant)
		set(warm, { BackgroundTransparency = 1 - look.mood.warm }, instant)
		set(darken, { BackgroundTransparency = 1 - look.mood.darken }, instant)
		local bottomT = 1 - look.vignette.bottom * 0.22
		local sideT = 1 - look.vignette.sides * 0.25
		for _, f in ipairs(bottomStrips) do set(f, { BackgroundTransparency = bottomT }, instant) end
		for _, f in ipairs(sideStrips) do set(f, { BackgroundTransparency = sideT }, instant) end
	end

	return M
end

return TableLook
