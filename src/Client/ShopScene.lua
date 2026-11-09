--[[
	Client/ShopScene.lua
	The Peddler's Wagon dressing for the Counter (Shop overlay). Look only: no rules, prices or remotes.
	  * warm vignette strips and a wooden counter strip across the lower third (behind the offers, ZIndex 5);
	  * a hanging rail with ropes that sway slightly;
	  * Marlo the Peddler: painted slot "shop_peddler" (ContentArt category "shop") with a hooded emoji fallback,
	    idle bob, blink every 4 to 7 seconds and a parchment speech bubble (2 lines max) fed by ShopkeeperLines;
	  * at most 12 ambient objects (dust motes and a candle glow), all off in calm mode;
	  * reactions: onBuy (coin arc to Marlo and a nod), onReroll (rail shake), onCantAfford (Marlo line, no red flashing).
	Loops only run while the shop frame is visible. Everything is destroyed with the frame.

	ShopScene.new({ shopFrame, getState }) -> { say, sayText, onBuy, onReroll, onCantAfford, railShake }
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ShopScene = {}

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local MAX_AMBIENT = 12

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(235, 215, 170)

local function tween(obj, props, t, style, dir)
	if obj and obj.Parent then
		TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
	end
end

function ShopScene.new(deps)
	local shopFrame = deps.shopFrame
	local getState = deps.getState
	local ClientSettings = require(script.Parent.ClientSettings)
	local Cue = require(script.Parent.Cue)
	local Lines = require(Engine:WaitForChild("ShopkeeperLines"))
	local self = {}
	local rng = Random.new()
	local lineCount = 0
	local visits = 0
	local seenBefore = false

	local function calm()
		return ClientSettings.get("reduceShake") == true
	end

	local scene = Instance.new("Frame")
	scene.Name = "PeddlerScene"
	scene.Size = UDim2.fromScale(1, 1)
	scene.BackgroundTransparency = 1
	scene.Active = false
	scene.ZIndex = 5
	scene.ClipsDescendants = true
	scene.Parent = shopFrame

	-- Warm vignette: four dark edge strips (Color stops only, no Transparency gradient).
	local function edge(name, pos, size, rotation)
		local f = Instance.new("Frame")
		f.Name = name
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = Color3.fromRGB(30, 18, 8)
		f.BackgroundTransparency = 0.78
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 5
		f.Parent = scene
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(Color3.fromRGB(40, 22, 10), Color3.fromRGB(120, 70, 30))
		g.Rotation = rotation
		g.Parent = f
	end
	edge("VignetteTop", UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, 40), 90)
	edge("VignetteLeft", UDim2.fromScale(0, 0), UDim2.new(0, 36, 1, 0), 0)
	edge("VignetteRight", UDim2.new(1, -36, 0, 0), UDim2.new(0, 36, 1, 0), 180)

	-- Counter strip across the lower third: dark plank with a lighter lip on top.
	local counter = Instance.new("Frame")
	counter.Name = "CounterStrip"
	counter.AnchorPoint = Vector2.new(0, 1)
	counter.Position = UDim2.new(0, 0, 1, -58)
	counter.Size = UDim2.new(1, 0, 0, 56)
	counter.BackgroundColor3 = Color3.fromRGB(86, 56, 30)
	counter.BackgroundTransparency = 0.25
	counter.BorderSizePixel = 0
	counter.Active = false
	counter.ZIndex = 5
	counter.Parent = scene
	local lip = Instance.new("Frame")
	lip.Name = "CounterLip"
	lip.Size = UDim2.new(1, 0, 0, 5)
	lip.BackgroundColor3 = Color3.fromRGB(176, 128, 70)
	lip.BorderSizePixel = 0
	lip.Active = false
	lip.ZIndex = 5
	lip.Parent = counter

	-- Hanging rail near the top of the offer area, with ropes that sway.
	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.Position = UDim2.new(0, 24, 0, 78)
	rail.Size = UDim2.new(1, -48, 0, 6)
	rail.BackgroundColor3 = Color3.fromRGB(120, 80, 42)
	rail.BorderSizePixel = 0
	rail.Active = false
	rail.ZIndex = 5
	rail.Parent = scene
	local ropes = {}
	for i = 1, 5 do
		local rope = Instance.new("Frame")
		rope.Name = "Rope" .. i
		rope.AnchorPoint = Vector2.new(0.5, 0)
		rope.Position = UDim2.new((i - 0.5) / 5, 0, 1, 0)
		rope.Size = UDim2.fromOffset(3, 22)
		rope.BackgroundColor3 = Color3.fromRGB(190, 160, 110)
		rope.BorderSizePixel = 0
		rope.Active = false
		rope.ZIndex = 5
		rope.Parent = rail
		ropes[#ropes + 1] = rope
	end

	-- Marlo: portrait slot at the right of the counter, above the footer.
	local peddler = Instance.new("Frame")
	peddler.Name = "Peddler"
	peddler.AnchorPoint = Vector2.new(1, 1)
	peddler.Position = UDim2.new(1, -16, 1, -62)
	peddler.Size = UDim2.fromOffset(112, 128)
	peddler.BackgroundColor3 = Color3.fromRGB(58, 38, 22)
	peddler.BackgroundTransparency = 0.2
	peddler.Active = false
	peddler.ZIndex = 7
	peddler.Parent = shopFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = peddler
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(222, 182, 104)
		s.Thickness = 2
		s.Parent = peddler
	end
	local emoji = Instance.new("TextLabel")
	emoji.Name = "PeddlerEmoji"
	emoji.Size = UDim2.new(1, 0, 1, -22)
	emoji.BackgroundTransparency = 1
	emoji.Text = "\u{1F9D9}" -- hooded figure fallback until shop_peddler art exists
	emoji.TextSize = 64
	emoji.TextColor3 = Color3.fromRGB(250, 235, 200)
	emoji.TextTransparency = 0
	emoji.TextStrokeTransparency = 1
	emoji.ZIndex = 7
	emoji.Parent = peddler
	pcall(function()
		require(script.Parent.ArtIcon).apply(peddler, "shop", "shop_peddler", emoji, { cornerRadius = 10 })
	end)
	local nameTag = Instance.new("TextLabel")
	nameTag.Name = "PeddlerName"
	nameTag.AnchorPoint = Vector2.new(0, 1)
	nameTag.Position = UDim2.fromScale(0, 1)
	nameTag.Size = UDim2.new(1, 0, 0, 22)
	nameTag.BackgroundTransparency = 1
	nameTag.Text = "Marlo"
	nameTag.Font = Enum.Font.GothamBold
	nameTag.TextSize = 15
	nameTag.TextColor3 = Color3.fromRGB(250, 235, 200)
	nameTag.TextTransparency = 0
	nameTag.TextStrokeTransparency = 0.5
	nameTag.ZIndex = 8
	nameTag.Parent = peddler
	-- A blink overlay (dark lid strip) over the emoji eyes row; harmless over painted art.
	local lid = Instance.new("Frame")
	lid.Name = "Blink"
	lid.Position = UDim2.fromScale(0.3, 0.3)
	lid.Size = UDim2.fromScale(0.4, 0)
	lid.BackgroundColor3 = Color3.fromRGB(58, 38, 22)
	lid.BorderSizePixel = 0
	lid.Active = false
	lid.ZIndex = 8
	lid.Visible = false
	lid.Parent = peddler

	-- Speech bubble (parchment, 2 lines max).
	local bubble = Instance.new("TextLabel")
	bubble.Name = "PeddlerBubble"
	bubble.AnchorPoint = Vector2.new(1, 1)
	bubble.Position = UDim2.new(1, -16, 1, -194)
	bubble.Size = UDim2.fromOffset(200, 54)
	bubble.BackgroundColor3 = PARCHMENT
	bubble.BackgroundTransparency = 1
	bubble.Font = Enum.Font.GothamBold
	bubble.TextSize = 16
	bubble.TextColor3 = INK
	bubble.TextWrapped = true
	bubble.MaxVisibleGraphemes = -1
	bubble.TextTransparency = 1
	bubble.TextStrokeTransparency = 1
	bubble.Text = ""
	bubble.Active = false
	bubble.ZIndex = 9
	bubble.Visible = false
	bubble.Parent = shopFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = bubble
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(110, 76, 40)
		s.Thickness = 1.5
		s.Parent = bubble
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 8)
		p.PaddingRight = UDim.new(0, 8)
		p.Parent = bubble
	end

	local bubbleToken = 0
	local function seedFor(event)
		local st = getState() or {}
		return tostring(st.seed or st.runSeed or 0) .. "|" .. tostring(st.night or 0) .. "|" .. tostring(lineCount) .. event
	end

	-- Marlo says a line for an event (rate limited to one bubble at a time).
	local function show(text)
		bubbleToken += 1
		local token = bubbleToken
		bubble.Text = text
		bubble.Visible = true
		bubble.BackgroundTransparency = 0.05
		bubble.TextTransparency = 0
		if not calm() then
			peddler.Rotation = 0
			tween(peddler, { Rotation = 3 }, 0.1)
			task.delay(0.12, function()
				tween(peddler, { Rotation = 0 }, 0.15)
			end)
		end
		task.delay(2.6, function()
			if token ~= bubbleToken or not bubble.Parent then
				return
			end
			tween(bubble, { BackgroundTransparency = 1, TextTransparency = 1 }, 0.35)
			task.delay(0.4, function()
				if token == bubbleToken and bubble.Parent then
					bubble.Visible = false
				end
			end)
		end)
	end

	function self.say(event)
		lineCount += 1
		show(Lines.pick(event, seedFor(event)))
	end

	-- A fixed line (the haggle result), same bubble.
	function self.sayText(text)
		show(text)
	end

	function self.railShake()
		if calm() or not rail.Parent then
			return
		end
		task.spawn(function()
			for _, angle in ipairs({ -1.2, 1.2, -0.8, 0.8, 0 }) do
				if not rail.Parent then
					return
				end
				tween(scene, { Rotation = angle }, 0.05)
				task.wait(0.05)
			end
		end)
	end

	-- A small coin flies from where the player clicked to Marlo, who nods.
	function self.onBuy(event)
		Cue.play("shop_buy")
		self.say(event or "buy")
		if calm() then
			return
		end
		local ok = pcall(function()
			local mouse = UserInputService:GetMouseLocation()
			local coin = Instance.new("TextLabel")
			coin.Name = "ShopCoin"
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.Size = UDim2.fromOffset(26, 26)
			coin.BackgroundTransparency = 1
			coin.Text = "\u{1FA99}"
			coin.TextSize = 22
			coin.TextTransparency = 0
			coin.TextStrokeTransparency = 1
			coin.ZIndex = 10
			local origin = shopFrame.AbsolutePosition
			coin.Position = UDim2.fromOffset(mouse.X - origin.X, mouse.Y - origin.Y - 36)
			coin.Parent = shopFrame
			local target = peddler.AbsolutePosition - origin
			tween(coin, { Position = UDim2.fromOffset(target.X + 56, target.Y + 40) }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(coin, { Rotation = 360 }, 0.45)
			task.delay(0.5, function()
				coin:Destroy()
			end)
		end)
		if ok then
			tween(peddler, { Position = UDim2.new(1, -16, 1, -56) }, 0.1)
			task.delay(0.12, function()
				tween(peddler, { Position = UDim2.new(1, -16, 1, -62) }, 0.15, Enum.EasingStyle.Back)
			end)
		end
	end

	function self.onReroll()
		Cue.play("shop_reroll")
		self.say("reroll")
		self.railShake()
	end

	-- Never red flashing: Marlo answers and the rail ropes give a small wobble.
	function self.onCantAfford()
		Cue.play("shop_cant")
		self.say("cantAfford")
		if not calm() then
			for _, rope in ipairs(ropes) do
				rope.Rotation = 0
				tween(rope, { Rotation = 4 }, 0.08)
				task.delay(0.1, function()
					tween(rope, { Rotation = 0 }, 0.2, Enum.EasingStyle.Back)
				end)
			end
		end
	end

	-- Ambient loops (only while visible): rope sway, Marlo bob and blink, dust motes, candle glow.
	local glow = Instance.new("Frame")
	glow.Name = "CandleGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 1, -66)
	glow.Size = UDim2.fromOffset(360, 36)
	glow.BackgroundColor3 = Color3.fromRGB(255, 190, 90)
	glow.BackgroundTransparency = 0.88
	glow.BorderSizePixel = 0
	glow.Active = false
	glow.ZIndex = 5
	glow.Parent = scene
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = glow
	end

	local motes = {}
	local function spawnMote()
		if #motes >= MAX_AMBIENT - 1 then
			return
		end
		local mote = Instance.new("Frame")
		mote.Name = "DustMote"
		local size = rng:NextInteger(3, 5)
		mote.Size = UDim2.fromOffset(size, size)
		mote.Position = UDim2.new(rng:NextNumber(0.05, 0.95), 0, rng:NextNumber(0.4, 0.8), 0)
		mote.BackgroundColor3 = Color3.fromRGB(255, 230, 170)
		mote.BackgroundTransparency = 0.7
		mote.BorderSizePixel = 0
		mote.Active = false
		mote.ZIndex = 5
		mote.Parent = scene
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = mote
		end
		motes[#motes + 1] = mote
		local life = rng:NextNumber(5, 8)
		tween(mote, { Position = mote.Position + UDim2.new(0.03, 0, -0.12, 0), BackgroundTransparency = 1 }, life, Enum.EasingStyle.Sine)
		task.delay(life, function()
			local i = table.find(motes, mote)
			if i then
				table.remove(motes, i)
			end
			mote:Destroy()
		end)
	end

	local running = false
	local function loop()
		if running then
			return
		end
		running = true
		task.spawn(function()
			local t = 0
			local nextBlink = rng:NextNumber(4, 7)
			local nextMote = 0
			while shopFrame.Parent and shopFrame.Visible do
				local dt = task.wait(0.1)
				t += dt
				if not calm() then
					for i, rope in ipairs(ropes) do
						rope.Rotation = math.sin(t * 1.3 + i) * 2
					end
					peddler.Position = UDim2.new(1, -16, 1, -62 + math.floor(math.sin(t * 1.6) * 2 + 0.5))
					glow.BackgroundTransparency = 0.86 + math.sin(t * 5.3) * 0.03 + math.sin(t * 2.1) * 0.02
					nextMote -= dt
					if nextMote <= 0 then
						nextMote = rng:NextNumber(0.7, 1.4)
						spawnMote()
					end
				end
				nextBlink -= dt
				if nextBlink <= 0 then
					nextBlink = rng:NextNumber(4, 7)
					lid.Size = UDim2.fromScale(0.4, 0.06)
					lid.Visible = true
					task.delay(0.12, function()
						lid.Visible = false
					end)
				end
			end
			running = false
		end)
	end

	shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if shopFrame.Visible then
			visits += 1
			Cue.play("shop_enter")
			local st = getState() or {}
			local event = "enter"
			if not seenBefore then
				seenBefore = true
				event = "enterFirstTime"
			elseif (st.tips or 0) <= 2 then
				event = "lowTips"
			elseif (st.tips or 0) >= 20 then
				event = "richTips"
			end
			self.say(event)
			loop()
		else
			bubbleToken += 1
			bubble.Visible = false
			for _, mote in ipairs(motes) do
				mote:Destroy()
			end
			motes = {}
		end
	end)
	if shopFrame.Visible then
		loop()
	end

	return self
end

return ShopScene
