--[[
	Client/Gameplay2FlairFX.lua
	Gameplay v2: the hand name flair above the centre score (numbers in Engine/Gameplay2Flair, tested). One FxLoop job per hand,
	no tweens: the name slams in (1.4x, squash, settle) in 40 px gold serif, a light bar sweeps across it, better hands add a gold
	underline wipe, a burst or a brief gold vignette on the screen edge, and a one hand Target kill adds a small OVERKILL plate.
	Under 1.2 s in all and a tap skips it. Calm mode, Reduce motion and Fast speed with no room for motion: the text only, 1 s.
	It takes no clicks and sits above the numeral, below the Patron row.

	show(layer, stage, avoidBottom, handName, over, chips, mult)   layer is the table's frame, stage the centre rect, avoidBottom the
	                                                  bottom of the Patron row's last row, over true when one hand beat the Target;
	                                                  chips and mult (the hand's own) show on two small plates beside the name banner
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Flair = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Gameplay2Flair"))
local FxLoop = require(script.Parent.FxLoop)
local Kit = require(script.Parent.TavernKit)
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local GOLD, DARK, CREAM = Color3.fromRGB(246, 196, 70), Color3.fromRGB(34, 22, 12), Color3.fromRGB(250, 240, 220)
local Z = 8
local live -- { root, job, conn }: only one flair at a time, a new hand replaces it

local function frame(parent, name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = Z
	f.Parent = parent
	return f
end

local function corner(f, r)
	local u = Instance.new("UICorner")
	u.CornerRadius = UDim.new(0, r)
	u.Parent = f
end

local function stop()
	if not live then return end
	if live.job then live.job.cancel() end
	if live.conn then live.conn:Disconnect() end
	if live.root then live.root:Destroy() end
	if live.cleanup then live.cleanup() end
	if live.edge then live.edge:Destroy() end
	live = nil
end

function M.show(layer, stage, avoidBottom, handName, over, chips, mult)
	stop()
	if not layer or not layer.Parent or not handName or handName == "" then return end
	local size = Flair.fontSize(stage, avoidBottom)
	if not size then return end
	local still = Kit.still()
	local fast = ClientSettings.get("animSpeed") == "fast"
	local spec = Flair.spec(handName, still, fast, over)
	local rect = Flair.nameRect(stage, avoidBottom, size)
	local root = frame(layer, "HandFlair")
	root.Position = UDim2.fromOffset(rect.x, rect.y)
	root.Size = UDim2.fromOffset(rect.w, rect.h)
	local fades = {} -- { inst, kind } the banner and plates fade out with the name
	local br = Flair.bannerRect(rect, stage, handName, size)
	if br then -- dark ornate banner behind the gold name: dark wood, thin gold edge, a Color-only lighter top
		local b = frame(root, "NameBanner")
		b.Position = UDim2.fromOffset(br.x - rect.x, br.y - rect.y)
		b.Size = UDim2.fromOffset(br.w, br.h)
		b.BackgroundColor3 = Color3.fromRGB(44, 28, 16)
		b.BackgroundTransparency = 0.05
		corner(b, 10)
		local bs = Instance.new("UIStroke"); bs.Color = GOLD; bs.Thickness = 2; bs.Parent = b
		local bg = Instance.new("UIGradient")
		bg.Color = ColorSequence.new(Color3.fromRGB(86, 58, 30), Color3.fromRGB(44, 28, 16))
		bg.Rotation = 90
		bg.Parent = b
		fades[#fades + 1] = { b, "frame" }
		local plates = chips and mult and Flair.sidePlates(br, stage)
		if plates then
			local ct, mt = Flair.sideText(chips, mult)
			for _, def in ipairs({ { "ChipsPlate", plates.chips, ct, Color3.fromRGB(34, 62, 128) }, { "MultPlate", plates.mult, mt, Color3.fromRGB(150, 44, 34) } }) do
				local pl = frame(root, def[1])
				pl.Position = UDim2.fromOffset(def[2].x - rect.x, def[2].y - rect.y)
				pl.Size = UDim2.fromOffset(def[2].w, def[2].h)
				pl.BackgroundColor3 = def[4]
				pl.BackgroundTransparency = 0.05
				corner(pl, 8)
				local ps = Instance.new("UIStroke"); ps.Color = GOLD; ps.Thickness = 1.5; ps.Parent = pl
				local pt = Instance.new("TextLabel")
				pt.BackgroundTransparency = 1; pt.Size = UDim2.fromScale(1, 1)
				pt.Font = Enum.Font.GothamBold; pt.TextSize = 15; pt.TextColor3 = CREAM
				pt.TextTransparency = 0; pt.TextStrokeColor3 = DARK; pt.TextStrokeTransparency = 0.3
				pt.Text = def[3]; pt.ZIndex = Z + 2
				pt.Parent = pl
				fades[#fades + 1] = { pl, "frame" }
				fades[#fades + 1] = { pt, "text" }
			end
		end
	end
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Merriweather
	label.TextSize = size
	label.TextColor3 = GOLD
	label.TextTransparency = 0
	label.TextStrokeColor3 = DARK
	label.TextStrokeTransparency = 0.1
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = handName
	label.ZIndex = Z + 1
	label.Parent = root
	local plate
	local pr = spec.overkill and Flair.overkillRect(rect, stage, handName, size)
	if pr then
		plate = frame(layer, "Overkill")
		plate.Position = UDim2.fromOffset(pr.x, pr.y)
		plate.Size = UDim2.fromOffset(pr.w, pr.h)
		plate.BackgroundTransparency = 0.05
		plate.BackgroundColor3 = Color3.fromRGB(120, 36, 30)
		corner(plate, 12)
		local ps = Instance.new("UIStroke"); ps.Color = GOLD; ps.Thickness = 2; ps.Parent = plate
		local pt = Instance.new("TextLabel")
		pt.BackgroundTransparency = 1; pt.Size = UDim2.fromScale(1, 1)
		pt.Font = Enum.Font.Merriweather; pt.TextSize = 16; pt.TextColor3 = CREAM
		pt.TextStrokeColor3 = DARK; pt.TextStrokeTransparency = 0.3; pt.Text = "OVERKILL"; pt.ZIndex = Z + 2
		pt.Parent = plate
	end
	live = { root = root }
	if spec.static then
		-- the text only, held 1 s (a Calm mode player sees the name and the OVERKILL plate, nothing moves)
		local mine = live
		task.delay(spec.hold, function()
			if live == mine then stop() end
		end)
		if plate then live.edge = plate end
		return
	end
	if plate then live.edge = plate; plate.Visible = false end
	local scale = Instance.new("UIScale"); scale.Parent = label
	local clip = frame(root, "SweepClip")
	clip.Size = UDim2.fromScale(1, 1)
	clip.ClipsDescendants = true
	local bar = frame(clip, "Sweep")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Size = UDim2.new(0, math.max(10, math.floor(size * 0.4)), 1.6, 0)
	bar.Rotation = 20
	bar.BackgroundColor3 = CREAM
	bar.BackgroundTransparency = 1
	local under
	if spec.underline > 0 then
		under = frame(layer, "FlairUnderline")
		under.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y + rect.h - 1)
		under.AnchorPoint = Vector2.new(0.5, 0)
		under.Size = UDim2.fromOffset(0, 3)
		under.BackgroundColor3 = GOLD
		under.BackgroundTransparency = 0
		live.under = under
	end
	local dots = {}
	for i = 1, spec.burst do
		local d = frame(layer, "FlairDot")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(6, 6)
		d.BackgroundColor3 = GOLD
		d.BackgroundTransparency = 1
		corner(d, 3)
		dots[i] = d
	end
	local edge, edgeStroke
	if spec.vignette > 0 then
		local gui = layer:FindFirstAncestorOfClass("ScreenGui")
		if gui then
			edge = frame(gui, "FlairVignette")
			edge.ZIndex = 4
			edge.Position = UDim2.fromOffset(10, 10)
			edge.Size = UDim2.new(1, -20, 1, -20)
			corner(edge, 24)
			edgeStroke = Instance.new("UIStroke")
			edgeStroke.Color = GOLD; edgeStroke.Thickness = 22; edgeStroke.Transparency = 1
			edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edgeStroke.Parent = edge
		end
	end
	local mine = live
	mine.cleanup = function()
		for _, d in ipairs(dots) do d:Destroy() end
		if under then under:Destroy() end
		if edge then edge:Destroy() end
		if plate then plate:Destroy() end
	end
	local t0 = os.clock()
	local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
	local function finish()
		if live == mine then
			mine.cleanup()
			live = nil
			if mine.conn then mine.conn:Disconnect() end
			if mine.job then mine.job.cancel() end
			root:Destroy()
		end
	end
	mine.conn = UserInputService.InputBegan:Connect(function(input)
		local ty = input.UserInputType
		if ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch then finish() end -- a tap skips it
	end)
	local sl = spec.slam
	mine.job = FxLoop.add(function(_, now)
		if live ~= mine or not root.Parent then return true end
		local e = now - t0
		-- slam: 1.4 down to 1.12 (squash), then settle to 1
		if e < sl.down then scale.Scale = 1.4 + (1.12 - 1.4) * (e / sl.down)
		elseif e < sl.down + sl.settle then scale.Scale = 1.12 + (1 - 1.12) * ((e - sl.down) / sl.settle)
		else scale.Scale = 1 end
		local sweepStart = 0.1
		if e >= sweepStart and e <= sweepStart + spec.sweep then
			local f = (e - sweepStart) / spec.sweep
			bar.Position = UDim2.new(-0.1 + 1.2 * f, 0, 0.5, 0)
			bar.BackgroundTransparency = 0.55
		else
			bar.BackgroundTransparency = 1
		end
		if under then
			local f = math.max(0, math.min(1, (e - 0.3) / spec.underline))
			under.Size = UDim2.fromOffset(math.floor(rect.w * 0.5 * f), 3)
		end
		if #dots > 0 then
			local f = math.max(0, math.min(1, (e - 0.3) / 0.4))
			for i, d in ipairs(dots) do
				local a = (i / #dots) * math.pi * 2
				local dist = 30 + 70 * f
				d.Position = UDim2.fromOffset(cx + math.cos(a) * dist, cy + math.sin(a) * dist * 0.5)
				d.BackgroundTransparency = (f <= 0 or f >= 1) and 1 or 0.1 + 0.9 * f
			end
		end
		if edgeStroke then
			local f = math.min(1, e / spec.vignette)
			edgeStroke.Transparency = f >= 1 and 1 or 0.55 + 0.45 * f
		end
		if plate then plate.Visible = e >= 0.35 end
		local fade = spec.total - 0.2
		if e > fade then
			local a = math.min(1, (e - fade) / 0.2)
			label.TextTransparency, label.TextStrokeTransparency = a, 0.1 + 0.9 * a
			if under then under.BackgroundTransparency = a end
			if plate then plate.BackgroundTransparency = 0.05 + 0.95 * a end
			for _, f in ipairs(fades) do
				if f[2] == "frame" then f[1].BackgroundTransparency = 0.05 + 0.95 * a
				else f[1].TextTransparency, f[1].TextStrokeTransparency = a, 0.3 + 0.7 * a end
			end
		end
		if e >= spec.total then
			finish()
			return true
		end
		return false
	end, 1 / 30)
end

return M
