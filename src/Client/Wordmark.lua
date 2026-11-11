--[[
	Client/Wordmark.lua
	The Menu title: the game name only, no tagline. Code-drawn by default (muted gold gradient text with a dark outline and a
	small drawn diamond flourish on each side); when Engine/LogoArt.lua has a logo_wordmark id the painted wordmark replaces
	the lettering automatically (the label keeps its name and size so MenuTitleHider and the parallax keep working).

	Wordmark.build(parent, opts) -> { shadow = TextLabel, title = TextLabel, painted = bool }
	  opts = { name = string?, imageId = number|string|nil, zIndex = number? }
	Rules (calm direction): Color-only gradient (never Transparency), no flicker, no glow.
]]

local GameName = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GameName"))
local ImageSpace = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ImageSpace"))
local AssetId =require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("AssetId"))

local Wordmark = {}

-- Chosen to read well on a dark wall at 1920x1080 and on a phone. Swap here if Studio shows a better one
-- (Almendra and IMFellEnglishSC are the other candidates).
Wordmark.FONT = Enum.Font.Fondamento
Wordmark.TEXT_SIZE = 56

local GOLD_TOP = Color3.fromRGB(236, 205, 134)
local GOLD_BOTTOM = Color3.fromRGB(184, 146, 80)
local OUTLINE = Color3.fromRGB(46, 30, 14)

local function baseLabel(name, z)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, 80)
	label.BackgroundTransparency = 1
	label.Font = Wordmark.FONT
	label.TextSize = Wordmark.TEXT_SIZE
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	label.Active = false
	label.ZIndex = z
	return label
end

local function flourish(parent, side, z)
	-- a small gilded diamond (rotated square) with a thin dark rim; a child of the title so it hides with it
	local gem = Instance.new("Frame")
	gem.Name = "Flourish" .. side
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Size = UDim2.fromOffset(14, 14)
	gem.Rotation = 45
	gem.BackgroundColor3 = GOLD_BOTTOM
	gem.BorderSizePixel = 0
	gem.ZIndex = z
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 1.5
	stroke.Parent = gem
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = GOLD_TOP
	dot.BorderSizePixel = 0
	dot.ZIndex = z
	dot.Parent = gem
	gem.Parent = parent
	return gem
end

function Wordmark.build(parent, opts)
	opts = opts or {}
	local z = opts.zIndex or 11
	local name = GameName.NAME
	local painted = opts.imageId ~= nil and tostring(opts.imageId) ~= ""

	local shadow = baseLabel("MenuTitleShadow", z - 1)
	shadow.Position = UDim2.new(0, 3, 0, 23)
	shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
	shadow.TextTransparency = 0.75
	shadow.Text = painted and "" or name
	shadow.Parent = parent

	local title = baseLabel("MenuTitle", z)
	title.Position = UDim2.new(0, 0, 0, 20)
	title.Parent = parent

	if painted then
		title.Text = ""
		local image = Instance.new("ImageLabel")
		image.Name = "WordmarkImage"
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromOffset(480, 72) -- the crop below is about 6.6:1
		image.BackgroundTransparency = 1
		image.Image = AssetId.normalize(opts.imageId) or ""
		-- the painted wordmark is a 1536x1024 canvas with one centred line; show only the band that holds the lettering
		local rx, ry, rw, rh = ImageSpace.rect(40, 390, 1456, 220, 1536, 1024)
		image.ImageRectOffset = Vector2.new(rx, ry)
		image.ImageRectSize = Vector2.new(rw, rh)
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = z
		image.Parent = title
		return { shadow = shadow, title = title, painted = true }
	end

	title.Text = name
	title.TextColor3 = Color3.new(1, 1, 1) -- the gradient supplies the colour
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, GOLD_TOP),
		ColorSequenceKeypoint.new(1, GOLD_BOTTOM),
	})
	gradient.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = title

	local left, right = flourish(title, "Left", z), flourish(title, "Right", z)
	local function place()
		local half = title.TextBounds.X / 2 + 30
		left.Position = UDim2.new(0.5, -half, 0.5, 0)
		right.Position = UDim2.new(0.5, half, 0.5, 0)
	end
	place()
	title:GetPropertyChangedSignal("TextBounds"):Connect(place)

	return { shadow = shadow, title = title, painted = false }
end

return Wordmark
