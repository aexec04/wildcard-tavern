--[[
	Client/MapHover.lua
	Hover and tap feedback for Tavern Map landmarks, stops and discovery tiles, one shared info card per map canvas.

	  local hover = MapHover.new({ canvas = Frame, TweenService = ..., calm = function() return bool end })
	  hover.bind(guiObject, getInfo, { pin = true })

	getInfo() -> { title, biome, line, done } is read on every hover, so it can honor fog and secrets: return "???" lines
	and the card never leaks what is hidden. `done = true` adds a gold check ("Cleared"). Hover lifts the object 4px and
	brightens its outline (a UIStroke is added when it has none); under calm mode (Reduce Motion) it only brightens, no
	movement. Tapping (pin = true) pins the card as a small detail card until the next tap anywhere on the map or on
	another bound object; objects with their own click behaviour pass pin = false and just get the hover card.
	One card per canvas, destroyed with the canvas. Nothing loops.
]]

local MapHover = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local BRIGHT = Color3.fromRGB(255, 232, 150)
local CREAM = Color3.fromRGB(250, 235, 200)
local DARK = Color3.fromRGB(46, 32, 22)
local Tips = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MapTooltips"))
local CARD_W, CARD_H = Tips.CARD_W, Tips.CARD_H

function MapHover.new(opts)
	local canvas = opts.canvas
	local TweenService = opts.TweenService
	local calm = opts.calm or function() return false end

	local card = Instance.new("Frame")
	card.Name = "MapHoverCard"
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = DARK
	card.BorderSizePixel = 0
	card.Visible = false
	card.Active = false
	card.ZIndex = 60
	card.Parent = canvas
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = card

	local function line(y, h, size, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(12, y)
		l.Size = UDim2.new(1, -24, 0, h)
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.TextWrapped = true
		l.ZIndex = 61
		l.Parent = card
		return l
	end
	local titleLabel = line(8, 24, 18, CREAM)
	local biomeLabel = line(34, 20, 15, GOLD)
	local bodyLabel = line(56, Tips.BODY_H, Tips.BODY_SIZE, CREAM)
	bodyLabel.Font = Enum.Font.GothamMedium

	local pinnedTarget
	local shownFor

	local function place(target)
		local pos, size = target.Position, target.AbsoluteSize
		local anchor = target.AnchorPoint
		local cx = pos.X.Offset + (0.5 - anchor.X) * size.X
		local top = pos.Y.Offset - anchor.Y * size.Y
		local c = canvas.AbsoluteSize
		local r = Tips.place(cx, top, size.Y, c.X, c.Y > 0 and c.Y or math.huge) -- always inside the map canvas
		card.AnchorPoint = Vector2.new(0, 0)
		card.Position = UDim2.fromOffset(r.x, r.y)
	end

	local function show(target, getInfo)
		local ok, info = pcall(getInfo)
		if not ok or type(info) ~= "table" then return end
		titleLabel.Text = info.title or "???"
		biomeLabel.Text = info.biome or "???"
		bodyLabel.Text = (info.done and Tips.CLEARED or "") .. (info.line or "")
		place(target)
		card.Visible = true
		shownFor = target
	end

	local function hide(target)
		if pinnedTarget then return end
		if target == nil or shownFor == target then
			card.Visible = false
			shownFor = nil
		end
	end

	-- a tap anywhere else on the map unpins the card
	canvas.InputBegan:Connect(function(input)
		if pinnedTarget and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			pinnedTarget = nil
			card.Visible = false
			shownFor = nil
		end
	end)

	local self = {}

	function self.bind(target, getInfo, bindOpts)
		bindOpts = bindOpts or {}
		-- noGlow: the object recolors its own outline by state (map nodes), so only lift it and show the card
		local glow = (not bindOpts.noGlow) and target:FindFirstChildOfClass("UIStroke") or nil
		if not glow and not bindOpts.noGlow then
			glow = Instance.new("UIStroke")
			glow.Color = BRIGHT
			glow.Thickness = 2
			glow.Transparency = 1
			glow.Parent = target
		end
		local baseColor = glow and glow.Color
		local baseThickness = glow and glow.Thickness or 0
		local baseTransparency = glow and glow.Transparency or 1
		local baseY = target.Position.Y
		local lifted = false

		local function enter()
			show(target, getInfo)
			if lifted then return end
			lifted = true
			baseY = target.Position.Y
			if glow then
				glow.Color = BRIGHT
				glow.Transparency = 0
				glow.Thickness = baseThickness + 1.5
			end
			if not calm() then
				TweenService:Create(target, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = UDim2.new(target.Position.X.Scale, target.Position.X.Offset, baseY.Scale, baseY.Offset - 4) }):Play()
			end
		end
		local function leave()
			hide(target)
			if not lifted then return end
			lifted = false
			if glow then
				glow.Color = baseColor
				glow.Thickness = baseThickness
				glow.Transparency = baseTransparency
			end
			if not calm() then
				TweenService:Create(target, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = UDim2.new(target.Position.X.Scale, target.Position.X.Offset, baseY.Scale, baseY.Offset) }):Play()
			else
				target.Position = UDim2.new(target.Position.X.Scale, target.Position.X.Offset, baseY.Scale, baseY.Offset)
			end
		end
		target.MouseEnter:Connect(enter)
		target.MouseLeave:Connect(leave)
		if bindOpts.pin then
			target.Active = true
			target.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if pinnedTarget == target then
						pinnedTarget = nil
						card.Visible = false
						shownFor = nil
					else
						pinnedTarget = nil
						show(target, getInfo)
						pinnedTarget = target
					end
				end
			end)
		end
	end

	return self
end

return MapHover
