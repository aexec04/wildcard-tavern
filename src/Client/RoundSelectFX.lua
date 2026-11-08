--[[
	Client/RoundSelectFX.lua
	Hover life and idle motion for the Round Select cards and their Select / Skip buttons.
	Cosmetic only: it never changes what a card or button does. RoundSelect.lua builds the
	cards, then hands each one to addCard(); the module adds its own UIScales, clip frames and
	overlays, so the card layout is untouched.

	Card hover: grow to ~1.04 (UIScale), brighten the art, slow Ken Burns zoom, stroke swell,
	one diagonal light sweep per enter. "Up next" / Cleared cards get a smaller version (no zoom,
	no sweep, no sound) so it is clear they cannot be chosen.
	Idle (only while the overlay is visible and Reduce shake is off): the current card breathes
	and its chip pulses, the Boss card's stroke pulses red-orange and embers drift up its art,
	Tag chips sway a couple of degrees.
	Buttons: hover grows 1.05 and tints toward gold, press squashes to 0.96 and springs back,
	Select gets a shine sweep. Nothing animates while an action is pending.
	Sound: a quiet click on hover for enabled cards/buttons, rate limited to one per 0.1s.

	NOTE (lift): cards live in a UIListLayout so their Position cannot be tweened; the 8px "lift"
	is approximated by the grow (UIScale) and the art zoom.
]]

local TweenService = game:GetService("TweenService")
local ClientSettings = require(script.Parent.ClientSettings)

local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local EMBER = Color3.fromRGB(255, 150, 70)
local BOSS_GLOW = Color3.fromRGB(230, 90, 40)

local HOVER_SCALE_ACTIVE = 1.04
local HOVER_SCALE_LOCKED = 1.02
local ZOOM_MAX = 1.08
local ZOOM_SECONDS = 6
local EMBER_COUNT = 5

local FX = {}

local function tween(inst, props, time, style, dir, repeatCount, reverses)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, repeatCount or 0, reverses or false)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function reducedMotion()
	return ClientSettings.get("reduceShake") == true
end

local function makeStrip(parent, zIndex, transparency)
	-- Narrow diagonal cream strip. UIGradient touches Color only, never Transparency.
	local strip = Instance.new("Frame")
	strip.Name = "SweepStrip"
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.Size = UDim2.new(0.16, 0, 1.8, 0)
	strip.Position = UDim2.new(-0.3, 0, 0.5, 0)
	strip.Rotation = 20
	strip.BackgroundColor3 = CREAM
	strip.BackgroundTransparency = transparency
	strip.BorderSizePixel = 0
	strip.Active = false
	strip.ZIndex = zIndex
	strip.Parent = parent
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 210, 160)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 250, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 210, 160)),
	})
	grad.Rotation = 0
	grad.Parent = strip
	return strip
end

