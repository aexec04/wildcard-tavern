--[[
	Client/PlayFeltShade.lua
	Shading over the felt only (never the rail, deck or plates): a resting stack of card-backs at the centre, four dark edge glows and four dark corner glows (far corners about 10 percent darker)
	and a tiled seamless grain image at 8 to 12 percent once `play_felt_grain` has an Image id in PlaySceneArt. Everything sits in
	one clipped frame that PlayScenePaint sizes to the measured felt rect, above the painted table and below the cards.
	Numbers: Engine/PlayMotion FELT and cornerGlows (tested). No motion, so calm mode keeps it as is.

	install(root, art) -> { frame, apply(rect or nil) }   rect = { x, y, w, h } in root pixels
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PM = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayMotion"))
local SoftGlow = require(script.Parent.SoftGlow)

local M = {}

function M.install(root, art)
	local frame = Instance.new("Frame")
	frame.Name = "PlayFeltShade"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.ClipsDescendants = true
	frame.ZIndex = 0
	frame.Visible = false
	frame.Parent = root

	local fill = Instance.new("Frame") -- code-drawn felt for painted fronts without one (PlayTableLayout.fillOf), bottom of the stack
	fill.Name = "SetFelt"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.Visible = false
	fill.ZIndex = 0
	fill.Parent = frame
	local stitch = Instance.new("Frame")
	stitch.Name = "Stitch"
	stitch.Position = UDim2.fromOffset(6, 6)
	stitch.Size = UDim2.new(1, -12, 1, -12)
	stitch.BackgroundTransparency = 1
	stitch.BorderSizePixel = 0
	stitch.Active = false
	stitch.ZIndex = 0
	stitch.Parent = fill
	local stitchLine = Instance.new("UIStroke")
	stitchLine.Thickness = 1
	stitchLine.Transparency = 0.5
	stitchLine.Parent = stitch

	local grainId = type(art) == "table" and art.play_felt_grain or nil
	if grainId and grainId ~= "" then
		local grain = Instance.new("ImageLabel")
		grain.Name = "Grain"
		grain.BackgroundTransparency = 1
		grain.BorderSizePixel = 0
		grain.Active = false
		grain.Size = UDim2.fromScale(1, 1)
		grain.Image = grainId
		grain.ScaleType = Enum.ScaleType.Tile
		grain.TileSize = UDim2.fromOffset(PM.FELT.grainTile, PM.FELT.grainTile)
		grain.ImageTransparency = 1 - PM.FELT.grainOpacity
		grain.ZIndex = 0
		grain.Parent = frame
	end

	local corners = {}
	for i = 1, 4 do
		corners[i] = SoftGlow.build(frame, {
			name = "Corner" .. i, color = Color3.fromRGB(8, 14, 8), position = UDim2.fromOffset(0, 0),
			size = UDim2.fromOffset(10, 10), peak = PM.FELT.cornerPeak, zIndex = 0,
		})
	end

	local edges = {}
	for i = 1, 4 do
		edges[i] = SoftGlow.build(frame, {
			name = "Edge" .. i, color = Color3.fromRGB(8, 14, 8), position = UDim2.fromOffset(0, 0),
			size = UDim2.fromOffset(10, 10), peak = PM.FELT.edgePeak, zIndex = 0,
		})
	end

	-- a small resting stack of played cards on the felt centre: card-backs with fixed tilts, low contrast, under the cards in play
	local stack = Instance.new("Folder")
	stack.Name = "RestStack"
	stack.Parent = frame
	local stackCards = {}
	for i = 1, #PM.REST_STACK do
		local c = Instance.new("Frame")
		c.Name = "Card" .. i
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		local sh = Instance.new("Frame") -- soft contact shadow just under the card, rotated with it
		sh.Name = "Shadow"
		sh.Size = UDim2.new(1, 2, 1, 2)
		sh.Position = UDim2.fromOffset(PM.REST_BACK.shadowOffset - 1, PM.REST_BACK.shadowOffset - 1)
		sh.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		sh.BackgroundTransparency = PM.REST_BACK.shadowTransparency
		sh.BorderSizePixel = 0
		sh.Active = false
		sh.ZIndex = 0
		sh.Parent = c
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0, 6)
		sc.Parent = sh
		c.BackgroundColor3 = Color3.fromRGB(PM.REST_BACK.navy[1], PM.REST_BACK.navy[2], PM.REST_BACK.navy[3])
		c.BackgroundTransparency = 0
		c.BorderSizePixel = 0
		c.Active = false
		c.ZIndex = 0
		c.Parent = stack
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = c
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(PM.REST_BACK.gold[1], PM.REST_BACK.gold[2], PM.REST_BACK.gold[3])
		edge.Thickness = 1.5
		edge.Transparency = 0
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = c
		stackCards[i] = c
	end
	-- the top card wears the deck's own back (navy with the gold compass star) so the stack matches the draw pile
	pcall(function()
		local backId = require(script.Parent.ArtAssets).cardBackTemplate
		if backId and backId ~= "" and stackCards[#stackCards] then
			local top = stackCards[#stackCards]
			local img = Instance.new("ImageLabel")
			img.Name = "BackArt"
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.BorderSizePixel = 0
			img.Active = false
			img.Image = backId
			img.ScaleType = Enum.ScaleType.Stretch
			img.ImageTransparency = 0
			img.ZIndex = 0
			img.Parent = top
			local ic = Instance.new("UICorner")
			ic.CornerRadius = UDim.new(0, 5)
			ic.Parent = img
		end
	end)

	local linkBack = function() end
	-- the played stack wears the equipped back: mirror the draw pile's CardBackArt (image, crop mode, tint) and follow its changes
	do
		local linked = false
		local function link()
			if linked then return end
			local gui = frame:FindFirstAncestorOfClass("ScreenGui")
			local src = gui and gui:FindFirstChild("CardBackArt", true)
			local top = stackCards[#stackCards]
			if not (src and top and src:IsA("ImageLabel")) then return end
			linked = true
			local art = top:FindFirstChild("BackArt")
			if not art then
				art = Instance.new("ImageLabel")
				art.Name = "BackArt"
				art.Size = UDim2.fromScale(1, 1)
				art.BackgroundTransparency = 1
				art.BorderSizePixel = 0
				art.Active = false
				art.ZIndex = 0
				art.Parent = top
				local ic = Instance.new("UICorner")
				ic.CornerRadius = UDim.new(0, 5)
				ic.Parent = art
			end
			local function sync()
				if src.Image ~= "" then art.Image = src.Image end
				art.ScaleType = src.ScaleType
				art.ImageColor3 = src.ImageColor3
			end
			sync()
			src:GetPropertyChangedSignal("Image"):Connect(sync)
			src:GetPropertyChangedSignal("ImageColor3"):Connect(sync)
		end
		frame.AncestryChanged:Connect(link)
		task.defer(link)
		linkBack = link
	end

	local api = { frame = frame }
	function api.setFill(f) -- nil hides it
		fill.Visible = f ~= nil
		if f then
			fill.BackgroundColor3 = Color3.fromRGB(f.color[1], f.color[2], f.color[3])
			fill.BackgroundTransparency = f.transparency
			stitchLine.Color = Color3.fromRGB(f.stitch[1], f.stitch[2], f.stitch[3])
		end
	end
	local reported = false
	function api.apply(rect, clipped)
		if not rect then frame.Visible = false return end
		linkBack()
		frame.Position = UDim2.fromOffset(rect.x, rect.y)
		frame.Size = UDim2.fromOffset(rect.w, rect.h)
		frame.Visible = true
		-- glows centred on a clip line (the line under the left HUD) would end in a hard dark rectangle edge: when the felt is
		-- clipped on the left, the left corner glows and the left edge glow are not drawn (PM.shadeGlows decides, tested)
		local show = PM.shadeGlows(clipped)
		for i, g in ipairs(PM.cornerGlows(0, 0, rect.w, rect.h)) do
			corners[i].root.Visible = show.corners[i]
			corners[i].root.Position = UDim2.fromOffset(g[1], g[2])
			corners[i].root.Size = UDim2.fromOffset(g[3], g[3])
		end
		for i, g in ipairs(PM.edgeGlows(0, 0, rect.w, rect.h)) do
			edges[i].root.Visible = show.edges[i]
			edges[i].root.Position = UDim2.fromOffset(g[1], g[2])
			edges[i].root.Size = UDim2.fromOffset(g[3], g[3])
		end
		if not reported and game:GetService("RunService"):IsStudio() then
			reported = true
			print(string.format("[PlayFeltShade] frame x=%d y=%d w=%d h=%d leftClipped=%s bgTransparency=%s", rect.x, rect.y, rect.w, rect.h, tostring(clipped == true), tostring(frame.BackgroundTransparency)))
		end
		for i, c in ipairs(PM.restStack(rect.w, rect.h)) do
			stackCards[i].Position = UDim2.fromOffset(c[1], c[2])
			stackCards[i].Size = UDim2.fromOffset(c[3], c[4])
			stackCards[i].Rotation = c[5]
		end
	end
	return api
end

return M
