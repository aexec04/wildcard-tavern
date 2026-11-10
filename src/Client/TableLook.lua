--[[
	Client/TableLook.lua
	The code-drawn look of the gameplay table, stacked above the scene painting (GameplayScene) and
	below the UI. It only draws what Engine/TableStyle.resolve returns:

	  Grade     flat biome colour wash (BackgroundTransparency = 1 - strength; never UIGradient Transparency)
	  Warm      a faint warm wash that grows with the Night
	  Darken    a black wash that grows with the Night (and on boss rounds)
	  TableLook the host the equipped Cosmetic Set's backdropStyle is drawn on (CosmeticSetsView attaches
	            Client/BackdropStyles to the frame named "TableLook"), so a set is visible on the table
	  Vignette  smooth gradient edges (SmoothVignette) behind the card row (bottom) and at the sides; heavier on boss rounds

	Changes crossfade (0.7s) so the travel transition shows no pop; Fast / Reduce shake apply at once.
	Nothing here is ever red. Click-through (Active = false). Everything sits at ZIndex 0.

	new(root) -> { apply(look, instant) }
]]

local TweenService = game:GetService("TweenService")
local ClientSettings = require(script.Parent.ClientSettings)
local SmoothVignette = require(script.Parent.SmoothVignette)
local VignetteCurve = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("VignetteCurve"))

local TableLook = {}

-- Edge darkness equals the old stack of 8 bottom / 4 side layers.
local BASE_BOTTOM_STEPS, BASE_SIDE_STEPS = 8, 4
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

	-- one smooth gradient frame per edge (Client/SmoothVignette); apply() sets each edge's strength
	local edges = SmoothVignette.build(layers, {
		name = "Vignette", zIndex = 0, color = Color3.fromRGB(10, 6, 4),
		bottom = { strength = 0.5, extent = 0.6 },
		left = { strength = 0.5, extent = 0.16 },
		right = { strength = 0.5, extent = 0.16 },
	})
	for _, f in pairs(edges.frames) do f.BackgroundTransparency = 1 end

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
		local bottomOpacity = VignetteCurve.stacked(look.vignette.bottom * 0.22, BASE_BOTTOM_STEPS)
		local sideOpacity = VignetteCurve.stacked(look.vignette.sides * 0.25, BASE_SIDE_STEPS)
		set(edges.frames.bottom, { BackgroundTransparency = 1 - bottomOpacity }, instant)
		set(edges.frames.left, { BackgroundTransparency = 1 - sideOpacity }, instant)
		set(edges.frames.right, { BackgroundTransparency = 1 - sideOpacity }, instant)
	end

	return M
end

return TableLook
