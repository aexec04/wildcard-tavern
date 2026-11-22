--[[
	Client/HandReadout.lua
	A 16 px serif line just above the Play Hand button: best hand name and base Chips x Mult (Engine/HandReadout), live as cards
	are selected, hidden when nothing is. A short fade in, no tween in Calm mode. The label is parented to the action row's
	parent so the row's UIListLayout never lays it out.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Engine.HandReadout)
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local label, anchor

local function ensure(playButton)
	if label and label.Parent then return label end
	if not (playButton and playButton.Parent and playButton.Parent.Parent) then return nil end
	anchor = playButton
	label = Instance.new("TextLabel")
	label.Name = "HandReadout"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Garamond
	label.TextSize = Rules.TEXT_SIZE
	label.TextColor3 = Color3.fromRGB(242, 207, 114)
	label.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.AnchorPoint = Vector2.new(0, 1)
	label.Size = UDim2.fromOffset(240, 22)
	label.Visible = false
	label.ZIndex = 5
	label.Parent = playButton.Parent.Parent
	return label
end

local function place()
	if not (label and anchor and anchor.Parent and label.Parent) then return end
	local p = anchor.AbsolutePosition - label.Parent.AbsolutePosition
	label.Position = UDim2.fromOffset(p.X + (anchor.AbsoluteSize.X - 240) / 2, p.Y - 4)
end

-- name: the preview's hand name or nil when nothing is selected; handLevels: the run's levels
function M.set(playButton, name, handLevels)
	local lbl = ensure(playButton)
	if not lbl then return end
	local text = Rules.line(name, handLevels)
	if not text then
		lbl.Visible = false
		lbl.TextTransparency = 1
		lbl.TextStrokeTransparency = 1
		return
	end
	place()
	lbl.Text = text
	local wasHidden = not lbl.Visible
	lbl.Visible = true
	if ClientSettings.get("reduceShake") == true or not wasHidden then
		lbl.TextTransparency = 0
		lbl.TextStrokeTransparency = 0.5
	else
		lbl.TextTransparency, lbl.TextStrokeTransparency = 1, 1
		TweenService:Create(lbl, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	end
end

return M
