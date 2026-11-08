--[[
	Client/TravelTransition.lua
	A short "travelling" cover shown when a round starts: a parchment map where the hero walks the road from the
	previous stop to the current one, with the place name as a caption. It covers the screen at once, waits until
	the round is ready (readyFn) for at least TravelTiming.MIN seconds and at most MAX, then fades out.
	The round-start request is sent by the caller right away; only the reveal waits. Tap to skip after 1s.
	Reduce Shake turns it into a plain quick fade. Timings are printed as [Transition].
	Rules live in Shared/Engine/TravelTiming.lua (tested).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local TravelTiming = require(Engine:WaitForChild("TravelTiming"))
local WorldMap = require(Engine:WaitForChild("WorldMap"))
local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local ClientSettings = require(script.Parent.ClientSettings)

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)

local TravelTransition = {}
local running = false

local function stopName(state, night)
	local id = state.worldRoute and state.worldRoute[night]
	local stop = id and WorldMap.Stops[id]
	if stop then
		return stop.name, stop.region
	end
	local entry = JourneyMap.Nights and JourneyMap.Nights[night]
	return entry and entry.name or "The Road", nil
end

-- opts: { state = latest state, readyFn = function() -> boolean }
function TravelTransition.show(opts)
	opts = opts or {}
	local state = opts.state
	if running or not TravelTiming.shouldRun(state) then
		return false
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	running = true

	local reduced = ClientSettings.get("reduceShake") == true
	local night = state.night or 1
	local toName, region = stopName(state, night)
	local fromName = night > 1 and select(1, stopName(state, night - 1)) or toName
	local tint = region and WorldMap.Regions[region] and WorldMap.Regions[region].tint or { 222, 200, 150 }

	local gui = Instance.new("ScreenGui")
	gui.Name = "TravelTransition"
	gui.DisplayOrder = 500
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	-- CanvasGroup so the whole cover fades with one GroupTransparency tween (no UIGradient Transparency).
	local cover = Instance.new("CanvasGroup")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.fromRGB(tint[1], tint[2], tint[3])
	cover.BorderSizePixel = 0
	cover.GroupTransparency = 0
	cover.Parent = gui

	-- Soft vignette: stepped dark frames at the screen edges.
	for i = 1, 8 do
		local inset = (i - 1) * 0.012
		local f = Instance.new("Frame")
		f.Name = "Vignette" .. i
		f.Size = UDim2.new(1 - 2 * inset, 0, 1 - 2 * inset, 0)
		f.Position = UDim2.fromScale(inset, inset)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.ZIndex = 1
		f.Parent = cover
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(40, 26, 14)
		s.Thickness = 14
		s.Transparency = 0.35 + i * 0.08
		s.Parent = f
	end

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.fromScale(0.5, 0.12)
	caption.Size = UDim2.fromOffset(700, 48)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.GothamBold
	caption.TextSize = 30
	caption.TextColor3 = CREAM
	caption.TextStrokeColor3 = INK
	caption.TextStrokeTransparency = 0.3
	caption.Text = toName
	caption.ZIndex = 5
	caption.Parent = cover

	local hint = Instance.new("TextLabel")
	hint.Name = "SkipHint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.fromOffset(300, 24)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 16
	hint.TextColor3 = CREAM
	hint.TextStrokeColor3 = INK
	hint.TextStrokeTransparency = 0.3
	hint.Text = "Tap to skip"
	hint.TextTransparency = 1
	hint.TextStrokeTransparency = 1
	hint.ZIndex = 5
	hint.Parent = cover

	local hero
	if not reduced then
		-- Road: dots along a gentle curve from the previous stop to this one.
		local ax, ay, bx, by = 0.22, 0.62, 0.78, 0.5
		local function pointAt(t)
			return ax + (bx - ax) * t, ay + (by - ay) * t - math.sin(t * math.pi) * 0.06
		end
		for i = 0, 16 do
			local x, y = pointAt(i / 16)
			local dot = Instance.new("Frame")
			dot.Name = "RoadDot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(x, y)
			dot.Size = UDim2.fromOffset(10, 10)
			dot.BackgroundColor3 = INK
			dot.BackgroundTransparency = 0.25
			dot.BorderSizePixel = 0
			dot.ZIndex = 2
			dot.Parent = cover
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = dot
		end
		local function marker(x, y, label)
			local m = Instance.new("Frame")
			m.Name = "Stop"
			m.AnchorPoint = Vector2.new(0.5, 0.5)
			m.Position = UDim2.fromScale(x, y)
			m.Size = UDim2.fromOffset(34, 34)
			m.BackgroundColor3 = Color3.fromRGB(222, 182, 104)
			m.ZIndex = 3
			m.Parent = cover
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = m
			local st = Instance.new("UIStroke")
			st.Color = INK
			st.Thickness = 2
			st.Parent = m
			local t = Instance.new("TextLabel")
			t.AnchorPoint = Vector2.new(0.5, 0)
			t.Position = UDim2.new(0.5, 0, 1, 6)
			t.Size = UDim2.fromOffset(260, 22)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.GothamBold
			t.TextSize = 16
			t.TextColor3 = CREAM
			t.TextStrokeColor3 = INK
			t.TextStrokeTransparency = 0.3
			t.Text = label
			t.ZIndex = 4
			t.Parent = m
		end
		marker(ax, ay, fromName)
		marker(bx, by, toName)

		-- Hero: the painted hero token (emoji fallback). The live avatar is not used here.
		local tokenId = ContentArt.getImageId("map_nodes", "hero_token")
		if tokenId then
			hero = Instance.new("ImageLabel")
			hero.BackgroundTransparency = 1
			hero.Image = tokenId
			hero.ScaleType = Enum.ScaleType.Fit
		else
			hero = Instance.new("TextLabel")
			hero.BackgroundTransparency = 1
			hero.Font = Enum.Font.GothamBold
			hero.TextSize = 36
			hero.Text = "🚶"
		end
		hero.Name = "Hero"
		hero.AnchorPoint = Vector2.new(0.5, 1)
		hero.Size = UDim2.fromOffset(56, 56)
		hero.Position = UDim2.fromScale(ax, ay)
		hero.ZIndex = 6
		hero.Parent = cover
		-- Walk along the curve over the minimum time, then wait at the destination.
		local progress = Instance.new("NumberValue")
		local walk = TweenService:Create(progress, TweenInfo.new(TravelTiming.MIN, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = 1 })
		progress.Changed:Connect(function(v)
			if hero and hero.Parent then
				local x, y = pointAt(v)
				hero.Position = UDim2.new(x, 0, y, math.sin(v * 40) * -3) -- small footstep bob
			end
		end)
		walk:Play()
		task.delay(TravelTiming.MAX + 1, function() progress:Destroy() end)
	end

	-- Tap anywhere to skip (only honoured after SKIP_AFTER seconds and once the round is ready).
	local skipRequested = false
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipSink"
	skipButton.Size = UDim2.fromScale(1, 1)
	skipButton.BackgroundTransparency = 1
	skipButton.Text = ""
	skipButton.AutoButtonColor = false
	skipButton.ZIndex = 10
	skipButton.Parent = cover
	skipButton.MouseButton1Click:Connect(function()
		skipRequested = true
	end)

	local startClock = os.clock()
	task.spawn(function()
		local readyAt = nil
		while gui.Parent do
			local elapsed = os.clock() - startClock
			if readyAt == nil and opts.readyFn then
				local okReady, ready = pcall(opts.readyFn)
				if okReady and ready == true then
					readyAt = elapsed
				end
			end
			if elapsed >= TravelTiming.SKIP_AFTER and not reduced then
				hint.TextTransparency = 0
				hint.TextStrokeTransparency = 0.3
			end
			if TravelTiming.shouldReveal(elapsed, readyAt, reduced, skipRequested) then
				print(string.format("[Transition] %s -> %s: ready after %s, revealed after %.2fs",
					fromName, toName, readyAt and string.format("%.2fs", readyAt) or "never (timed out)", elapsed))
				break
			end
			task.wait(0.05)
		end
		if gui.Parent then
			skipButton.Active = false
			skipButton.Visible = false -- never block input during the fade
			local fade = TweenService:Create(cover, TweenInfo.new(reduced and 0.15 or 0.4, Enum.EasingStyle.Quad), { GroupTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			gui:Destroy()
		end
		running = false
	end)
	return true
end

return TravelTransition