-- deps: roundSelectFrame, playClickSfx, isActionPending (function -> bool), roundCorner
function FX.new(deps)
	local frame = deps.roundSelectFrame
	local playClickSfx = deps.playClickSfx
	local isActionPending = deps.isActionPending or function() return false end
	local roundCorner = deps.roundCorner

	local self = {}
	local cards = {}
	local connections = {}
	local lastSound = 0
	local destroyed = false

	local function connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(connections, c)
		return c
	end

	local function hoverSound()
		local now = os.clock()
		if now - lastSound < 0.1 then return end
		lastSound = now
		if playClickSfx then pcall(playClickSfx, 0.12) end
	end

	-- ===== loops (idle motion) =====
	local function stopLoops(card)
		card.loopToken = card.loopToken + 1
		for _, t in ipairs(card.loopTweens) do
			t:Cancel()
		end
		card.loopTweens = {}
		-- Reset what the loops animate.
		card.breatheK.Value = 1
		card.tag.Rotation = 0
		if card.chipBase then card.chip.BackgroundTransparency = card.chipBase end
		if card.isBoss and card.stroke then
			card.stroke.Thickness = 4
			card.stroke.Color = card.strokeBase
		end
		for _, e in ipairs(card.embers) do
			e.Visible = false
		end
	end

	local function startEmber(card, ember, token, index)
		task.spawn(function()
			task.wait(index * 0.55)
			while not destroyed and card.loopToken == token do
				local x = 0.12 + math.random() * 0.76
				local rise = 0.45 + math.random() * 0.25
				local dur = 2.4 + math.random() * 1.6
				ember.Position = UDim2.new(x, 0, 0.98, 0)
				ember.BackgroundTransparency = 0.2
				ember.Visible = true
				local t1 = tween(ember, {
					Position = UDim2.new(x + (math.random() - 0.5) * 0.12, 0, 0.98 - rise, 0),
					BackgroundTransparency = 1,
				}, dur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				table.insert(card.loopTweens, t1)
				task.wait(dur + 0.2 + math.random() * 0.8)
			end
		end)
	end

	local function refreshLoops(card)
		local want = (not destroyed) and frame.Visible and not reducedMotion()
		local key = (want and "on" or "off") .. ":" .. tostring(card.kind)
		if card.loopKey == key then return end
		card.loopKey = key
		stopLoops(card)
		if not want then return end
		local token = card.loopToken
		local function loop(inst, props, time)
			local t = tween(inst, props, time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			table.insert(card.loopTweens, t)
		end
		if card.kind == "current" then
			loop(card.breatheK, { Value = 1.015 }, 2.4)
			loop(card.chip, { BackgroundTransparency = 0.45 }, 1.2)
		end
		if card.isBoss and card.stroke then
			loop(card.stroke, { Thickness = 8, Color = BOSS_GLOW }, 1.25)
			for i, ember in ipairs(card.embers) do
				startEmber(card, ember, token, i)
			end
		end
		if card.tag.Visible or not card.isBoss then
			card.tag.Rotation = -2
			loop(card.tag, { Rotation = 2 }, 3)
		end
	end

	-- ===== card hover =====
	local function applyScale(card)
		card.scale.Scale = card.fit * card.hoverK.Value * card.breatheK.Value
	end

	local function sweep(strip, from, to, time)
		strip.Position = UDim2.new(from, 0, 0.5, 0)
		return tween(strip, { Position = UDim2.new(to, 0, 0.5, 0) }, time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	end

	local function setCardHover(card, on)
		if destroyed or card.hovered == on then return end
		card.hovered = on
		local locked = card.kind ~= "current"
		if on then
			tween(card.hoverK, { Value = locked and HOVER_SCALE_LOCKED or HOVER_SCALE_ACTIVE }, 0.18)
			tween(card.glow, { BackgroundTransparency = locked and 0.95 or 0.9 }, 0.18)
			if card.stroke and not card.isBoss then
				tween(card.stroke, { Thickness = locked and 4 or 5 }, 0.18)
			end
			if not locked then
				hoverSound()
				if not reducedMotion() then
					card.zoomTween = tween(card.zoomK, { Value = ZOOM_MAX }, ZOOM_SECONDS, Enum.EasingStyle.Linear)
					sweep(card.strip, -0.3, 1.3, 0.6)
				end
			end
		else
			tween(card.hoverK, { Value = 1 }, 0.2)
			tween(card.glow, { BackgroundTransparency = 1 }, 0.2)
			if card.stroke and not card.isBoss then
				tween(card.stroke, { Thickness = 3 }, 0.2)
			end
			if card.zoomTween then card.zoomTween:Cancel() card.zoomTween = nil end
			tween(card.zoomK, { Value = 1 }, 0.3)
		end
	end

	local function hoverIn(card)
		card.leaveToken = card.leaveToken + 1
		setCardHover(card, true)
	end
	local function hoverOut(card)
		card.leaveToken = card.leaveToken + 1
		local mine = card.leaveToken
		-- The panel reports a leave when the mouse moves onto one of its own buttons;
		-- wait a beat so an enter on a child cancels it.
		task.delay(0.06, function()
			if not destroyed and card.leaveToken == mine then
				setCardHover(card, false)
			end
		end)
	end

	-- ===== buttons =====
	local function wireButton(card, button, withShine)
		local bscale = Instance.new("UIScale")
		bscale.Name = "HoverScale"
		bscale.Parent = button
		local stroke = button:FindFirstChildOfClass("UIStroke")
		local baseColor = stroke and stroke.Color
		local baseThick = stroke and stroke.Thickness
		local hovering = false
		local shineStrip
		if withShine then
			local holder = Instance.new("Frame")
			holder.Name = "ShineClip"
			holder.Size = UDim2.new(1, 0, 1, 0)
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			holder.ClipsDescendants = true
			holder.Active = false
			holder.ZIndex = 12
			holder.Parent = button
			if roundCorner then roundCorner(holder, 10) end
			shineStrip = makeStrip(holder, 12, 0.75)
			shineStrip.Size = UDim2.new(0.22, 0, 2, 0)
		end

		local function enabled()
			return button.Visible and not isActionPending()
		end

		connect(button.MouseEnter, function()
			hoverIn(card)
			if not enabled() then return end
			hovering = true
			hoverSound()
			tween(bscale, { Scale = 1.05 }, 0.12)
			if stroke then
				tween(stroke, { Color = GOLD, Thickness = baseThick + 1.5 }, 0.12)
			end
			if shineStrip and not reducedMotion() then
				sweep(shineStrip, -0.3, 1.3, 0.45)
			end
		end)
		connect(button.MouseLeave, function()
			hoverOut(card)
			hovering = false
			tween(bscale, { Scale = 1 }, 0.12)
			if stroke then
				tween(stroke, { Color = baseColor, Thickness = baseThick }, 0.12)
			end
		end)
		connect(button.MouseButton1Down, function()
			if not enabled() then return end
			tween(bscale, { Scale = 0.96 }, 0.06)
		end)
		connect(button.MouseButton1Up, function()
			if destroyed then return end
			tween(bscale, { Scale = hovering and 1.05 or 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
	end

	-- ===== public =====
	-- entry: { panel, sceneImage, statusChip, tagLabel, selectButton, skipButton, isBossRound, cardScale }
	function self.addCard(entry)
		local panel = entry.panel
		local card = {
			entry = entry,
			scale = entry.cardScale,
			fit = entry.cardScale.Scale,
			kind = "future",
			isBoss = entry.isBossRound,
			chip = entry.statusChip,
			chipBase = entry.statusChip.BackgroundTransparency,
			tag = entry.tagLabel,
			stroke = panel:FindFirstChildOfClass("UIStroke"),
			hoverK = Instance.new("NumberValue"),
			breatheK = Instance.new("NumberValue"),
			zoomK = Instance.new("NumberValue"),
			loopToken = 0,
			loopTweens = {},
			leaveToken = 0,
			embers = {},
		}
		card.strokeBase = card.stroke and card.stroke.Color or GOLD
		card.hoverK.Value = 1
		card.breatheK.Value = 1
		card.zoomK.Value = 1
		for _, v in ipairs({ card.hoverK, card.breatheK, card.zoomK }) do
			v.Parent = panel
		end

		-- Clip frame for the art so the Ken Burns zoom never spills over the card.
		local artClip = Instance.new("Frame")
		artClip.Name = "ArtClip"
		artClip.Size = UDim2.new(1, 0, 1, 0)
		artClip.BackgroundTransparency = 1
		artClip.BorderSizePixel = 0
		artClip.ClipsDescendants = true
		artClip.Active = false
		artClip.ZIndex = 8
		artClip.Parent = panel
		if roundCorner then roundCorner(artClip, 14) end
		local img = entry.sceneImage
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.new(0.5, 0, 0.5, 0)
		img.Parent = artClip
		-- Keep the status chip at the card corner (it must not zoom with the art).
		entry.statusChip.Parent = artClip

		-- Brighten overlay (art tint itself is owned by RoundSelect's dimming).
		local glow = Instance.new("Frame")
		glow.Name = "HoverGlow"
		glow.Size = UDim2.new(1, 0, 1, 0)
		glow.BackgroundColor3 = CREAM
		glow.BackgroundTransparency = 1
		glow.BorderSizePixel = 0
		glow.Active = false
		glow.ZIndex = 9
		glow.Parent = artClip
		card.glow = glow

		-- Light sweep, clipped to the card, under the text (ZIndex 10 < 11).
		local sweepClip = Instance.new("Frame")
		sweepClip.Name = "SweepClip"
		sweepClip.Size = UDim2.new(1, 0, 1, 0)
		sweepClip.BackgroundTransparency = 1
		sweepClip.BorderSizePixel = 0
		sweepClip.ClipsDescendants = true
		sweepClip.Active = false
		sweepClip.ZIndex = 10
		sweepClip.Parent = panel
		if roundCorner then roundCorner(sweepClip, 14) end
		card.strip = makeStrip(sweepClip, 10, 0.8)

		-- Boss embers (hidden until the idle loop runs).
		if card.isBoss then
			for i = 1, EMBER_COUNT do
				local dot = Instance.new("Frame")
				dot.Name = "Ember" .. i
				local s = 4 + (i % 3) * 2
				dot.Size = UDim2.new(0, s, 0, s)
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.BackgroundColor3 = EMBER
				dot.BorderSizePixel = 0
				dot.Active = false
				dot.Visible = false
				dot.ZIndex = 10
				dot.Parent = artClip
				if roundCorner then roundCorner(dot, 6) end
				table.insert(card.embers, dot)
			end
		end

		connect(card.hoverK:GetPropertyChangedSignal("Value"), function() applyScale(card) end)
		connect(card.breatheK:GetPropertyChangedSignal("Value"), function() applyScale(card) end)
		connect(card.zoomK:GetPropertyChangedSignal("Value"), function()
			local k = card.zoomK.Value
			img.Size = UDim2.new(k, 0, k, 0)
		end)

		connect(panel.MouseEnter, function() hoverIn(card) end)
		connect(panel.MouseLeave, function() hoverOut(card) end)
		wireButton(card, entry.selectButton, true)
		wireButton(card, entry.skipButton, false)

		table.insert(cards, card)
		refreshLoops(card)
	end

	-- Called by fitCards with the viewport fit scale (0.6..1).
	function self.setFit(value)
		for _, card in ipairs(cards) do
			card.fit = value
			applyScale(card)
		end
	end

	-- kind: "current" | "past" | "future". Cheap to call on every rebuild.
	function self.setKind(entry, kind)
		for _, card in ipairs(cards) do
			if card.entry == entry then
				if card.kind ~= kind then
					card.kind = kind
					if card.hovered then
						card.hovered = nil
						setCardHover(card, true)
					end
				end
				refreshLoops(card)
				return
			end
		end
	end

	function self.destroy()
		if destroyed then return end
		destroyed = true
		for _, card in ipairs(cards) do
			stopLoops(card)
		end
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		connections = {}
	end

	-- Pause the loops while the overlay is hidden; restart when it shows again.
	connect(frame:GetPropertyChangedSignal("Visible"), function()
		for _, card in ipairs(cards) do
			if not frame.Visible then
				card.hovered = nil
				card.hoverK.Value = 1
				card.zoomK.Value = 1
			end
			refreshLoops(card)
		end
	end)
	connect(frame.Destroying, function() self.destroy() end)
	-- Re-evaluate when Reduce shake is toggled.
	if ClientSettings.onChanged then
		pcall(function()
			ClientSettings.onChanged(function()
				for _, card in ipairs(cards) do refreshLoops(card) end
			end)
		end)
	end

	return self
end

return FX
