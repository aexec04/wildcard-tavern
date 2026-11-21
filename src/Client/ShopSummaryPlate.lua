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
local pending, shown, token = false, false, 0 -- pending: a cleared round not yet shown; shown: on screen now

local function picture() return plate and plate.Parent and plate.Parent:FindFirstChild("RoundSummaryPaint") end

local function setFade(a) -- 0 solid, 1 gone; both text transparencies move together
	if not plate then return end
	local pic = picture()
	if pic and pic:IsA("ImageLabel") then pic.ImageTransparency = a end
	if labels then
		for _, l in pairs(labels) do l.TextTransparency, l.TextStrokeTransparency = math.min(1, a), math.min(1, 0.4 + 0.6 * a) end
	end
	local x = plate:FindFirstChild("CloseX")
	if x then x.Visible = a < 0.5 end
end

local function paint()
	if not plate then return end
	local on = lines ~= nil and shown and Flags.gameplay() == 2
	plate.Visible = on
	if on and labels then
		labels.Title.Text, labels.Score.Text = lines.title, Summary.detail(lines)
	end
end

local function dismiss(fade)
	token = token + 1
	local my = token
	shown, pending = false, false
	local calm = false
	pcall(function() calm = require(script.Parent.ClientSettings).get("reduceShake") == true end)
	if not fade or calm or not plate then paint(); setFade(0); return end
	task.spawn(function()
		for i = 1, 8 do
			if token ~= my then return end
			setFade(i / 8)
			task.wait(0.04)
		end
		if token == my then paint(); setFade(0) end
	end)
end

local function reveal()
	if not pending or not plate then return end
	pending, shown = false, true
	token = token + 1
	local my = token
	setFade(0)
	paint()
	task.delay(Summary.SHOW_SECONDS, function()
		if token == my and shown then dismiss(true) end
	end)
end

local function place(shopFrame)
	local size = shopFrame.AbsoluteSize
	local r = Summary.rect(size.X, size.Y)
	plate.Position = UDim2.fromOffset(r.x, r.y)
	plate:SetAttribute("PaintW", r.w) -- slice by the layout size so all four corners stay on the plate (TavernKit.painted); set before Size, which refits
	plate:SetAttribute("PaintH", r.h)
	plate.Size = UDim2.fromOffset(r.w, r.h)
end

function M.remember(clear)
	lines = Summary.lines(clear)
	pending, shown = lines ~= nil, false
	token = token + 1
	paint()
	if plate and plate.Parent and plate.Parent.Visible then reveal() end
end

function M.attach(shopFrame)
	if not shopFrame or shopFrame:FindFirstChild("RoundSummary") then return end
	plate = Kit.plate(shopFrame, UDim2.fromOffset(Summary.WIDTH_MAX, Summary.HEIGHT))
	plate.Name = "RoundSummary"
	plate.Active = false
	plate.ZIndex = 12
	plate:SetAttribute("PaintW", Summary.WIDTH_MAX)
	plate:SetAttribute("PaintH", Summary.HEIGHT)
	pcall(function() Kit.painted(plate, "orn_target") end)
	labels = {}
	local rr = Summary.rows(Summary.WIDTH_MAX)
	local rows = { { "Title", rr.title }, { "Score", rr.score } }
	for i, spec in ipairs(rows) do
		local l = Instance.new("TextLabel")
		l.Name = spec[1]
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -2 * (Summary.BORDER + Summary.PAD), 0, spec[2].h)
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
	-- the small X: closes the plate at once and it does not come back until the next cleared round
	pcall(function()
		require(script.Parent.CloseX).attach(plate, function() dismiss(false) end, { inset = -10, top = -16, z = 20 })
	end)
	shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if shopFrame.Visible then reveal() end
	end)
	shopFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() place(shopFrame) end)
	place(shopFrame)
	paint()
	-- Studio report: where the plate and its picture really sit (a clipped or off screen picture shows here)
	task.delay(3, function()
		local pic = plate and plate.Parent and plate.Parent:FindFirstChild("RoundSummaryPaint")
		if not pic then return end
		local function d(o) return string.format("pos=%d,%d size=%d,%d clips=%s", o.AbsolutePosition.X, o.AbsolutePosition.Y, o.AbsoluteSize.X, o.AbsoluteSize.Y, tostring(o.ClipsDescendants)) end
		print("[SummaryPlate] plate " .. d(plate) .. " | picture " .. d(pic) .. " scale=" .. tostring(pic.ScaleType) .. " slice=" ..
			tostring(pic.SliceCenter) .. " sliceScale=" .. string.format("%.3f", pic.SliceScale) .. " | parent " .. d(pic.Parent))
	end)
end

return M
