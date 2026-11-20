--[[
	Client/MenuDailyEntry.lua
	The Daily Challenge entry on the Menu's Notice Board, rebuilt with the TavernKit green plate (the board keeps its parchment look).
	One real button starts the Daily exactly as the Daily action row does (Menu.lua passes the same function to both).

	attach(parent, layoutOrder, onPlay) -> the note Frame (board.pin puts it on a slot)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MenuDailyEntry"))
local Kit = require(script.Parent.TavernKit)

local M = {}

local WOOD = Color3.fromRGB(86, 58, 34)
local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)

function M.attach(parent, layoutOrder, onPlay)
	local frame = Instance.new("Frame")
	frame.Name = "MenuDailyEntry"
	frame.Size = UDim2.fromOffset(460, Rules.NOTE_H)
	frame.LayoutOrder = layoutOrder or Rules.ORDER
	frame.BackgroundColor3 = WOOD -- flat fallback; the painted plate goes on when the board pins the note
	frame.ZIndex = 10
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local function text(name, str, size, font, y, h, color)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.Size = UDim2.new(1, -60, 0, h)
		t.Position = UDim2.fromOffset(30, y) -- 30 px clear of the painted plate's gold ends
		t.BackgroundTransparency = 1
		t.Font = font
		t.TextSize = size
		t.TextColor3 = color
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Text = str
		t.Active = false
		t.ZIndex = 11
		t.Parent = frame
		return t
	end
	text("Title", Rules.TITLE, 18, Enum.Font.Merriweather, 10, 22, GOLD)
	text("Text", Rules.LINE, 14, Enum.Font.GothamMedium, 32, 36, CREAM)

	local play = Kit.primaryButton(frame, Rules.BUTTON_TEXT)
	play.Name = "DailyPlay"
	play.AnchorPoint = Vector2.new(1, 1)
	play.Size = UDim2.fromOffset(Rules.BUTTON.w, Rules.BUTTON.h)
	play.Position = UDim2.new(1, -30, 1, -8)
	play.ZIndex = 12
	play.TextSize = 15
	play.MouseButton1Click:Connect(function()
		if onPlay then onPlay() end
	end)
	return frame
end

return M
