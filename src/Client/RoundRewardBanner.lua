--[[
	Client/RoundRewardBanner.lua
	Round Complete without a Continue click: a small dark parchment plate with a brass edge near the top centre of the screen lists
	Round reward, Interest and a gold Total, counts the Tips up, holds about 2.2 s (1.2 s on fast animation, no fades in calm mode)
	and fades out by itself. It never blocks: it is not a "...Backdrop", takes no input, and the Counter, Reroll, Haggle, the cards and
	Next Round work from the first frame. A click or key press anywhere (after a short grace) closes it early. Timing lives in the
	tested Engine/RewardBanner; the amounts come from Engine/RoundPayout. The economy is not touched, this only draws.

	RoundRewardBanner.show({ screenGui, title, amount, interest, flavor, onClose })
	    flavor   one small line under the Total (a callout such as the Counter's "Big spender today!", merged here by Client/Announcer
	             instead of a second overlapping label); RoundRewardBanner.setFlavor(text) adds it while the plate is up
	    onClose  called once when the plate is gone (Client/Announcer frees the centre of the screen then)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local RewardBanner = require(Engine:WaitForChild("RewardBanner"))
local Payout = require(Engine:WaitForChild("RoundPayout"))
local ClientSettings = require(script.Parent.ClientSettings)

local RoundRewardBanner = {}

local PLATE = Color3.fromRGB(46, 34, 24)
local BRASS = Color3.fromRGB(200, 160, 84)
local CREAM = Color3.fromRGB(250, 238, 212)
local GOLD_TEXT = Color3.fromRGB(255, 214, 130)
local SOFT = Color3.fromRGB(226, 206, 168)
local Z = 55 -- over the Counter and the table, under every modal (the Choice screens start at 60)

local current -- the banner on screen: { gui, conns, onClose, flavorLabel }

local function close()
	if not current then return end
	local onClose = current.onClose
	for _, c in ipairs(current.conns) do c:Disconnect() end
	if current.gui then current.gui:Destroy() end
	current = nil
	if onClose then pcall(onClose) end
end

function RoundRewardBanner.setFlavor(text)
	if current and current.flavorLabel and type(text) == "string" and text ~= "" then
		current.flavorLabel.Text = text
		current.flavorLabel.Visible = true
	end
end

local function label(parent, text, size, color, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size + 8)
	l.LayoutOrder = order
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.Text = text
	l.TextColor3 = color
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = Z + 1
	l.Parent = parent
	return l
end

function RoundRewardBanner.show(args)
	close()
	local screenGui = args.screenGui
	if not screenGui then return end
	local calm = ClientSettings.get("reduceShake") == true
	local plan = RewardBanner.plan(ClientSettings.get("animSpeed"), calm)
	local data = Payout.breakdown(args.amount, args.interest or 0)

	local gui = Instance.new("CanvasGroup") -- one GroupTransparency fades the whole plate
	gui.Name = "RoundRewardBanner"
	gui.AnchorPoint = Vector2.new(0.5, 0)
	gui.Position = UDim2.new(0.5, 0, 0, calm and 64 or 48) -- under the Roblox top bar, above the offers; slides down 16 px as it fades in
	gui.Size = UDim2.fromOffset(420, 0)
	gui.AutomaticSize = Enum.AutomaticSize.Y
	gui.BackgroundColor3 = PLATE
	gui.BorderSizePixel = 0
	gui.Active = false
	gui.ZIndex = Z
	gui.GroupTransparency = plan.fadeIn > 0 and 1 or 0
	gui.Parent = screenGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = gui
	local minSize = Instance.new("UISizeConstraint") -- a strip at least 64 px tall
	minSize.MinSize = Vector2.new(0, 64)
	minSize.Parent = gui
	if not calm then
		pcall(function() game:GetService("TweenService"):Create(gui, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 64) }):Play() end)
	end
	local edge = Instance.new("UIStroke")
	edge.Color = BRASS
	edge.Thickness = 3
	edge.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	pad.Parent = gui
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = gui

	-- ONE line: "Round Complete  +$4 Tips" (counts up); a small second line names the parts when interest was paid
	local toast = Payout.toastLines(args.amount, args.interest or 0)
	local mainRow = label(gui, toast.main, 18, GOLD_TEXT, 1)
	mainRow.Name = "Main"
	if toast.sub then
		local subRow = label(gui, toast.sub, 14, SOFT, 2)
		subRow.Name = "Parts"
		subRow.Font = Enum.Font.GothamMedium
	end
	local flavorLabel = label(gui, args.flavor or "", 15, SOFT, 50)
	flavorLabel.Name = "Flavor"
	flavorLabel.Font = Enum.Font.GothamMedium
	flavorLabel.Visible = type(args.flavor) == "string" and args.flavor ~= ""

	pcall(function() require(script.Parent.Cue).play("coin", 2) end)

	current = { gui = gui, conns = {}, onClose = args.onClose, flavorLabel = flavorLabel }
	local me = current
	local started = os.clock()
	local dismissedAt = nil
	local function onInput(input)
		if current ~= me or dismissedAt then return end
		local t = os.clock() - started
		if not RewardBanner.canDismiss(plan, t) then return end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.Keyboard then
			dismissedAt = t
		end
	end
	table.insert(me.conns, UserInputService.InputBegan:Connect(onInput))
	table.insert(me.conns, RunService.Heartbeat:Connect(function()
		if current ~= me then return end
		local t = os.clock() - started
		local phase, alpha = RewardBanner.phaseAt(plan, t, dismissedAt)
		if phase == "done" then
			close()
			return
		end
		gui.GroupTransparency = 1 - alpha
		mainRow.Text = Payout.toastLines(RewardBanner.countAt(plan, data.total, t), 0).main
	end))
end

RoundRewardBanner.close = close

return RoundRewardBanner
