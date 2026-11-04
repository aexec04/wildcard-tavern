--[[
	Client/BackdropStyles.lua
	Draws a Cosmetic Set's `backdropStyle` (Engine/CosmeticSets.lua) over a
	backdrop with UI elements only: a color tint on the base image, a flat
	tinted overlay, a stepped vignette (stacked edge strips; gradients here only
	use Color stops, never Transparency) and cheap layers (snow, sparks, dust,
	bunting). No new image files.

	attach(host, opts) -> controller
	  host: the GuiObject whose backdrop is styled. The effects live in a
	        child frame "BackdropFX" at the host's own ZIndex, so they sit
	        below anything with a higher ZIndex (the gameplay UI).
	  opts.defaultTint: Color3 put back on an ImageLabel host when no style.
	controller.setStyle(style or nil)

	Safety: the effects never take input (Active = false, Interactable =
	false). Every build step is in a pcall, so a failing effect just leaves
	that effect out. Particles are capped, reuse their frames, and only move
	while the host is actually visible. "Reduce screen shake" turns the
	moving layers off (the static tint, vignette and bunting stay); Animation
	Speed scales how fast particles drift.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
local PlayerProfile = require(Engine:WaitForChild("PlayerProfile"))
local ClientSettings = require(script.Parent.ClientSettings)

local VIGNETTE_STEPS = 6
local STEP_INTERVAL = 1 / 30
local VISIBLE_CHECK_INTERVAL = 0.25

local M = {}

local active = {} -- controllers that have moving particles
local connection = nil
local sinceStep = 0
local sinceCheck = 0

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function isShown(host)
	local obj = host
	while obj do
		if obj:IsA("GuiObject") then
			if not obj.Visible then
				return false
			end
		elseif obj:IsA("ScreenGui") then
			return obj.Enabled
		elseif obj:IsA("LayerCollector") then
			return true
		end
		obj = obj.Parent
	end
	return false
end

local function calm()
	return ClientSettings.get("reduceShake") == true
end

local function speedFactor()
	return PlayerProfile.animationPaceDivisor(ClientSettings.get("animSpeed"), false)
end

-- ===== Moving layers =====
-- Each layer = { kind, speed, items = { { frame, x, y, vx, vy, phase } } }.

local function newDot(parent, zindex, color, size, transparency)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size, size)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = zindex
	f.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	return f
end

local function buildParticles(fx, layer)
	local items = {}
	local count = math.min(layer.count, CosmeticSets.BackdropLimits.maxParticles)
	local rng = Random.new(count * 7919 + #layer.kind)
	for i = 1, count do
		local item = { x = rng:NextNumber(), y = rng:NextNumber(), phase = rng:NextNumber() * 6.28, vx = 0, vy = 0 }
		local frame
		if layer.kind == "snow" then
			item.vy = 0.05 + rng:NextNumber() * 0.05
			frame = newDot(fx, fx.ZIndex, Color3.fromRGB(235, 245, 255), rng:NextInteger(3, 6), 0.2 + rng:NextNumber() * 0.3)
		elseif layer.kind == "sparks" then
			item.vy = -(0.04 + rng:NextNumber() * 0.06)
			frame = newDot(fx, fx.ZIndex, Color3.fromRGB(255, 190 + rng:NextInteger(0, 50), 90), rng:NextInteger(2, 4), 0.3)
		else -- dust
			item.vx = (rng:NextNumber() - 0.5) * 0.02
			item.vy = -0.004 - rng:NextNumber() * 0.006
			frame = newDot(fx, fx.ZIndex, Color3.fromRGB(215, 185, 140), rng:NextInteger(2, 3), 0.6 + rng:NextNumber() * 0.2)
		end
		item.frame = frame
		frame.Position = UDim2.fromScale(item.x, item.y)
		items[i] = item
	end
	return { kind = layer.kind, speed = layer.speed or 1, items = items }
end

local function stepLayer(layer, dt, t)
	local k = dt * layer.speed
	for _, item in ipairs(layer.items) do
		item.y = item.y + item.vy * k
		item.x = item.x + item.vx * k
		local sway = 0
		if layer.kind == "snow" then
			sway = math.sin(t * 0.8 + item.phase) * 0.012
		elseif layer.kind == "sparks" then
			sway = math.sin(t * 1.3 + item.phase) * 0.015
			item.frame.BackgroundTransparency = 0.35 + 0.35 * math.sin(t * 3 + item.phase)
		end
		if item.y > 1.05 then
			item.y = -0.05
		elseif item.y < -0.05 then
			item.y = 1.05
		end
		if item.x > 1.05 then
			item.x = -0.05
		elseif item.x < -0.05 then
			item.x = 1.05
		end
		item.frame.Position = UDim2.fromScale(item.x + sway, item.y)
	end
end

local function loop(dt)
	sinceStep = sinceStep + dt
	sinceCheck = sinceCheck + dt
	local recheck = sinceCheck >= VISIBLE_CHECK_INTERVAL
	if recheck then
		sinceCheck = 0
	end
	local stepNow = sinceStep >= STEP_INTERVAL
	local stepDt = sinceStep
	if stepNow then
		sinceStep = 0
	end
	local t = os.clock()
	local factor = speedFactor()
	for controller in pairs(active) do
		if recheck then
			local run = isShown(controller.host) and not calm()
			controller.running = run
			for _, layer in ipairs(controller.layers) do
				for _, item in ipairs(layer.items) do
					item.frame.Visible = run
				end
			end
		end
		if stepNow and controller.running then
			for _, layer in ipairs(controller.layers) do
				local ok = pcall(stepLayer, layer, stepDt * factor, t)
				if not ok then
					controller.running = false -- stop a failing layer's updates
				end
			end
		end
	end
end

local function register(controller)
	active[controller] = true
	if not connection then
		connection = RunService.Heartbeat:Connect(loop)
	end
end

local function unregister(controller)
	active[controller] = nil
	if connection and next(active) == nil then
		connection:Disconnect()
		connection = nil
	end
end

-- ===== Static effects =====

local function solid(parent, zindex, color, transparency)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = zindex
	f.Parent = parent
	return f
end

-- Stacked edge strips: where they overlap (toward the edge and in the
-- corners) the color gets stronger. Total opacity at an edge = strength.
local function buildVignette(fx, vignette)
	local color = rgb(vignette.color)
	local strength = math.clamp(vignette.strength, 0, 0.95)
	local perStep = 1 - (1 - strength) ^ (1 / VIGNETTE_STEPS)
	local transparency = 1 - perStep
	local light = color:Lerp(Color3.new(1, 1, 1), 0.3)
	for step = 1, VIGNETTE_STEPS do
		local depth = step / VIGNETTE_STEPS
		for edge = 1, 4 do
			local strip = solid(fx, fx.ZIndex, color, transparency)
			if edge == 1 then -- top
				strip.Size = UDim2.new(1, 0, 0.22 * depth, 0)
			elseif edge == 2 then -- bottom
				strip.AnchorPoint = Vector2.new(0, 1)
				strip.Position = UDim2.fromScale(0, 1)
				strip.Size = UDim2.new(1, 0, 0.22 * depth, 0)
			elseif edge == 3 then -- left
				strip.Size = UDim2.new(0.14 * depth, 0, 1, 0)
			else -- right
				strip.AnchorPoint = Vector2.new(1, 0)
				strip.Position = UDim2.fromScale(1, 0)
				strip.Size = UDim2.new(0.14 * depth, 0, 1, 0)
			end
			-- Gradient Color stops only (Transparency is never touched).
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new(color, light)
			gradient.Rotation = edge <= 2 and 0 or 90
			gradient.Parent = strip
		end
	end
end

local function buildBunting(fx, layer)
	local rope = solid(fx, fx.ZIndex, Color3.fromRGB(70, 45, 25), 0.1)
	rope.Size = UDim2.new(1, 0, 0, 3)
	rope.Position = UDim2.fromOffset(0, 2)
	local colors = layer.colors or { { 230, 80, 90 }, { 250, 200, 70 } }
	local count = math.min(layer.count, CosmeticSets.BackdropLimits.maxParticles)
	for i = 1, count do
		-- A rotated square hanging half above the top edge reads as a flag.
		local flag = solid(fx, fx.ZIndex, rgb(colors[(i - 1) % #colors + 1]), 0.05)
		flag.AnchorPoint = Vector2.new(0.5, 0.5)
		flag.Size = UDim2.fromOffset(20, 20)
		flag.Position = UDim2.new((i - 0.5) / count, 0, 0, 2)
		flag.Rotation = 45
	end
end

-- ===== Controller =====

function M.attach(host, opts)
	opts = opts or {}
	local controller = { host = host, layers = {}, running = false }
	local fx = nil

	local function clear()
		unregister(controller)
		controller.layers = {}
		controller.running = false
		if fx then
			fx:Destroy()
			fx = nil
		end
	end

	local function newFx()
		fx = Instance.new("Frame")
		fx.Name = "BackdropFX"
		fx.Size = UDim2.fromScale(1, 1)
		fx.BackgroundTransparency = 1
		fx.BorderSizePixel = 0
		fx.ClipsDescendants = true
		fx.Active = false
		fx.ZIndex = host.ZIndex
		pcall(function()
			fx.Interactable = false
		end)
		fx.Parent = host
	end

	function controller.setStyle(style)
		clear()
		if host:IsA("ImageLabel") then
			pcall(function()
				host.ImageColor3 = style and style.tint and rgb(style.tint) or opts.defaultTint or Color3.new(1, 1, 1)
			end)
		end
		if not style then
			return
		end
		local valid = CosmeticSets.validateStyle(style)
		if not valid then
			return
		end
		newFx()
		if style.overlay then
			pcall(function()
				local o = solid(fx, fx.ZIndex, rgb(style.overlay.color), style.overlay.transparency)
				o.Size = UDim2.fromScale(1, 1)
			end)
		end
		if style.vignette then
			pcall(buildVignette, fx, style.vignette)
		end
		for _, layer in ipairs(style.layers or {}) do
			if layer.kind == "bunting" then
				pcall(buildBunting, fx, layer)
			else
				local ok, built = pcall(buildParticles, fx, layer)
				if ok then
					table.insert(controller.layers, built)
				end
			end
		end
		if #controller.layers > 0 then
			register(controller)
		end
	end

	return controller
end

return M
