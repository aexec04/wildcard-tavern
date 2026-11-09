--[[
	Client/ModalStage.lua
	Modal popups get their own space. ModalStage.mount(frame, kind) turns a popup's full-screen frame (a
	"...Backdrop", the pack panel, the Collection detail shade) into a themed stage:

	  * an opaque painted backdrop (Engine/ModalGate.STAGES: candlelit altar, card table, map desk, cork wall)
	    built from gradients and plain frames, so the live screen never shows through;
	  * an Active sink button, so no click reaches anything below;
	  * the central gate (Engine/ModalGate): the frame counts as an open modal while it is Visible. Every
	    hover handler, tooltip and tile highlight under it asks ModalStage.blocks(instance) first and returns
	    early; the modal's own buttons are inside the frame, so they keep working;
	  * a slow 6px cursor ease on the decor, off in calm mode (ClientSettings reduceShake).

	Settings and Volume are small floating popups and are never mounted, so they stay usable.
	setKind(frame, kind) re-themes a mounted frame (the Choice panel switches between blessing, draft and event).
	No Studio-only APIs beyond plain Instances; every call is safe to wrap in pcall.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ModalGate = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ModalGate"))
local ClientSettings = require(script.Parent.ClientSettings)

local ModalStage = {}

local gate = ModalGate.new()
local mounted = {} -- frame -> { stage = Frame, decor = Frame, kind = string, conn = RBXScriptConnection? }

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function inside(target, owner)
	return typeof(target) == "Instance" and owner ~= nil and target:IsDescendantOf(owner)
end

function ModalStage.isModalOpen()
	return gate:isModalOpen()
end

function ModalStage.count()
	return gate:count()
end

-- Hover handlers: `if ModalStage.blocks(button) then return end`. True when a modal is open and `inst` is not part of it.
function ModalStage.blocks(inst)
	return gate:blocks(inst, inside)
end

local function frameBit(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Active = false
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent
	return f
end

local function buildDecor(decor, stageDef, z)
	local accent = rgb(stageDef.accent)
	for _, child in ipairs(decor:GetChildren()) do child:Destroy() end
	if stageDef.decor == "rays" then
		for i = 1, 5 do -- soft light rays fanning from the top centre (plain thin frames, colour only)
			local ray = frameBit(decor, {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.3 + i * 0.1, -0.05),
				Size = UDim2.new(0, 38, 1.2, 0), Rotation = -24 + i * 12, BackgroundColor3 = accent,
				BackgroundTransparency = 0.93, ZIndex = z,
			})
			ray.Name = "Ray" .. i
		end
	elseif stageDef.decor == "chairs" then
		for i = 1, 3 do -- three chair silhouettes along the bottom edge
			local chair = frameBit(decor, {
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.2 + (i - 1) * 0.3, 1.02),
				Size = UDim2.new(0, 120, 0, 90), BackgroundColor3 = Color3.fromRGB(8, 20, 16), BackgroundTransparency = 0.2, ZIndex = z,
			})
			chair.Name = "Chair" .. i
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 18)
			c.Parent = chair
		end
	elseif stageDef.decor == "map" then
		for i = 1, 3 do -- rolled map strips across the desk
			local strip = frameBit(decor, {
				Position = UDim2.fromScale(0, 0.15 + i * 0.22), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = accent,
				BackgroundTransparency = 0.88, ZIndex = z,
			})
			strip.Name = "Strip" .. i
		end
	elseif stageDef.decor == "pins" then
		for i = 1, 6 do -- pins and string on a cork wall
			local pin = frameBit(decor, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.08 + (i - 1) * 0.17, i % 2 == 0 and 0.1 or 0.9),
				Size = UDim2.fromOffset(12, 12), BackgroundColor3 = accent, ZIndex = z,
			})
			pin.Name = "Pin" .. i
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = pin
		end
	end
end

local function applyTheme(entry, kind)
	local def = ModalGate.STAGES[ModalGate.stageFor(kind)]
	entry.kind = kind
	entry.stageDef = def
	-- Color stops only; never UIGradient.Transparency
	entry.gradient.Color = ColorSequence.new(rgb(def.top), rgb(def.bottom))
	entry.stage.BackgroundColor3 = rgb(def.top)
	buildDecor(entry.decor, def, entry.stage.ZIndex)
end

local function stopEase(entry)
	if entry.conn then
		entry.conn:Disconnect()
		entry.conn = nil
	end
	entry.decor.Position = UDim2.fromScale(0, 0)
end

local function startEase(entry)
	if entry.conn or ClientSettings.get("reduceShake") == true then return end
	local ease = (entry.stageDef and entry.stageDef.ease) or 6
	local offset = Vector2.zero
	entry.conn = RunService.RenderStepped:Connect(function(dt)
		local size = entry.stage.AbsoluteSize
		if size.X < 1 or size.Y < 1 then return end
		local m = UserInputService:GetMouseLocation() - entry.stage.AbsolutePosition
		local target = Vector2.new((m.X / size.X - 0.5) * -2 * ease, (m.Y / size.Y - 0.5) * -2 * ease)
		offset = offset:Lerp(target, math.min(1, dt * 3))
		entry.decor.Position = UDim2.fromOffset(offset.X, offset.Y)
	end)
end

local function sync(frame, entry)
	if frame.Visible then
		gate:open(frame)
		startEase(entry)
	else
		gate:close(frame)
		stopEase(entry)
	end
end

function ModalStage.setKind(frame, kind)
	local entry = mounted[frame]
	if entry and entry.kind ~= kind then applyTheme(entry, kind) end
end

-- Idempotent. `kind` is a ModalGate stage or a Choice kind (see ModalGate.stageFor).
function ModalStage.mount(frame, kind)
	local entry = mounted[frame]
	if entry then
		ModalStage.setKind(frame, kind)
		return entry.stage
	end

	local stage = Instance.new("TextButton") -- Active sink: swallows every click that reaches the stage
	stage.Name = "ModalStage"
	stage.Text = ""
	stage.AutoButtonColor = false
	stage.Active = true
	stage.BorderSizePixel = 0
	stage.BackgroundTransparency = 0 -- opaque: the live screen never shows through
	stage.Size = UDim2.fromScale(1, 1)
	stage.ZIndex = frame.ZIndex
	stage.LayoutOrder = -1000
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = stage
	local clip = Instance.new("Frame") -- decor layer: the cursor ease moves this, the stage itself stays put
	clip.Name = "Decor"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.Active = false
	clip.Size = UDim2.fromScale(1, 1)
	clip.ZIndex = frame.ZIndex
	clip.Parent = stage
	stage.ClipsDescendants = true
	stage.Parent = frame

	entry = { stage = stage, decor = clip, gradient = gradient }
	mounted[frame] = entry
	applyTheme(entry, kind)

	frame:GetPropertyChangedSignal("Visible"):Connect(function() sync(frame, entry) end)
	frame.AncestryChanged:Connect(function()
		if not frame:IsDescendantOf(game) then
			gate:close(frame)
			stopEase(entry)
			mounted[frame] = nil
		end
	end)
	sync(frame, entry)
	return stage
end

return ModalStage
