--[[
	Client/AmbientLife.lua
	Gentle ambient motion on the table backdrops (butterflies, clouds, snow, fireflies ...). The data and the motion maths
	are Engine/AmbientLayout (pure, tested); this module only draws them.

	  AmbientLife.attach(fx, host) -> controller
	    fx:   the "BackdropFX" frame BackdropStyles builds inside the host (clipped, same ZIndex as the host, so the
	          objects sit below the card row, hand tray, sidebar and popups and never over text)
	    host: the backdrop GuiObject (used for the visibility check and the slow whole-picture breath on ImageLabels)
	  controller.setSet(setId)   build the set's objects (zero objects in calm mode)
	  controller.destroy()

	One Heartbeat drives every scene, capped at 30 Hz. Frames are pooled (built once per set, reused every tick) and
	destroyed with the table. Everything stops while the table is hidden or a "...Backdrop" popup covers it, and calm
	mode / Reduce shake removes the objects entirely. Art comes from ContentArt "ambient"; a sprite with no Image id yet
	is drawn from simple shapes (soft circles, ellipses, rounded rectangles).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local AmbientLayout = require(Engine:WaitForChild("AmbientLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local PlayerProfile = require(Engine:WaitForChild("PlayerProfile"))
local ClientSettings = require(script.Parent.ClientSettings)

local CHECK_INTERVAL = 0.4

local M = {}

local scenes = {} -- [controller] = true
local connection = nil
local sinceStep = 0
local sinceCheck = 0
local clock = 0 -- scene time in seconds, advances only while stepping (so pauses do not jump)

local function calm()
	return ClientSettings.get("reduceShake") == true
end

local function paceFactor()
	local ok, v = pcall(function()
		return PlayerProfile.animationPaceDivisor(ClientSettings.get("animSpeed"), false)
	end)
	return (ok and type(v) == "number" and v > 0) and v or 1
end

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function shown(host)
	local obj = host
	while obj do
		if obj:IsA("GuiObject") then
			if not obj.Visible then return false end
		elseif obj:IsA("ScreenGui") then
			return obj.Enabled
		elseif obj:IsA("LayerCollector") then
			return true
		end
		obj = obj.Parent
	end
	return false
end

-- A visible "...Backdrop" panel (popup) on the same ScreenGui covers the table: pause underneath it.
local function covered(host)
	local gui = host:FindFirstAncestorWhichIsA("ScreenGui")
	if not gui then return false end
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and child ~= host and string.sub(child.Name, -8) == "Backdrop"
			and child.Name ~= "DeckTrackerBackdrop" and not host:IsDescendantOf(child) then
			return true
		end
	end
	return false
end

local function spriteImage(kind, which)
	local s = AmbientLayout.SPRITES[kind]
	if not s then return nil end
	local id = s.ids[which] or s.ids[1]
	if not id then return nil end
	local art = ContentArt.ambient
	local v = art and art[id]
	if v and v ~= "" and v ~= "rbxassetid://0" then return v, s.crop end
	return nil
end

-- ===== objects =====

local function shape(kind, spec)
	-- code-drawn stand-ins; returns the visual frame and its aspect (width / height)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = c3(spec.color or { 255, 255, 255 })
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local aspect = 1
	if kind == "cloud" then
		aspect = 3
	elseif kind == "mist" then
		aspect = 5
	elseif kind == "sand" then
		aspect = 8
	elseif kind == "shimmer" then
		aspect = 40
		corner.CornerRadius = UDim.new(0, 0)
	elseif kind == "bird" then
		aspect = 2.2
	elseif kind == "butterfly" then
		aspect = 1.1
		corner.CornerRadius = UDim.new(0.35, 0)
	elseif kind == "leaf" or kind == "petal" or kind == "ribbon" then
		aspect = 1.8
		corner.CornerRadius = UDim.new(0.45, 0)
	elseif kind == "lantern" then
		aspect = 0.8
		corner.CornerRadius = UDim.new(0.3, 0)
	elseif kind == "glow" then
		aspect = 1.6
	end
	return f, aspect
end

local function buildObject(scene, item)
	local spec = item.spec
	local holder = Instance.new("Frame")
	holder.Name = "Ambient_" .. item.kind
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ZIndex = scene.fx.ZIndex
	pcall(function() holder.Interactable = false end)
	local visual, aspect, image
	local img, crop = spriteImage(item.kind, 1)
	if img then
		visual = Instance.new("ImageLabel")
		visual.BackgroundTransparency = 1
		visual.Image = img
		visual.ScaleType = crop and Enum.ScaleType.Crop or Enum.ScaleType.Fit
		if crop then
			visual.ImageRectOffset = Vector2.new(crop[1], crop[2])
			visual.ImageRectSize = Vector2.new(crop[3], crop[4])
			aspect = crop[3] / crop[4]
		else
			aspect = 1
		end
		if item.kind == "leaf" or item.kind == "petal" or item.kind == "snow" or item.kind == "ember" or item.kind == "mote" then
			visual.ImageColor3 = c3(spec.color or { 255, 255, 255 })
		end
		image = true
	else
		visual, aspect = shape(item.kind, spec)
	end
	visual.Size = UDim2.fromScale(1, 1)
	visual.Active = false
	visual.ZIndex = holder.ZIndex
	visual.Parent = holder
	local w = (spec.size or 0.02) * (item.kind == "glow" and 1 or 1)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = aspect
	ratio.DominantAxis = Enum.DominantAxis.Width
	ratio.Parent = holder
	holder.Size = UDim2.fromScale(w, 0)
	holder.Parent = scene.fx
	return { item = item, holder = holder, visual = visual, image = image, lastFrame = 1, aspect = aspect }
end

local function setFrame(obj, st)
	if obj.lastFrame == st.frame then return end
	obj.lastFrame = st.frame
	if obj.image then
		local img = spriteImage(obj.item.kind, st.frame)
		if img then obj.visual.Image = img end
	elseif obj.item.kind == "butterfly" then
		obj.holder.Size = UDim2.fromScale((obj.item.spec.size or 0.04) * (st.frame == 1 and 1 or 0.55), 0)
	end
end

local function clearObjects(scene)
	for _, obj in ipairs(scene.objects) do
		obj.holder:Destroy()
	end
	scene.objects = {}
end

local function restoreHost(scene)
	local saved = scene.saved
	if saved and scene.host and scene.host.Parent then
		pcall(function()
			scene.host.AnchorPoint = saved.anchor
			scene.host.Size = saved.size
			scene.host.Position = saved.position
		end)
	end
	scene.saved = nil
end

local function build(scene)
	clearObjects(scene)
	if calm() or not scene.setId then return end
	for _, item in ipairs(AmbientLayout.list(scene.setId, false)) do
		local ok, obj = pcall(buildObject, scene, item)
		if ok then table.insert(scene.objects, obj) end
	end
end

local function breathe(scene, t)
	local host = scene.host
	if not host:IsA("ImageLabel") then return end
	if not scene.saved then
		local s = host.Size
		if s.X.Scale ~= 1 or s.Y.Scale ~= 1 or s.X.Offset ~= 0 or s.Y.Offset ~= 0 then return end -- laid out by something else
		scene.saved = { anchor = host.AnchorPoint, size = s, position = host.Position }
		host.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	local b = AmbientLayout.breath(t)
	host.Size = UDim2.fromScale(b.scale, b.scale)
	host.Position = UDim2.fromScale(0.5 + b.dx, 0.5 + b.dy)
end

-- ===== the single loop =====

local function step(dt)
	sinceStep = sinceStep + dt
	sinceCheck = sinceCheck + dt
	local recheck = sinceCheck >= CHECK_INTERVAL
	if recheck then sinceCheck = 0 end
	local stepNow = sinceStep >= AmbientLayout.TICK
	local stepDt = sinceStep
	if stepNow then sinceStep = 0 end
	if recheck then
		local isCalm = calm()
		for scene in pairs(scenes) do
			if not scene.fx.Parent then
				scene.dead = true
			else
				local wasCalm = scene.calm
				scene.calm = isCalm
				if wasCalm ~= isCalm then
					if isCalm then
						clearObjects(scene)
						restoreHost(scene)
					else
						build(scene)
					end
				end
				scene.running = (not isCalm) and shown(scene.host) and not covered(scene.host)
				for _, obj in ipairs(scene.objects) do
					obj.holder.Visible = scene.running
				end
				if not scene.running then restoreHost(scene) end
			end
		end
		for scene in pairs(scenes) do
			if scene.dead then
				scenes[scene] = nil
			end
		end
		if next(scenes) == nil and connection then
			connection:Disconnect()
			connection = nil
			return
		end
	end
	if not stepNow then return end
	clock = clock + stepDt * paceFactor()
	local wind = AmbientLayout.wind(clock, 0)
	for scene in pairs(scenes) do
		if scene.running then
			local ok = pcall(function()
				for _, obj in ipairs(scene.objects) do
					local st = AmbientLayout.state(obj.item, clock, wind)
					setFrame(obj, st)
					obj.holder.Position = UDim2.fromScale(st.x, st.y)
					obj.holder.Rotation = st.rot
					local a = 1 - math.clamp(st.alpha, 0, 1)
					if obj.image then
						obj.visual.ImageTransparency = a
					else
						obj.visual.BackgroundTransparency = math.clamp(0.35 + a * 0.65, 0, 1)
					end
				end
				breathe(scene, clock)
			end)
			if not ok then
				scene.running = false -- a failing scene stops instead of erroring every frame
			end
		end
	end
end

function M.attach(fx, host)
	local scene = { fx = fx, host = host, objects = {}, running = false, calm = calm(), setId = nil }
	local controller = {}

	function controller.setSet(setId)
		scene.setId = setId
		scene.calm = calm()
		build(scene)
		scenes[scene] = true
		if not connection then
			connection = RunService.Heartbeat:Connect(step)
		end
	end

	function controller.destroy()
		scenes[scene] = nil
		clearObjects(scene)
		restoreHost(scene)
	end

	controller.scene = scene -- exposed for tests
	return controller
end

return M
