--[[
	Client/PatronVoice.lua
	A Patron's one-line voice (Engine/PatronLines) in a small parchment speech bubble beside its
	sidebar seat, plus a tiny hop on the seat. Cosmetic only. Rate limited: each Patron speaks at
	most once per hand (callers pass a hand key), and only one bubble shows at a time.
	Fast animation speed skips the bubble and the hop; Reduce shake skips the hop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PatronLines = require(Engine:WaitForChild("PatronLines"))
local ClientSettings = require(script.Parent.ClientSettings)

local PatronVoice = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(232, 212, 168)
local SHOW_SECONDS = 1.8
local QUOTE_SECONDS = 1.2 -- the v2 quote plate holds at least 1.0 s

local spokeThisHand = {} -- [patronId] = true, cleared when the hand key changes
local currentHandKey = nil
local bubble, bubbleLabel, bubbleToken = nil, nil, 0

local function ensureBubble(gui)
	if bubble and bubble.Parent == gui then return end
	if bubble then bubble:Destroy() end
	bubble = Instance.new("Frame")
	bubble.Name = "PatronVoiceBubble"
	bubble.AnchorPoint = Vector2.new(0, 0.5)
	bubble.Size = UDim2.fromOffset(190, 40)
	bubble.BackgroundColor3 = PARCHMENT
	bubble.BorderSizePixel = 0
	bubble.Active = false
	bubble.Visible = false
	bubble.ZIndex = 60
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(96, 64, 36)
	stroke.Thickness = 1.5
	stroke.Parent = bubble
	bubbleLabel = Instance.new("TextLabel")
	bubbleLabel.Size = UDim2.new(1, -12, 1, 0)
	bubbleLabel.Position = UDim2.fromOffset(6, 0)
	bubbleLabel.BackgroundTransparency = 1
	bubbleLabel.Font = Enum.Font.GothamBold
	bubbleLabel.TextSize = 16
	bubbleLabel.TextColor3 = INK
	bubbleLabel.TextWrapped = true
	bubbleLabel.ZIndex = 61
	bubbleLabel.Parent = bubble
	local tail = Instance.new("Frame") -- parchment tail on the top edge, points up at the speaking seat
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Size = UDim2.fromOffset(12, 12)
	tail.Position = UDim2.new(0, 24, 0, 0)
	tail.Rotation = 45
	tail.BackgroundColor3 = PARCHMENT
	tail.BorderSizePixel = 0
	tail.Active = false
	tail.Visible = false
	tail.ZIndex = 60
	tail.Parent = bubble
	local tailStroke = Instance.new("UIStroke")
	tailStroke.Color = Color3.fromRGB(96, 64, 36)
	tailStroke.Thickness = 1.5
	tailStroke.Parent = tail
end

-- handKey: any value that is the same for every Patron trigger within one scored hand.
-- slotFrame: the Patron's sidebar seat. Returns true when a line was shown.
local quietUntil = 0
-- The finale banner calls this: hide any bubble now and stay quiet while the banner is up.
function PatronVoice.suppress(seconds)
	quietUntil = os.clock() + (seconds or 2.5)
	PatronVoice.hide()
end

function PatronVoice.say(patronId, slotFrame, handKey)
	if os.clock() < quietUntil then return false end
	if handKey ~= currentHandKey then
		currentHandKey = handKey
		spokeThisHand = {}
	end
	if spokeThisHand[patronId] then return false end
	spokeThisHand[patronId] = true

	if ClientSettings.get("animSpeed") == "fast" then return false end
	if typeof(slotFrame) ~= "Instance" or not slotFrame.Parent then return false end
	local gui = slotFrame:FindFirstAncestorOfClass("ScreenGui")
	if not gui then return false end

	-- tiny hop on the seat (a frame inside a layout, so move a UIScale-free child offset via Rotation)
	if ClientSettings.get("reduceShake") ~= true then
		local rest = slotFrame.Rotation
		local up = TweenService:Create(slotFrame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = rest - 10 })
		up:Play()
		up.Completed:Connect(function()
			if slotFrame.Parent then
				TweenService:Create(slotFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = rest }):Play()
			end
		end)
	end

	pcall(ensureBubble, gui)
	if not bubble then return false end
	bubbleToken += 1
	local mine = bubbleToken
	bubbleLabel.Text = PatronLines.get(patronId)
	local pos = slotFrame.AbsolutePosition - gui.AbsolutePosition
	local size = slotFrame.AbsoluteSize
	-- open beside the whole left HUD column (the table area), never over its plates or the hand preview
	local col = slotFrame:FindFirstAncestor("SidebarBoard") or slotFrame:FindFirstAncestor("Sidebar")
	local left = pos.X + size.X + 8
	if col then left = math.max(left, col.AbsolutePosition.X - gui.AbsolutePosition.X + col.AbsoluteSize.X + 8) end
	bubble.AnchorPoint = Vector2.new(0, 0.5)
	bubble.Size = UDim2.fromOffset(190, 40)
	bubble.Position = UDim2.fromOffset(left, pos.Y + size.Y / 2)
	local bubbleV2, noRoom = false, false
	pcall(function() -- v2 table: below the Patron row, centred on its own Patron, never over a neighbour's face
		local okA, active = pcall(function() return require(script.Parent.Gameplay2).isActive() end)
		local okE, rowBottom = pcall(function() return require(script.Parent.PatronRow).bottomEdge() end)
		if okA and active and okE and rowBottom then
			local Eng = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
			local G2 = require(Eng:WaitForChild("Gameplay2Layout"))
			-- under the tag rows AND the trigger pill row (never over a rarity or effect pill), so the bubble starts below both
			local below = pos.Y + G2.triggerPillY(gui.AbsoluteSize.X, gui.AbsoluteSize.Y) + G2.TRIGGER_PILL_H
			bubbleV2 = true
			local PVL = require(Eng:WaitForChild("PatronVoiceLayout"))
			local R = PVL.rect(pos.X, size.X, below, gui.AbsoluteSize.X)
			local okS, sr = pcall(function() return require(script.Parent.Gameplay2).scoringRects() end)
			if okS and sr then -- a hand is scoring: beside the Score plate, never over it, the banner or the played cards (none when no room)
				R = PVL.beside(sr.plate, sr.stage, gui.AbsoluteSize.X)
				if not R then noRoom = true; return end
				pcall(function() print(string.format("[ScoringRects] quote %d,%d %dx%d plate %d,%d %dx%d banner %s cards %d to %d", R.x, R.y, R.w, R.h, sr.plate.x, sr.plate.y, sr.plate.w, sr.plate.h, sr.name and string.format("%d,%d %dx%d", sr.name.x, sr.name.y, sr.name.w, sr.name.h) or "none", sr.band.top, sr.band.bottom)) end)
			end
			bubble.AnchorPoint = Vector2.new(0, 0)
			bubble.Size = UDim2.fromOffset(R.w, R.h)
			bubble.Position = UDim2.fromOffset(R.x, R.y)
		end
	end)
	if noRoom then bubble.Visible = false; return true end -- scoring, and no clear spot beside the Score plate: stay silent
	if bubbleV2 then -- the painted parchment plate (TavernKit.painted keeps the flat look if the picture fails); the label keeps 8 px padding
		pcall(function() require(script.Parent.TavernKit).painted(bubble, "parchment") end)
		bubbleLabel.Position = UDim2.fromOffset(8, 0)
		bubbleLabel.Size = UDim2.new(1, -16, 1, 0)
		bubbleLabel.TextSize = 18
	end
	bubbleLabel.TextTransparency, bubbleLabel.TextStrokeTransparency = 0, 1 -- the words and the plate always appear and go together, never bare text
	local tail = bubble:FindFirstChild("Tail")
	if tail then
		tail.Visible = bubbleV2
		if bubbleV2 then
			local PVL = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronVoiceLayout"))
			local bx, bw = bubble.Position.X.Offset, bubble.Size.X.Offset
			tail.Position = UDim2.new(0, PVL.tailX({ x = bx, w = bw }, pos.X + size.X / 2), 0, 0)
		end
	end
	bubble.Visible = true
	if bubbleV2 and game:GetService("RunService"):IsStudio() then -- Studio only: where the quote stands 1.4 s after Play Hand
		task.delay(1.4, function()
			if mine == bubbleToken and bubble then
				print(string.format("[QuoteCheck] 1.4 s: visible=%s abs=%d,%d %dx%d textTransparency=%.2f bgTransparency=%.2f paint=%s", tostring(bubble.Visible), bubble.AbsolutePosition.X, bubble.AbsolutePosition.Y, bubble.AbsoluteSize.X, bubble.AbsoluteSize.Y, bubbleLabel.TextTransparency, bubble.BackgroundTransparency, tostring(bubble.Parent and bubble.Parent:FindFirstChild("PatronVoiceBubblePaint") ~= nil)))
			end
		end)
	end
	task.delay(bubbleV2 and QUOTE_SECONDS or SHOW_SECONDS, function() -- v2: the plate and the words stay at least 1.2 s, then both go in one step
		if mine == bubbleToken and bubble then bubble.Visible = false end
	end)
	return true
end

function PatronVoice.hide()
	bubbleToken += 1
	if bubble then bubble.Visible = false end
end

return PatronVoice
