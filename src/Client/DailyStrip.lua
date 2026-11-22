--[[
	Client/DailyStrip.lua
	Draws Engine/DailyStrip: a slim TavernKit strip (streak, today's goal with a progress bar, a chest plate) at the bottom of the
	Night map and Run Over, never on the table. The chest fires the existing ClaimLoginReward remote; the server re-checks the day
	and the one claim per UTC day, so a double click or an old client can not claim twice. Display only otherwise.
	Calm mode, Reduce motion and Fast speed: the chest opens at once, no tween.

	update(state)   called from render(); creates the strip on first use, shows or hides it, redraws on change
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("DailyStrip"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local Kit = require(script.Parent.TavernKit)

local M = {}

local function color(name) local c = Style.rgb(name); return Color3.fromRGB(c[1], c[2], c[3]) end

local strip, lastKey, lastChest

local function gui()
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild("GameUI")
end

local function label(parent, name, size, x, y, w, h, text, align)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Font = Enum.Font.Merriweather
	t.TextSize = size
	t.TextColor3 = color("cream")
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.6
	t.TextStrokeColor3 = color("outline")
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	t.Active = false
	t.ZIndex = 43 -- above the plate (ZIndex 40): under ZIndexBehavior.Global a lower child draws UNDER its parent, which hid every word
	t.Parent = parent
	return t
end

-- bottom edge of the lowest room card while the Night map is up (nil elsewhere), in GameUI pixels
local function cardsBottom(g, phase)
	if phase ~= "roundSelect" then return nil end
	local rs = g:FindFirstChild("RoundSelect", true)
	if not rs or not rs:IsA("GuiObject") or not rs.Visible then return nil end
	local bottom
	for _, d in ipairs(rs:GetDescendants()) do
		if d:IsA("GuiObject") and d.Name:match("^RoundPanel%d") then
			local b = d.AbsolutePosition.Y + d.AbsoluteSize.Y - g.AbsolutePosition.Y
			if not bottom or b > bottom then bottom = b end
		end
	end
	return bottom
end

local function build(root)
	local f = Kit.plate(root, UDim2.fromOffset(Rules.MAX_W, Rules.HEIGHT))
	f.Name = "DailyStrip"
	f.Active = false
	f.ZIndex = 40
	f.Visible = false
	pcall(function() Kit.painted(f, "wh_target") end) -- the ornate gold framed plate of the table (Target and Tips), flat look if it does not load; , flat look if it does not load
	label(f, "Streak", 15, 30, 0, 150, Rules.HEIGHT, "")
	label(f, "Goal", 15, 168, 2, 200, 24, "")
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BorderSizePixel = 0
	track.BackgroundColor3 = color("plateDark")
	track.Active = false
	track.ZIndex = 43
	track.Parent = f
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = color("gold")
	fill.Active = false
	fill.ZIndex = 44
	fill.Parent = track
	for _, p in ipairs({ track, fill }) do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = p
	end
	local chest = Instance.new("TextButton")
	chest.Name = "Chest"
	chest.ZIndex = 45
	chest.Parent = f
	return f
end

local lastState, hooked

function M.update(state)
	local g = gui()
	if not g then return end
	local menu = g:FindFirstChild("MenuRoot", true)
	local onMenu = menu ~= nil and menu:IsA("GuiObject") and menu.Visible
	-- No state yet (Studio with no DataStore, or the menu opened before the first render): the Menu still shows the strip with its
	-- placeholder words (Rules.view falls back for nil login and quests), so it is never just missing.
	if type(state) ~= "table" then
		state = lastState or {} -- phase is nil without a state, so off the Menu the strip hides below
	else
		lastState = state
	end
	if not strip or not strip.Parent then strip = build(g); lastKey = nil end
	if menu and not hooked then
		hooked = true
		menu:GetPropertyChangedSignal("Visible"):Connect(function() M.update(lastState) end) -- opening the Menu draws the strip without waiting for a render
	end
	local show = onMenu or Rules.visible(state.phase)
	strip.Visible = show
	if not show then return end

	local v = Rules.view(state.login, state.dailyQuests)
	local size = g.AbsoluteSize
	local r
	if onMenu then r = Rules.menuRect(size.X, size.Y) -- bottom row between the Deal Me In column and All actions
	else r = Rules.rectBelow(size.X, size.Y, cardsBottom(g, state.phase)) end
	if not r then strip.Visible = false; return end -- no clear band under the cards: leave it out rather than cover them
	strip.Chest:SetAttribute("ClaimDay", v.claimDay) -- always current, so a refused claim can be tried again
	strip.Chest:SetAttribute("State", v.chest)
	local key = table.concat({ v.streakText, v.chestText, v.goalText, v.chest, r.x, r.y, r.w, r.h, onMenu and "m" or "n" }, "|")
	if key == lastKey then return end
	lastKey = key

	if onMenu then print(string.format("[MenuRects] strip x=%d y=%d w=%d h=%d (screen %dx%d)", r.x, r.y, r.w, r.h, size.X, size.Y)) end
	strip.Position = UDim2.fromOffset(r.x, r.y)
	strip.Size = UDim2.fromOffset(r.w, r.h)
	local cr = Rules.chestRect(r)
	strip.Streak.Text = v.streakText
	strip.Streak.Size = UDim2.fromOffset(math.min(150, math.floor(r.w * 0.3)), r.h)
	local goalX = strip.Streak.Position.X.Offset + strip.Streak.Size.X.Offset + 14 -- 30 px in from the carved gold end
	local goalW = math.max(40, cr.x - goalX - 12)
	strip.Goal.Position = UDim2.fromOffset(goalX, 2)
	strip.Goal.Size = UDim2.fromOffset(goalW, 24)
	strip.Goal.Text = v.goalText
	strip.Track.Position = UDim2.fromOffset(goalX, 30)
	strip.Track.Size = UDim2.fromOffset(goalW, 8)
	strip.Track.Fill.Size = UDim2.fromScale(math.clamp(v.progress / v.goal, 0, 1), 1)

	local chest = strip.Chest
	Kit.skin(chest, v.chestText, v.chest == "ready" and "primary" or "secondary")
	pcall(Kit.paintedButton, chest, v.chest == "ready" and "primary" or "secondary") -- lit ornate button, flat look if the picture does not load
	chest.Position = UDim2.fromOffset(cr.x, cr.y)
	chest.Size = UDim2.fromOffset(cr.w, cr.h)
	chest.Active = v.chest == "ready"
	chest.AutoButtonColor = false
	-- claimable: a gold ring that breathes; static (solid ring) in Calm mode, Reduce motion and Fast
	local ring = chest:FindFirstChild("ReadyRing")
	if v.pulse then
		if not ring then
			ring = Instance.new("UIStroke")
			ring.Name = "ReadyRing"
			ring.Color = color("gold")
			ring.Thickness = 3
			ring.Parent = chest
			if not Kit.still() then
				TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 1 }):Play()
			end
		end
	elseif ring then
		ring:Destroy()
	end
	if not chest:GetAttribute("Wired") then
		chest:SetAttribute("Wired", true)
		chest.MouseButton1Click:Connect(function()
			local day = chest:GetAttribute("ClaimDay")
			local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("ClaimLoginReward")
			if remote and chest:GetAttribute("State") == "ready" and day then
				chest:SetAttribute("State", "opened") -- one click per day; the server decides the rest
				remote:FireServer(day)
			end
		end)
	end

	-- A small reveal when the chest changes from ready to opened. Calm mode, Reduce motion, Fast: none.
	if lastChest == "ready" and v.chest == "opened" and not Kit.still() then
		local t = Rules.reveal(false, false)
		local pop = Instance.new("UIScale")
		pop.Scale = 1.15
		pop.Parent = chest
		local tw = TweenService:Create(pop, TweenInfo.new(t.open, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		tw.Completed:Connect(function() pop:Destroy() end)
		tw:Play()
	end
	lastChest = v.chest
end

return M
