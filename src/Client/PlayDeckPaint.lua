--[[
	Client/PlayDeckPaint.lua
	Step D2 of the painted play screen: the deck sits INSIDE the painted recess of play_table_front_b. The widget takes the recess
	rect (PlayTableLayout map.deck), the card back is a portrait card at 90 percent of the recess height in its left part, and the
	count ("44/52", 20 px) sits on a small wooden board cut from play_plates_b in its right part. The click catcher still covers the
	whole widget, the pile lift on hover follows the new rest position (attribute PaintedRest, read by Client/DeckWidget), and the draw
	and shuffle animations read the widget's own position, so they start from the recess. play_deck_box_b is not used.

	PlayDeckPaint.rects(rw, rh)   pure: card and count rects inside a recess of rw x rh (tested)
	PlayDeckPaint.apply(widget, deckRect, platesId)   deckRect from PlayTableLayout.map; nil puts the old widget back
	No recess, no widget or any error leaves the old deck widget exactly as it was.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayTableLayout = require(Engine:WaitForChild("PlayTableLayout"))
local ImageSpace = require(Engine:WaitForChild("ImageSpace"))

local PlayDeckPaint = {}

local KEEP = { ClickCatcher = true, DeckCardBack = true, DeckCount = true, StackBackA = true, StackBackB = true, StackBackC = true, PileGlow = true }

-- gold corner brackets, studs and the inner rim that the skin and the ornate-frame pass put on the widget and on the card back;
-- the skin shows them again whenever it restyles, so a hidden one is hidden again as soon as something turns it back on
local DECOR = { HudBrackets = true, InnerRim = true, BracketH = true, BracketV = true, CornerStud = true, Brackets = true }

local function hideDecor(widget, parent)
	for _, c in ipairs(parent:GetChildren()) do
		if DECOR[c.Name] and c:IsA("GuiObject") then
			c:SetAttribute("PaintedHidden", true)
			c.Visible = false
			if not c:GetAttribute("DecorHooked") then
				c:SetAttribute("DecorHooked", true)
				c:GetPropertyChangedSignal("Visible"):Connect(function()
					if widget:GetAttribute("DeckPainted") and c.Visible then c.Visible = false end
				end)
			end
		end
	end
end

local function paint(widget, deckRect, platesId)
	local card = widget:FindFirstChild("DeckCardBack")
	local count = widget:FindFirstChild("DeckCount")
	if not (card and count) then return false end
	local rects = PlayTableLayout.deckRects(deckRect.w, deckRect.h)
	if widget:GetAttribute("PaintedOrig") == nil then
		widget:SetAttribute("PaintedOrig", true)
		widget:SetAttribute("OrigPos", widget.Position)
		widget:SetAttribute("OrigSize", widget.Size)
		widget:SetAttribute("OrigAnchor", widget.AnchorPoint)
		widget:SetAttribute("OrigBgT", widget.BackgroundTransparency)
	end
	widget:SetAttribute("DeckPainted", true)
	widget.AnchorPoint = Vector2.new(1, 1)
	widget.Size = UDim2.fromOffset(deckRect.w, deckRect.h)
	local rest = UDim2.fromOffset(deckRect.x + deckRect.w, deckRect.y + deckRect.h)
	widget:SetAttribute("PaintedRest", rest)
	widget.Position = rest
	widget.BackgroundTransparency = 1
	widget.Rotation = 0

	local function chrome()
		for _, c in ipairs(widget:GetChildren()) do
			if c:IsA("UIStroke") or c:IsA("UIGradient") then
				c.Enabled = false
			elseif c:IsA("GuiObject") and not KEEP[c.Name] then
				c:SetAttribute("PaintedHidden", true)
				c.Visible = false
			end
		end
	end
	chrome()
	local function place()
		if not widget:GetAttribute("DeckPainted") then return end
		card.AnchorPoint = Vector2.new(0, 0.5)
		card.Position = UDim2.fromOffset(rects.card.x, rects.card.y + rects.card.h / 2)
		card.Size = UDim2.fromOffset(rects.card.w, rects.card.h)
		card.BackgroundTransparency = 1
		count.AnchorPoint = Vector2.new(0, 0)
		count.Position = UDim2.fromOffset(rects.count.x, rects.count.y)
		count.Size = UDim2.fromOffset(rects.count.w, rects.count.h)
		count.TextSize = 20
		count.BackgroundTransparency = 1
		count.TextTransparency = 0
	end
	-- the white corner brackets (HudBrackets on the card back) frame the whole widget: hidden while painted
	local function brackets()
		hideDecor(widget, card)
		hideDecor(widget, widget)
	end
	brackets()
	place()
	if not widget:GetAttribute("DeckHooked") then
		widget:SetAttribute("DeckHooked", true)
		-- the widget's own async holder-art callback and the per-set restyle write these again: put the painted values back
		for _, prop in ipairs({ "Position", "Size", "AnchorPoint" }) do
			card:GetPropertyChangedSignal(prop):Connect(function()
				if widget:GetAttribute("DeckPainted") then
					-- the holder-art callback writes a scale size and a top anchor: any difference puts the painted numbers back
					if card.Size ~= UDim2.fromOffset(rects.card.w, rects.card.h) or card.AnchorPoint ~= Vector2.new(0, 0.5)
						or card.Position ~= UDim2.fromOffset(rects.card.x, rects.card.y + rects.card.h / 2) then place() end
				end
			end)
		end
		card.ChildAdded:Connect(function() if widget:GetAttribute("DeckPainted") then brackets() end end)
		for _, prop in ipairs({ "Position", "Size", "BackgroundTransparency" }) do
			count:GetPropertyChangedSignal(prop):Connect(function()
				if widget:GetAttribute("DeckPainted") and (count.BackgroundTransparency ~= 1 or count.Size ~= UDim2.fromOffset(rects.count.w, rects.count.h)) then place() end
			end)
		end
		widget.ChildAdded:Connect(function(c)
			if widget:GetAttribute("DeckPainted") and c:IsA("GuiObject") and not KEEP[c.Name] then
				c:SetAttribute("PaintedHidden", true)
				c.Visible = false
			end
			if widget:GetAttribute("DeckPainted") then brackets() end
		end)
	end

	-- wooden board under the count: the lower 70 percent of the Play Hand sign, so the top rod is not drawn
	local board = count:FindFirstChild("CountBoard")
	if not board then
		board = Instance.new("ImageLabel")
		board.Name = "CountBoard"
		board.BackgroundTransparency = 1
		board.BorderSizePixel = 0
		board.Active = false
		board.ScaleType = Enum.ScaleType.Stretch
		board.ZIndex = math.max(1, count.ZIndex - 1)
		board.Size = UDim2.fromScale(1, 1)
		board.Parent = count
	end
	local b = PlayTableLayout.PLATE_BOXES.play
	if type(platesId) == "string" and platesId ~= "" then
		board.Image = platesId
		local x, y, w, h = ImageSpace.rect(b.x, b.y + math.floor(b.h * 0.3 + 0.5), b.w, math.floor(b.h * 0.7 + 0.5), PlayTableLayout.PLATES_IMG_W, PlayTableLayout.PLATES_IMG_H)
		board.ImageRectOffset = Vector2.new(x, y)
		board.ImageRectSize = Vector2.new(w, h)
		board.Visible = true
	else
		board.Visible = false
	end
	count.TextColor3 = Color3.fromRGB(250, 240, 220)
	return true
end

local function restore(widget)
	if not widget:GetAttribute("DeckPainted") then return end
	widget:SetAttribute("DeckPainted", nil)
	widget:SetAttribute("PaintedRest", nil)
	if widget:GetAttribute("OrigPos") then widget.Position = widget:GetAttribute("OrigPos") end
	if widget:GetAttribute("OrigSize") then widget.Size = widget:GetAttribute("OrigSize") end
	if widget:GetAttribute("OrigAnchor") then widget.AnchorPoint = widget:GetAttribute("OrigAnchor") end
	if widget:GetAttribute("OrigBgT") then widget.BackgroundTransparency = widget:GetAttribute("OrigBgT") end
	for _, c in ipairs(widget:GetChildren()) do
		if c:IsA("UIStroke") or c:IsA("UIGradient") then c.Enabled = true end
		if c:IsA("GuiObject") and c:GetAttribute("PaintedHidden") then
			c:SetAttribute("PaintedHidden", nil)
			c.Visible = true
		end
	end
	local count = widget:FindFirstChild("DeckCount")
	local card = widget:FindFirstChild("DeckCardBack")
	if count then
		local board = count:FindFirstChild("CountBoard")
		if board then board:Destroy() end
		count.AnchorPoint, count.Position, count.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 158), UDim2.new(0, 72, 0, 24)
		count.TextSize = 18
		count.BackgroundTransparency = 0
	end
	if card then
		for _, hb in ipairs(card:GetChildren()) do
			if hb:IsA("GuiObject") and hb:GetAttribute("PaintedHidden") then
				hb:SetAttribute("PaintedHidden", nil)
				hb.Visible = true
			end
		end
		card.AnchorPoint, card.Position, card.Size = Vector2.new(0, 0), UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0, 140)
	end
end

PlayDeckPaint.rects = function(rw, rh)
	return PlayTableLayout.deckRects(rw, rh)
end

function PlayDeckPaint.apply(widget, deckRect, platesId)
	if not widget then return false end
	if deckRect and deckRect.w > 0 then
		local ok, res = pcall(paint, widget, deckRect, platesId)
		if ok and res then return true end
		pcall(restore, widget)
		return false
	end
	pcall(restore, widget)
	return false
end

return PlayDeckPaint
