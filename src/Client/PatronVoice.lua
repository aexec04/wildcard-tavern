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
end

-- handKey: any value that is the same for every Patron trigger within one scored hand.
-- slotFrame: the Patron's sidebar seat. Returns true when a line was shown.
function PatronVoice.say(patronId, slotFrame, handKey)
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
	bubble.Position = UDim2.fromOffset(left, pos.Y + size.Y / 2)
	bubble.Visible = true
	task.delay(SHOW_SECONDS, function()
		if mine == bubbleToken and bubble then bubble.Visible = false end
	end)
	return true
end

function PatronVoice.hide()
	bubbleToken += 1
	if bubble then bubble.Visible = false end
end

return PatronVoice
