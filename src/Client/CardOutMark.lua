--[[
	Client/CardOutMark.lua
	Marks the hand cards a Boss Round switches off ("Hearts score nothing this round", No VIPs, Quiet Corner).
	Before this, nothing on the table showed which cards the rule meant: the player had to read the rule and check
	every card against it.

	Which cards are out is Engine/BossRules.switchesOff, the rule the scoring itself uses, so the mark and the score
	cannot disagree (a test holds the two together for all 52 cards under every such rule).

	A marked card is dimmed and carries a small "No score" plate along its lower edge. Nothing moves, so there is
	nothing to switch off in calm mode. The mark is a child of the card's button named OutMark.

	refresh(handFrame, state)    call after every render: marks each hand card that is out, clears the rest.
	apply(button, card, state)   one card. Returns the mark, or nil.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local BossRounds = require(Engine:WaitForChild("BossRounds"))
local BossRules = require(Engine:WaitForChild("BossRules"))

local CardOutMark = {}

CardOutMark.TEXT = "No score"

local INK = Color3.fromRGB(60, 40, 22)
local PLATE = Color3.fromRGB(46, 30, 18)
local GOLD = Color3.fromRGB(222, 182, 104)
local PARCHMENT = Color3.fromRGB(240, 226, 196)

-- Card face layers use ZIndex 2 to 6 (CardFace.build is called with 2). The ScreenGui layers globally, so these are
-- absolute: above the face, far below tooltips and popups.
local Z_DIM, Z_PLATE, Z_TEXT = 7, 8, 9

-- The Boss Round of this state, or nil.
local function bossOf(state)
	local modifier = state and state.bossModifier
	return modifier and BossRounds.getById(modifier.id) or nil
end

function CardOutMark.isOut(card, state)
	return BossRules.switchesOff(card, bossOf(state))
end

function CardOutMark.apply(button, card, state)
	local old = button:FindFirstChild("OutMark")
	local out = CardOutMark.isOut(card, state)
	if old and out then
		return old -- already marked: leave it alone, so a state push does not rebuild it
	end
	if old then
		old:Destroy()
	end
	if not out then
		return nil
	end

	local mark = Instance.new("Frame")
	mark.Name = "OutMark"
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundColor3 = INK
	mark.BackgroundTransparency = 0.5
	mark.BorderSizePixel = 0
	mark.Active = false -- clicks go through to the card: a switched-off card can still be played or discarded
	mark.ZIndex = Z_DIM
	mark.Parent = button
	local markCorner = Instance.new("UICorner")
	markCorner.CornerRadius = UDim.new(0, 8)
	markCorner.Parent = mark

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 1, -8)
	plate.Size = UDim2.new(1, -10, 0, 24)
	plate.BackgroundColor3 = PLATE
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = Z_PLATE
	plate.Parent = mark
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 6)
	plateCorner.Parent = plate
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = GOLD
	plateStroke.Thickness = 1
	plateStroke.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = PARCHMENT
	label.Text = CardOutMark.TEXT
	label.Active = false
	label.ZIndex = Z_TEXT
	label.Parent = plate

	return mark
end

-- Every hand slot carries its card's index in the hand (the HandIndex attribute the hub sets when it builds the slot).
function CardOutMark.refresh(handFrame, state)
	local hand = state and state.hand or {}
	for _, slot in ipairs(handFrame:GetChildren()) do
		local index = slot:GetAttribute("HandIndex")
		local button = index and slot:FindFirstChildWhichIsA("TextButton")
		if button then
			CardOutMark.apply(button, hand[index], state)
		end
	end
end

return CardOutMark
