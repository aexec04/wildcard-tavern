--[[
	Client/RoundRewardBanner.lua
	Round Complete without a Continue click: the painted ornate plate (same piece as the Counter summary plate) centred under the top bar lists
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
local Celebration = require(Engine:WaitForChild("Celebration"))
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
		if current.partsRow then current.partsRow.Visible = false end -- the third row is the flavor line now
		current.flavorLabel.Visible = true
	end
end

local pendingScore -- "Score 199 of 65", handed over by Gameplay2 when the round is cleared (either order works)

function RoundRewardBanner.rememberScore(text)
	pendingScore = type(text) == "string" and text or nil
	if current and current.clearedRow and pendingScore then current.clearedRow.Text = "Target cleared  " .. pendingScore end
end

local function label(parent, text, size, color, order, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.LayoutOrder = order
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.Text = text
	l.TextColor3 = color
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0.5
	l.TextStrokeColor3 = Color3.fromRGB(30, 20, 12)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.ZIndex = Z + 1
	l.Parent = parent
	return l
end

function RoundRewardBanner.show(args)
	close()
	local screenGui = args.screenGui
	if not screenGui then return end
	local calm = ClientSettings.get("reduceShake") == true or ClientSettings.get("reduceMotion") == true
	local plan = RewardBanner.plan(ClientSettings.get("animSpeed"), calm)
	local data = Payout.breakdown(args.amount, args.interest or 0)

	local gui = Instance.new("CanvasGroup") -- one GroupTransparency fades the whole plate (a fade, no motion: Calm mode has none)
	gui.Name = "RoundRewardBanner"
	local sw, sh = screenGui.AbsoluteSize.X, screenGui.AbsoluteSize.Y
	local spot = RewardBanner.place(sw, require(Engine:WaitForChild("ShopSummary")).rect(sw, sh))
	gui.Position = UDim2.fromOffset(spot.x, spot.y)
	gui:SetAttribute("PaintW", spot.w) -- slice by the layout size so all four corners stay on the plate (TavernKit.painted); set before Size
	gui:SetAttribute("PaintH", spot.h)
	gui.Size = UDim2.fromOffset(spot.w, spot.h)
	gui.BackgroundColor3 = PLATE
	gui.BorderSizePixel = 0
	gui.Active = false
	gui.ZIndex = Z
	gui.GroupTransparency = plan.fadeIn > 0 and 1 or 0
	gui.Parent = screenGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = gui
	local edge = Instance.new("UIStroke")
	edge.Color = BRASS
	edge.Thickness = 3
	edge.Parent = gui
	pcall(function() require(script.Parent.TavernKit).painted(gui, "orn_target") end) -- the same painted plate as the Counter summary (flat plate and brass edge stay if the picture is missing)
	local inset = 30 -- 22 px carved border plus 8 px
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, inset), UDim.new(0, inset)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, inset), UDim.new(0, inset)
	pad.Parent = gui
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 0)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = gui

	-- three rows: "Round Complete  +$4 Tips" (counts up), "Target cleared  Score 199 of 65" in the gold heading, then the parts or the flavor line
	local toast = Payout.toastLines(args.amount, args.interest or 0)
	local mainRow = label(gui, toast.main, 20, GOLD_TEXT, 1, Enum.Font.GothamBold)
	mainRow.Name = "Main"
	pcall(function() require(script.Parent.ConceptTSkin).title(mainRow, { 255, 214, 130 }) end) -- serif gold with a dark outline
	local clearedRow = label(gui, pendingScore and ("Target cleared  " .. pendingScore) or RewardBanner.clearedLine(args.score, args.target), 16, GOLD_TEXT, 2, Enum.Font.GothamBold)
	clearedRow.Name = "Cleared"
	pendingScore = nil -- used up: the next round hands over its own
	local partsRow = label(gui, toast.sub or "", 14, SOFT, 3, Enum.Font.GothamMedium)
	partsRow.Name = "Parts"
	partsRow.Visible = toast.sub ~= nil
	local flavorLabel = label(gui, args.flavor or "", 14, SOFT, 4, Enum.Font.GothamMedium)
	flavorLabel.Name = "Flavor"
	flavorLabel.Visible = type(args.flavor) == "string" and args.flavor ~= "" and not partsRow.Visible -- one third row only

	pcall(function() -- the Tips count up one coin at a time, then every Patron hops in order (none in Calm mode)
		require(script.Parent.CelebrationFX).countUp(mainRow, Payout.breakdown(args.amount, args.interest or 0).total, function(n) return Payout.toastLines(n, 0).main end)
		require(script.Parent.PatronRow).celebrate()
	end)
	pcall(function() require(script.Parent.Cue).play("coin", 2) end)
	pcall(function() require(script.Parent.Cue).play("round_clear", 3) end) -- no id yet: silent
	pcall(function() require(script.Parent.ConfettiFX).burst(screenGui, args.big == true) end) -- gold and purple, none in calm mode

	current = { gui = gui, conns = {}, onClose = args.onClose, flavorLabel = flavorLabel, clearedRow = clearedRow, partsRow = partsRow }
	if RunService:IsStudio() then print(("[RoundPlate] x=%d y=%d w=%d h=%d (summary x=%d)"):format(spot.x, spot.y, spot.w, spot.h, require(Engine:WaitForChild("ShopSummary")).rect(sw, sh).x)) end
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
