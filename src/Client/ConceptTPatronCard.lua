--[[
	Client/ConceptTPatronCard.lua
	The Concept T look under a Patron card in the play row: a rarity label pill (the word is part of the art, so rarity is never
	colour alone) and an effect pill with the live value in the game font. Image keys come from Engine/ConceptTLayout (tested).
	Both pieces are parented to the card's slot (they survive a clone), never pulse or tween (Calm mode looks the same), and are
	only shown for a Patron that has a Concept T cut card.

	set(slot, tier, valueText, hasCard)   tier "common".."legendary"; valueText "" or nil hides the effect pill
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ConceptTLayout"))
local Art = require(Engine:WaitForChild("ConceptTArt"))

local M = {}

local function piece(slot, name, z)
	local img = slot:FindFirstChild(name)
	if img then return img end
	img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Active = false
	img.ScaleType = Enum.ScaleType.Stretch
	img.ZIndex = z
	img.Parent = slot
	return img
end

function M.set(slot, tier, valueText, hasCard)
	local label = piece(slot, "CTLabel", 12)
	local pill = piece(slot, "CTPill", 12)
	local on = hasCard == true
	label.Visible = on
	pill.Visible = on and valueText ~= nil and valueText ~= ""
	if not on then return end
	label.Image = Art[Layout.labelKey(tier)] or ""
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 2)
	label.Size = UDim2.new(0.92, 0, 0, 22)
	pcall(function() require(script.Parent.RarityShape).set(label, tier, 12) end) -- a shape per tier beside the word, not colour alone
	pill.Image = Art[Layout.blankPillKey(tier)] or Art[Layout.pillKey(tier)] or ""
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 1, 26)
	pill.Size = UDim2.new(0.92, 0, 0, 26)
	local t = pill:FindFirstChild("Value")
	if not t then
		t = Instance.new("TextLabel")
		t.Name = "Value"
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = 15
		t.TextColor3 = Color3.fromRGB(255, 248, 224)
		t.TextTransparency = 0
		t.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
		t.TextStrokeTransparency = 0.2
		t.ZIndex = 13
		t.Parent = pill
	end
	t.Text = Layout.cleanValue(valueText)
end

return M
