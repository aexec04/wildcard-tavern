--[[
	Client/PatronParchmentCard.lua
	Gameplay v2 Patron seat as a cream parchment card (numbers in Engine/PatronParchment): paper backing with a gold edge, the cut
	card's portrait window cropped by ImageRect (the baked wood frame and name plate are not shown), a cream ribbon with the name
	in code text. The tier ring, corner letter and power disc come from PatronTierFX / ConceptTPatronCard on top. Static, no tweens.

	sync(c, name)   c is the PatronRow card record (c.body holds PatronArt); a card without a crop keeps the whole cut card
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local P = require(Engine:WaitForChild("PatronParchment"))
local NameFit = require(Engine:WaitForChild("PatronNameFit"))

local M = {}

local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local function corner(f, r)
	local u = Instance.new("UICorner")
	u.CornerRadius = UDim.new(0, r)
	u.Parent = f
end

local function make(class, name, parent, z)
	local f = Instance.new(class)
	f.Name = name
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	return f
end

function M.sync(c, name)
	if not c or not c.body then return end
	local art = c.body:FindFirstChild("PatronArt")
	local rect = c.id and P.storedRect(c.id) -- stored texture pixels, not the 1536 px source
	local paper, ribbon = c.body:FindFirstChild("ParchmentPaper"), c.body:FindFirstChild("ParchmentRibbon")
	if not art or not rect then
		if paper then paper.Visible = false end
		if ribbon then ribbon.Visible = false end
		return
	end
	local L = P.layout()
	local z = art.ZIndex
	if not paper then
		paper = make("Frame", "ParchmentPaper", c.body, z - 1)
		paper.Size = UDim2.fromScale(1, 1)
		paper.BackgroundColor3 = c3(P.PAPER)
		corner(paper, 8)
		local s = Instance.new("UIStroke")
		s.Color = c3(P.EDGE)
		s.Thickness = 2
		s.Parent = paper
	end
	paper.Visible = true
	art.ScaleType = Enum.ScaleType.Crop
	art.ImageRectOffset = Vector2.new(rect.x, rect.y)
	art.ImageRectSize = Vector2.new(rect.w, rect.h)
	art.Position = UDim2.fromScale(L.portrait.x, L.portrait.y)
	art.Size = UDim2.fromScale(L.portrait.w, L.portrait.h)
	art.AnchorPoint = Vector2.new(0, 0)
	if not ribbon then
		ribbon = make("Frame", "ParchmentRibbon", c.body, z + 2)
		ribbon.BackgroundColor3 = c3(P.RIBBON)
		corner(ribbon, 4)
		local s = Instance.new("UIStroke")
		s.Color = c3(P.EDGE)
		s.Thickness = 1.5
		s.Parent = ribbon
		local t = make("TextLabel", "Name", ribbon, z + 3)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Merriweather
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextScaled = true
		t.TextSize = 15
		t.TextColor3 = c3(P.INK)
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.TextTruncate = Enum.TextTruncate.AtEnd
		local cons = Instance.new("UITextSizeConstraint")
		cons.MinTextSize, cons.MaxTextSize = NameFit.MIN_SIZE, NameFit.MAX_SIZE
		cons.Parent = t
	end
	ribbon.Visible = true
	ribbon.Position = UDim2.fromScale(L.ribbon.x, L.ribbon.y)
	ribbon.Size = UDim2.fromScale(L.ribbon.w, L.ribbon.h)
	local t = ribbon:FindFirstChild("Name")
	if t then
		local w = c.slot and c.slot.AbsoluteSize.X or 96
		local nr = P.nameRect(w)
		t.Position = UDim2.new(0, nr.x + 2, 0, 0)
		t.Size = UDim2.new(0, math.max(0, nr.w - 4), 1, 0)
		t.Text = tostring(name or "")
	end
end

return M
