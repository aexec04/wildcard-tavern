--[[
	Client/PlayMotion.lua
	Calm 2D motion for the Play screen (numbers in Engine/PlayMotion, unit tested):
	  * parallax: the painted table and the rail pieces drift 9 to 14 px opposite the cursor, eased and capped, still under
	    a modal and in calm mode (Reduce Motion / Reduce Shake);
	  * light: a soft lamp light pool over the felt at the hand row, warm or cool per Card Set, no flicker;
	  * dealCard(button, order, count): a new hand card travels from the deck pile to its slot in a short arc;
  * depth: hand slots lie on a gentle arc (1 to 3 degrees, far-edge cards 4 percent smaller) and the table and rail
    layers lean 8 to 16 px and up to 2 percent toward the hand while a card is selected (still in calm mode and under a plate).
	Layout code sets the layers' Positions; this module reads whatever it wrote last as the new base each frame, so a
	resize never fights it. Nothing here touches input, selection or game state.

	install{ root, handFrame, deckWidget } -> { dealCard }
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PM = require(Engine:WaitForChild("PlayMotion"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true end

function M.install(deps)
	local root, handFrame = deps.root, deps.handFrame
	local ModalStage = require(script.Parent.ModalStage)
	local HudTheme = require(script.Parent.HudTheme)

	-- light pool ---------------------------------------------------------------------------------------------------
	local light = PM.lightFor(HudTheme.setId())
	local glow
	local function buildGlow()
		if glow then glow.root:Destroy() end
		light = PM.lightFor(HudTheme.setId())
		glow = require(script.Parent.SoftGlow).build(root, {
			name = "PlayLightPool", color = Color3.fromRGB(light.color[1], light.color[2], light.color[3]),
			position = UDim2.fromOffset(0, 0), size = UDim2.fromOffset(10, 10),
			peak = 1 - light.poolTransparency, zIndex = 1,
		})
	end
	pcall(buildGlow)
	pcall(function() HudTheme.onSkin(function() pcall(buildGlow) end) end)

	local sx, sy, lean = 0, 0, 0
	local function placeGlow()
		if not glow then return end
		local show = handFrame.Visible and root.AbsoluteSize.X > 0
		glow.root.Visible = show
		if not show then return end
		local ox, oy = root.AbsolutePosition.X, root.AbsolutePosition.Y
		local x, y, w, h = PM.poolRect(root.AbsoluteSize.X, root.AbsoluteSize.Y, handFrame.AbsolutePosition.Y - oy, handFrame.AbsoluteSize.Y)
		glow.root.Position = UDim2.fromOffset(x + w / 2 - sx * 12, y + h / 2 - sy * 6)
		glow.root.Size = UDim2.fromOffset(w, h)
	end

	-- parallax -----------------------------------------------------------------------------------------------------
	local layers = {
		{ name = "PlayTableFront", px = PM.LAYER_PX.table, leanPx = PM.LEAN_PX.table },
		{ name = "PlayRailBack", px = PM.LAYER_PX.rail, leanPx = PM.LEAN_PX.rail },
		{ name = "PlayRailFront", px = PM.LAYER_PX.rail, leanPx = PM.LEAN_PX.rail },
	}
	local fanChecked = false
	local function applyDepth()
		local slots = {}
		for _, c in ipairs(handFrame:GetChildren()) do
			if c:IsA("Frame") and c:GetAttribute("HandIndex") then slots[#slots + 1] = c end
		end
		table.sort(slots, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		local selected = 0
		for i, slot in ipairs(slots) do
			-- Roblox does not draw Rotation on a layout-controlled slot (AbsoluteRotation stays 0), so the tilt goes on the
			-- card button inside the slot and the slot keeps the target in an attribute
			local tilt = PM.cardTilt(i, #slots)
			slot.Rotation = 0
			slot:SetAttribute("FanRot", tilt)
			local tbtn = slot:FindFirstChildOfClass("TextButton")
			if tbtn and not slot:GetAttribute("Dealing") and tbtn.Rotation ~= tilt then tbtn.Rotation = tilt end
			-- fan offset (tuck and dip) lives in slot attributes; the hub's lift tween adds it to its own target
			local fx, fy = PM.cardOffset(i, #slots)
			fx, fy = math.floor(fx + 0.5), math.floor(fy + 0.5)
			local ox, oy = slot:GetAttribute("FanX") or 0, slot:GetAttribute("FanY") or 0
			if ox ~= fx or oy ~= fy then
				slot:SetAttribute("FanX", fx)
				slot:SetAttribute("FanY", fy)
				local btn = slot:FindFirstChildOfClass("TextButton")
				if btn and not slot:GetAttribute("Dealing") then
					btn.Position = btn.Position + UDim2.fromOffset(fx - ox, fy - oy)
				end
			end
			local us = slot:FindFirstChild("DepthScale")
			if not us then us = Instance.new("UIScale") us.Name = "DepthScale" us.Parent = slot end
			us.Scale = PM.cardScale(i, #slots)
			if slot:GetAttribute("Lifted") then selected += 1 end
		end
		return selected
	end
	RunService.RenderStepped:Connect(function(dt)
		if not handFrame.Visible then return end
		pcall(placeGlow)
		local isCalm, modal = calm(), ModalStage.isModalOpen()
		local nx, ny = 0, 0
		if not isCalm and not modal and UserInputService.MouseEnabled then
			local m, size = UserInputService:GetMouseLocation(), root.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				nx, ny = PM.clamp(m.X / size.X * 2 - 1, -1, 1), PM.clamp(m.Y / size.Y * 2 - 1, -1, 1)
			end
		end
		local a = PM.follow(dt, 0.1)
		sx += (nx - sx) * a
		sy += (ny - sy) * a
		local okD, selectedCount = pcall(applyDepth)
		if not fanChecked and okD then
			fanChecked = true
			task.defer(function()
				local n, rotated = 0, 0
				for _, c in ipairs(handFrame:GetChildren()) do
					local b = c:IsA("Frame") and c:GetAttribute("HandIndex") and c:FindFirstChildOfClass("TextButton")
					if b then n += 1 if math.abs(b.AbsoluteRotation) > 0.1 then rotated += 1 end end
				end
				print(string.format("[HandFan] cards=%d rotated=%d", n, rotated))
				if n > 1 and rotated == 0 then warn("[HandFan] no hand card has a nonzero AbsoluteRotation; the fan is not drawing") end
			end)
		end
		lean += (PM.leanTarget(okD and selectedCount or 0, false, modal, isCalm) - lean) * PM.follow(dt, 0.14) -- settles in about 0.3 s
		for _, layer in ipairs(layers) do
			local inst = layer.inst
			if not inst or inst.Parent ~= root then inst = root:FindFirstChild(layer.name); layer.inst = inst end
			if inst then
				if layer.applied ~= inst.Position then layer.base = inst.Position end -- layout moved it: new base
				local dx, dy = PM.layerOffset(sx, sy, layer, lean, isCalm)
				layer.applied = layer.base + UDim2.fromOffset(dx, dy)
				inst.Position = layer.applied
			end
		end
	end)

	-- deal arc -----------------------------------------------------------------------------------------------------
	local api = {}
	-- button: the new card (already at its slot, Position centred in its slot); order/count: 1-based among the dealt cards
	function api.dealCard(button, order, count)
		if calm() or ClientSettings.get("animSpeed") == "fast" then return false end
		local deck = deps.deckWidget
		if not deck or not deck.Parent or button.Parent == nil then return false end
		local slot = button.Parent
		local fromX = deck.AbsolutePosition.X + deck.AbsoluteSize.X / 2 - (slot.AbsolutePosition.X + slot.AbsoluteSize.X / 2)
		local fromY = deck.AbsolutePosition.Y + deck.AbsoluteSize.Y / 2 - (slot.AbsolutePosition.Y + slot.AbsoluteSize.Y / 2)
		local delay, dur = PM.dealTiming(order, count)
		local landX, landY = slot:GetAttribute("FanX") or 0, slot:GetAttribute("FanY") or 0
		slot:SetAttribute("Dealing", true)
		button.Position = UDim2.new(0.5, fromX, 0.5, fromY)
		button.Rotation = 14
		task.delay(delay, function()
			if not button.Parent then return end
			local t0 = os.clock()
			local conn
			conn = RunService.RenderStepped:Connect(function()
				if not button.Parent then conn:Disconnect() return end
				local t = (os.clock() - t0) / dur
				if t >= 1 then
					conn:Disconnect()
					button.Position = UDim2.new(0.5, landX, 0.5, landY)
					button.Rotation = slot:GetAttribute("FanRot") or 0
					slot:SetAttribute("Dealing", nil)
					return
				end
				local e = 1 - (1 - t) ^ 3 -- ease out
				local x, y = PM.arc(fromX, fromY, landX, landY, e, 40)
				button.Position = UDim2.new(0.5, x, 0.5, y)
				local rest = slot:GetAttribute("FanRot") or 0
				button.Rotation = rest + (14 - rest) * (1 - e)
			end)
		end)
		return true
	end
	M.current = api
	return api
end

-- used by the hand builder: false means the caller keeps its own fly-in
function M.deal(button, order, count)
	return M.current ~= nil and M.current.dealCard(button, order, count)
end

return M
