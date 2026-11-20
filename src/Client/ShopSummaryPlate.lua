--[[
	Client/ShopSummaryPlate.lua
	A lasting plate on the Counter: "Target cleared", "Score N of T", "Tips +N" (rects from Engine/ShopSummary, look from TavernKit).
	Gameplay2 hands over the lines when a round is cleared (remember); Shop.lua attaches the plate to the shop frame once, so it
	shows and hides with the Counter. No tweens. Gameplay v2 only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Summary = require(Engine:WaitForChild("ShopSummary"))
local Flags = require(Engine:WaitForChild("FeatureFlags"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local Kit = require(script.Parent.TavernKit)

local M = {}
local lines, plate, labels

local function paint()
	if not plate then return end
	local on = lines ~= nil and Flags.gameplay() == 2
	plate.Visible = on
	if on and labels then
		labels.Title.Text, labels.Score.Text, labels.Tips.Text = lines.title, lines.score, lines.tips
	end
end

local function place(shopFrame)
	local size = shopFrame.AbsoluteSize
	local r = Summary.rect(size.X, size.Y)
	plate.Position = UDim2.fromOffset(r.x, r.y)
	plate.Size = UDim2.fromOffset(r.w, r.h)
end

function M.remember(clear)
	lines = Summary.lines(clear)
	paint()
end

function M.attach(shopFrame)
	if not shopFrame or shopFrame:FindFirstChild("RoundSummary") then return end
	plate = Kit.plate(shopFrame, UDim2.fromOffset(Summary.WIDTH_MAX, Summary.HEIGHT))
	plate.Name = "RoundSummary"
	plate.Active = false
	plate.ZIndex = 12
	pcall(function() Kit.painted(plate, "wood_plate") end)
	labels = {}
	local rr = Summary.rows(Summary.WIDTH_MAX)
	local rows = { { "Title", rr.title }, { "Score", rr.score }, { "Tips", rr.tips } }
	for i, spec in ipairs(rows) do
		local l = Instance.new("TextLabel")
		l.Name = spec[1]
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -2 * (Summary.BORDER + Summary.PAD), 0, spec[2].h) -- 8 px inside the carved border
		l.Position = UDim2.fromOffset(spec[2].x, spec[2].y)
		l.Font = Enum.Font[i == 1 and Style.FONTS.title or Style.FONTS.ui]
		l.TextSize = spec[2].size
		l.TextColor3 = i == 1 and Color3.fromRGB(255, 214, 130) or Color3.fromRGB(250, 238, 212)
		l.TextTransparency, l.TextStrokeTransparency = 0, 0.4
		l.TextStrokeColor3 = Color3.fromRGB(30, 20, 12)
		l.ZIndex = 13
		l.Parent = plate
		labels[spec[1]] = l
	end
	shopFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() place(shopFrame) end)
	place(shopFrame)
	paint()
end

return M
