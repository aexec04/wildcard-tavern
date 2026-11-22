--[[
	Client/PatronJuiceFX.lua
	Gameplay v2: the trigger effect of one Patron, by tier (numbers in Engine/PatronJuice, tested). Every effect is a Frame,
	UIStroke or text driven by ONE FxLoop job per trigger, never a tween per particle. Calm mode, Reduce motion and Fast speed:
	only the floating pill text, held 0.4 s, no motion and no effect. Nothing here takes clicks.

	play(slot, tier, kind, amount, rim)   slot is the card's slot frame; rim a Color3 for the pill edge
	hopPx(tier)                           the card hop in pixels for this tier (nil when still)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Juice = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronJuice"))
local FxLoop = require(script.Parent.FxLoop)
local Kit = require(script.Parent.TavernKit)

local M = {}

local CREAM, DARK = Color3.fromRGB(250, 240, 220), Color3.fromRGB(34, 22, 12)
local GREEN, BLUE, PURPLE, GOLD = Color3.fromRGB(110, 210, 130), Color3.fromRGB(120, 180, 255), Color3.fromRGB(190, 130, 240), Color3.fromRGB(246, 206, 112)

local function frame(parent, name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function corner(f, r)
	local u = Instance.new("UICorner")
	u.CornerRadius = UDim.new(0, r)
	u.Parent = f
end

local function stroke(f, color, thickness, trans)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = trans
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return s
end

function M.hopPx(tier)
	if Kit.still() then return nil end
	return Juice.spec(tier, false).hop
end

local function pill(slot, text, rim, calm, spec)
	local p = frame(slot, "JuicePill", 60)
	-- under the Patron's tag rows (Gameplay2Layout.triggerPillY), never above the row where the top bar is
	local pillY = -4
	pcall(function()
		local host = slot.Parent and slot.Parent.AbsoluteSize
		if host and host.X > 0 and host.Y > 0 then
			pillY = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Gameplay2Layout")).triggerPillY(host.X, host.Y)
		end
	end)
	p.AnchorPoint = Vector2.new(0.5, 0)
	p.AutomaticSize = Enum.AutomaticSize.X
	p.Size = UDim2.fromOffset(0, 28)
	p.Position = UDim2.new(0.5, 0, 0, pillY)
	p.BackgroundTransparency = 0.08
	p.BackgroundColor3 = DARK
	corner(p, 14)
	local rimStroke = stroke(p, rim or GOLD, 2, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.new(0, 0, 1, 0)
	t.Font = Enum.Font.Merriweather
	t.TextSize = 16
	t.TextColor3 = CREAM
	t.TextTransparency = 0
	t.TextStrokeColor3 = DARK
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.ZIndex = 61
	t.Parent = p
	return p, t, rimStroke
end

function M.play(slot, tier, kind, amount, rim)
	if not slot or not slot.Parent then return end
	local calm = Kit.still()
	local spec = Juice.spec(tier, calm)
	local text = Juice.pillText(kind, amount)
	local fx = frame(slot.Parent, "JuiceFX", 55) -- beside the slot (same parent), so the slot's own clipping never cuts the pill
	fx.Position = slot.Position
	fx.Size = slot.Size
	local p, t, rimStroke
	if text ~= "" then p, t, rimStroke = pill(fx, text, rim, calm, spec) end
	if calm then
		-- static: the pill text only, held 0.4 s
		task.delay(spec.pill.dur, function() if fx.Parent then fx:Destroy() end end)
		return
	end
	local n = Juice.rank(tier)
	local ringStroke, sweep, crown, rays, sparks, edge, edgeStroke = nil, nil, nil, {}, {}, nil, nil
	if n >= 2 then
		local r = frame(fx, "Ring", 56)
		r.Size = UDim2.fromScale(1, 1)
		corner(r, 12)
		ringStroke = stroke(r, GREEN, 5, 1)
	end
	if n >= 3 then
		local clip = frame(fx, "SweepClip", 56)
		clip.Size = UDim2.fromScale(1, 1)
		clip.ClipsDescendants = true
		corner(clip, 12)
		sweep = frame(clip, "Sweep", 56)
		sweep.AnchorPoint = Vector2.new(0.5, 0.5)
		sweep.Size = UDim2.new(0, 18, 1.6, 0)
		sweep.Rotation = 20
		sweep.BackgroundColor3 = BLUE
		sweep.BackgroundTransparency = 1
	end
	if n >= 4 then
		for i = 1, spec.sparks do
			local d = frame(fx, "Spark" .. i, 58)
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Size = UDim2.fromOffset(5, 5)
			d.BackgroundColor3 = PURPLE
			d.BackgroundTransparency = 1
			corner(d, 3)
			sparks[i] = d
		end
		crown = frame(fx, "CrownFlash", 57)
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Position = UDim2.new(0.5, 0, 0, 0)
		crown.Size = UDim2.fromOffset(34, 34)
		crown.Rotation = 45
		crown.BackgroundColor3 = GOLD
		crown.BackgroundTransparency = 1
		corner(crown, 4)
	end
	if n >= 5 then
		local rayLen = Juice.rayLen(slot.AbsoluteSize.X, slot.AbsoluteSize.Y)
		for i = 1, 6 do
			local r = frame(fx, "Ray" .. i, 54)
			r.AnchorPoint = Vector2.new(0.5, 1)
			r.Position = UDim2.fromScale(0.5, 0.5)
			r.Size = UDim2.new(0, 4, rayLen, 0)
			r.Rotation = -75 + 30 * (i - 1)
			r.BackgroundColor3 = GOLD
			r.BackgroundTransparency = 1
			rays[i] = r
		end
		local gui = slot:FindFirstAncestorOfClass("ScreenGui")
		if gui then
			edge = frame(gui, "JuiceEdge", 5)
			edge.Position = UDim2.fromOffset(10, 10)
			edge.Size = UDim2.new(1, -20, 1, -20)
			corner(edge, 24)
			edgeStroke = stroke(edge, GOLD, 18, 1)
		end
	end
	local total = math.max(spec.dur, spec.pill.dur, spec.crown, spec.edge)
	local t0 = os.clock()
	FxLoop.add(function(_, now)
		local e = now - t0
		if not fx.Parent then
			if edge then edge:Destroy() end
			return true
		end
		local function frac(d) return d > 0 and math.min(1, e / d) or 1 end
		if p then -- rises 24 px and fades over 0.6 s, the rim fades with it
			local f = frac(spec.pill.dur)
			p.Position = UDim2.new(0.5, 0, 0, -4 - spec.pill.rise * f)
			local a = f > 0.5 and (f - 0.5) * 2 or 0
			p.BackgroundTransparency = 0.08 + 0.92 * a
			t.TextTransparency, t.TextStrokeTransparency = a, 0.3 + 0.7 * a
			rimStroke.Transparency = a
		end
		if ringStroke then
			local f = frac(spec.ring)
			ringStroke.Transparency = f >= 1 and 1 or 0.2 + 0.8 * f
		end
		if sweep then
			local f = frac(spec.sweep)
			sweep.Position = UDim2.new(-0.1 + 1.2 * f, 0, 0.5, 0)
			sweep.BackgroundTransparency = f >= 1 and 1 or 0.55
		end
		for i, d in ipairs(sparks) do
			local f = frac(spec.dur)
			local x, y = Juice.particle(i, #sparks, f)
			d.Position = UDim2.fromScale(x, y)
			d.BackgroundTransparency = f >= 1 and 1 or 0.1 + 0.9 * f
		end
		if crown then
			local f = frac(spec.crown)
			crown.BackgroundTransparency = f >= 1 and 1 or 0.3 + 0.7 * f
		end
		for _, r in ipairs(rays) do
			local f = frac(spec.rays)
			r.BackgroundTransparency = f >= 1 and 1 or 0.6 + 0.4 * f
		end
		if edgeStroke then
			local f = frac(spec.edge)
			edgeStroke.Transparency = f >= 1 and 1 or 0.7 + 0.3 * f
		end
		if e >= total then
			fx:Destroy()
			if edge then edge:Destroy() end
			return true
		end
		return false
	end, 1 / 30)
end

return M
