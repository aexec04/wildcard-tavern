--[[
	Client/SmoothVignette.lua
	Edge vignettes made of ONE frame per edge, each with a UIGradient Transparency that fades from dark at the
	screen edge to fully clear (curve from Engine/VignetteCurve). No stacked strips, so no frame edge ever falls
	inside the art. This is the one place a Transparency gradient is used on purpose: it is a fade, not a gloss.
	The frame's own BackgroundTransparency is the strength knob (1 - strength), so callers can tween it.

	build(parent, opts) -> { holder, frames = { top, bottom, left, right }, setStrength(edge, strength, instant) }
	  opts.zIndex   (default 0)
	  opts.color    Color3 (default near black)
	  opts.top / bottom / left / right = { strength = 0..0.95, extent = fraction of the area (0..1) }  (omit = none)
	  opts.name     holder name
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VignetteCurve = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("VignetteCurve"))

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

local SmoothVignette = {}

local EDGES = { "top", "bottom", "left", "right" }

local function sequence(reverse)
	local points = VignetteCurve.keypoints()
	local keys = {}
	if reverse then
		for i = #points, 1, -1 do
			keys[#keys + 1] = NumberSequenceKeypoint.new(1 - points[i][1], points[i][2])
		end
	else
		for _, p in ipairs(points) do keys[#keys + 1] = NumberSequenceKeypoint.new(p[1], p[2]) end
	end
	return NumberSequence.new(keys)
end

function SmoothVignette.build(parent, opts)
	opts = opts or {}
	local zIndex = opts.zIndex or 0
	local color = opts.color or Color3.fromRGB(10, 7, 5)
	local holder = Instance.new("Frame")
	holder.Name = opts.name or "SmoothVignette"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ZIndex = zIndex
	holder.Parent = parent
	local frames = {}
	local perfOn = perfRaw() == true -- Performance mode: nothing is built
	holder.Visible = not perfOn
	local cs = settings()
	if cs and type(cs.onChanged) == "function" then
		cs.onChanged(function(key, value)
			if key == "performanceMode" and holder.Parent then holder.Visible = value ~= true end
		end)
	end
	for _, edge in ipairs(EDGES) do
		local spec = opts[edge]
		if not perfOn and spec and (spec.strength or 0) > 0 then
			local f = Instance.new("Frame")
			f.Name = "Vignette_" .. edge
			f.BackgroundColor3 = color
			f.BackgroundTransparency = 1 - math.clamp(spec.strength, 0, 0.95)
			f.BorderSizePixel = 0
			f.Active = false
			f.ZIndex = zIndex
			local e = math.clamp(spec.extent or 0.2, 0.02, 1)
			local g = Instance.new("UIGradient")
			if edge == "top" then
				f.Size = UDim2.fromScale(1, e)
				g.Rotation = 90 -- time 0 at the top edge
				g.Transparency = sequence(false)
			elseif edge == "bottom" then
				f.AnchorPoint = Vector2.new(0, 1)
				f.Position = UDim2.fromScale(0, 1)
				f.Size = UDim2.fromScale(1, e)
				g.Rotation = 90 -- time 0 at the top of the frame, so reverse: dark at the bottom
				g.Transparency = sequence(true)
			elseif edge == "left" then
				f.Size = UDim2.fromScale(e, 1)
				g.Rotation = 0
				g.Transparency = sequence(false)
			else
				f.AnchorPoint = Vector2.new(1, 0)
				f.Position = UDim2.fromScale(1, 0)
				f.Size = UDim2.fromScale(e, 1)
				g.Rotation = 0
				g.Transparency = sequence(true)
			end
			g.Parent = f
			f.Parent = holder
			frames[edge] = f
		end
	end
	local self = { holder = holder, frames = frames }
	function self.setStrength(edge, strength, applyFn)
		local f = frames[edge]
		if not f then return end
		local props = { BackgroundTransparency = 1 - math.clamp(strength, 0, 0.95) }
		if type(applyFn) == "function" then applyFn(f, props) else f.BackgroundTransparency = props.BackgroundTransparency end
	end
	return self
end

return SmoothVignette
