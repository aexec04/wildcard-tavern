--[[
	Client/DeckWidgetSkin.lua
	Per-set look for the draw pile (Client/DeckWidget): corner brackets in the set accent around the top card back, a themed
	count plate, and three card backs fanned behind the pile with a tilt and offset that is different for every Card Set
	(Engine/HudStyle.pileLook). Follows HudTheme.setSkin, so it changes live on equip and Preview.

	DeckWidgetSkin.install{ widget, cardBack, stackCards, count, syncStack }   once, from DeckWidget.lua
	  stackCards   array of { frame, dx, dy } (the cards behind the top card); a third is added here
	  syncStack    re-lays the stack from the top card's position

	Art hook: the top card back already shows the equipped Card Back art; per-set frame art can be added beside the brackets.
	The brackets are children of the card back, the count plate styling sits on the count label itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudStyle"))
local HudTheme = require(script.Parent.HudTheme)

local DeckWidgetSkin = {}

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local LEN, THICK, OUT = 14, 3, 3

local function makeBrackets(cardBack)
	local holder = Instance.new("Frame")
	holder.Name = "HudBrackets"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.new(1, OUT * 2, 1, OUT * 2)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ZIndex = 6
	holder.Parent = cardBack
	local bars = {}
	-- x,y anchor (0 or 1) and the bar's size: one horizontal and one vertical bar per corner
	for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		for _, horizontal in ipairs({ true, false }) do
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(c[1], c[2])
			bar.Position = UDim2.fromScale(c[1], c[2])
			bar.Size = horizontal and UDim2.fromOffset(LEN, THICK) or UDim2.fromOffset(THICK, LEN)
			bar.BorderSizePixel = 0
			bar.Active = false
			bar.ZIndex = 6
			bar.Parent = holder
			table.insert(bars, bar)
		end
	end
	return holder, bars
end

function DeckWidgetSkin.install(deps)
	local widget, cardBack, count = deps.widget, deps.cardBack, deps.count
	local stackCards = deps.stackCards

	-- third card behind the pile (cloned from the first so it wears the same corner and edge)
	local first = stackCards[1]
	if first and #stackCards < 3 then
		local c = first.frame:Clone()
		c.Name = "StackBackC"
		c.Parent = widget
		stackCards[3] = { frame = c, dx = 0, dy = 6 }
	end
	-- two more layers (shown only in the painted recess, DeckWidget.syncStack): the pile reads as 4 to 5 cards thick
	if first and #stackCards == 3 then
		for i, name in ipairs({ "StackBackD", "StackBackE" }) do
			local c = first.frame:Clone()
			c.Name = name
			c.Parent = widget
			stackCards[3 + i] = { frame = c, dx = 0, dy = 6 + 2 * i }
		end
	end
	-- two more layers (shown only in the painted recess, DeckWidget.syncStack) so the pile reads as 4 to 5 cards thick
	if first and #stackCards == 3 then
		for i, name in ipairs({ "StackBackD", "StackBackE" }) do
			local c = first.frame:Clone()
			c.Name = name
			c.Parent = widget
			stackCards[3 + i] = { frame = c, dx = 0, dy = 6 + 2 * i }
		end
	end

	local _, bars = makeBrackets(cardBack)
	local plateRing = Instance.new("UIStroke")
	plateRing.Name = "PlateRing"
	plateRing.Thickness = 2
	plateRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	plateRing.Parent = count

	local function restyle(skin)
		skin = skin or HudTheme.skin()
		local p = HudStyle.deckPalette(skin.colors)
		for _, bar in ipairs(bars) do bar.BackgroundColor3 = c3(p.bracket) end
		count.BackgroundColor3 = c3(p.plate)
		count.BackgroundTransparency = 0 -- solid so the count reads on any card back
		count.TextColor3 = c3(p.text)
		count.TextTransparency = 0
		count.TextStrokeTransparency = 1
		plateRing.Color = c3(p.plateRing)
		local look = HudStyle.pileLook(skin.id)
		for i, card in ipairs(stackCards) do
			local l = look[i]
			if l then
				card.dx, card.dy = l.dx, l.dy
				card.frame.Rotation = l.rot
			end
		end
		if deps.syncStack then deps.syncStack() end
	end
	HudTheme.onSkin(restyle)
	restyle(HudTheme.skin())
end

return DeckWidgetSkin
