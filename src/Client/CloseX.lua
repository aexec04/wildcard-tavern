--[[
	Client/CloseX.lua
	The one round close X for every panel (replaces the wide text Close buttons): a 40 px brass disc with a thin cream cross inside a 44 px
	hit area, top right of the panel frame, hover glow, press nudge, click sound. Escape and the dark area are handled by Client/PopupDismiss.
	Geometry in Engine/CloseXRules (tested).

	CloseX.attach(panel, onClose, opts) -> the hit button (Name "CloseX"); a second call on the same panel returns the first
	  opts.corner "topRight" (default) | "topLeft", opts.inset (8), opts.top (inset), opts.z (60), opts.playClick (function)
	CloseX.retire(oldButton)            -> hides an old text Close button for good (it stays hidden if code flips Visible back on)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CloseXRules"))

local CloseX = {}

local BRASS = Color3.fromRGB(176, 138, 66)
local BRASS_HOVER = Color3.fromRGB(206, 168, 92)
local INK = Color3.fromRGB(34, 24, 16)
local CREAM = Color3.fromRGB(250, 240, 220)

function CloseX.retire(old)
	if not old then return end
	old.Visible = false
	old.Active = false
	old:GetPropertyChangedSignal("Visible"):Connect(function()
		if old.Visible then old.Visible = false end
	end)
end

function CloseX.attach(panel, onClose, opts)
	opts = opts or {}
	local existing = panel:FindFirstChild("CloseX")
	if existing then return existing end
	local inset = opts.inset or Rules.INSET
	local top = opts.top or inset
	local z = opts.z or 60
	local hit = Instance.new("TextButton")
	hit.Name = "CloseX"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.Size = UDim2.fromOffset(Rules.HIT, Rules.HIT)
	if opts.corner == "topLeft" then
		hit.AnchorPoint = Vector2.new(0, 0)
		hit.Position = UDim2.fromOffset(inset, top)
	else
		hit.AnchorPoint = Vector2.new(1, 0)
		hit.Position = UDim2.new(1, -inset, 0, top)
	end
	hit.ZIndex = z
	hit.Parent = panel

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(Rules.DISC, Rules.DISC)
	disc.BackgroundColor3 = BRASS
	disc.BorderSizePixel = 0
	disc.Active = false
	disc.ZIndex = z + 1
	disc.Parent = hit
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = disc
	for i, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Cross" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(20, 3)
		bar.Rotation = rot
		bar.BackgroundColor3 = CREAM
		bar.BorderSizePixel = 0
		bar.Active = false
		bar.ZIndex = z + 2
		bar.Parent = disc
	end

	-- the equipped Card Set's disc colours (accent brass); classic keeps BRASS. Read at each event so a set equipped later applies at once.
	local function discColors()
		local ok, c = pcall(function()
			local CS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
			return CS.closeDiscOf(require(script.Parent.TavernKit).plateSetId())
		end)
		if ok and c then return Color3.fromRGB(c.rest[1], c.rest[2], c.rest[3]), Color3.fromRGB(c.hover[1], c.hover[2], c.hover[3]) end
		return BRASS, BRASS_HOVER
	end
	disc.BackgroundColor3 = (discColors())
	pcall(function() require(script.Parent.HudTheme).onSkin(function() if disc.Parent then disc.BackgroundColor3 = (discColors()) end end) end)
	hit.MouseEnter:Connect(function()
		local _, hover = discColors()
		disc.BackgroundColor3 = hover
		stroke.Color = Color3.fromRGB(255, 214, 120)
	end)
	hit.MouseLeave:Connect(function()
		disc.BackgroundColor3 = (discColors())
		stroke.Color = INK
		disc.Position = UDim2.fromScale(0.5, 0.5)
	end)
	hit.MouseButton1Down:Connect(function() disc.Position = UDim2.new(0.5, 0, 0.5, 1) end)
	hit.MouseButton1Up:Connect(function() disc.Position = UDim2.fromScale(0.5, 0.5) end)
	hit.MouseButton1Click:Connect(function()
		if opts.playClick then opts.playClick() end
		onClose()
	end)
	return hit
end

return CloseX
