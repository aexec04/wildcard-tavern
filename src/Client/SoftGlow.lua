--[[
	Client/SoftGlow.lua
	The one soft radial glow helper (fire, lanterns, candles, light pools). Stacked discs with a smoothstep falloff
	from Engine/GlowCurve (32 steps), so no ring edge shows. This is the only file that stacks discs.

	build(parent, { name, color, position = UDim2, size = UDim2, peak = 0.2, inner = 0..0.9, zIndex }) -> { root, rings, setPeak(peak) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GlowCurve = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GlowCurve"))

-- ClientSettings is read lazily (pcall) so a module that builds without the settings module still draws
local function settings()
	local ok, cs = pcall(function() return require(script.Parent.ClientSettings) end)
	return ok and cs or nil
end
local function perfRaw()
	local cs = settings()
	local ok, v = pcall(function() return cs.getRaw("performanceMode") end)
	return ok and v or false
end

local SoftGlow = {}

local function apply(rings, peak, inner)
	local spec = GlowCurve.rings(#rings, peak, inner)
	for i, ring in ipairs(rings) do ring.BackgroundTransparency = spec[i].transparency end
end

function SoftGlow.build(parent, opts)
	local root = Instance.new("Frame")
	root.Name = opts.name or "SoftGlow"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = opts.position
	root.Size = opts.size
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Active = false
	root.ClipsDescendants = false
	root.ZIndex = opts.zIndex or 1
	root.Parent = parent
	local perfOn = perfRaw() == true -- Performance mode: no discs are built
	root.Visible = not perfOn
	local cs = settings()
	if cs and type(cs.onChanged) == "function" then
		cs.onChanged(function(key, value)
			if key == "performanceMode" and root.Parent then root.Visible = value ~= true end
		end)
	end
	local spec = GlowCurve.rings(GlowCurve.DEFAULT_STEPS, opts.peak, opts.inner)
	local rings = {}
	for i, s in ipairs(spec) do
		if perfOn then break end
		local d = Instance.new("Frame")
		d.Name = "Ring" .. i
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(0.5, 0.5)
		d.Size = UDim2.fromScale(s.size, s.size)
		d.BackgroundColor3 = opts.color
		d.BackgroundTransparency = s.transparency
		d.BorderSizePixel = 0
		d.Active = false
		d.ZIndex = opts.zIndex or 1
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = d
		d.Parent = root
		rings[i] = d
	end
	return { root = root, rings = rings, setPeak = function(peak) apply(rings, peak, opts.inner) end }
end

return SoftGlow
