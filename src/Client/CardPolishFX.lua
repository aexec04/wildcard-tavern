--[[
	Client/CardPolishFX.lua
	The deck stack's thickness edge: up to four thin dark purple lines under the deck book that disappear as cards are drawn
	(steps from Engine/CardPolish.deckSteps). Static frames, no tween, so Calm mode and Reduce motion are the same.
	Hand card shadows and tilt live in PlayRailLip and PlayMotion and use the same Engine/CardPolish rules.

	CardPolishFX.deckEdge(layer) -> { place(rect), set(remaining, total) }
	    rect = { x, y, w, h } of the deck picture in pixels; the lines sit under its lower edge, behind the picture.
]]
local CardPolish = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CardPolish"))

local M = {}

M.BOTTOM = 0.86 -- the book's bottom edge as a share of its picture height (the cut has a margin under it)
M.INSET = 0.14 -- each side, share of the picture width
M.LINE_H = 3

function M.deckEdge(layer)
	local lines = {}
	for i = 1, CardPolish.DECK_STEPS do
		local f = Instance.new("Frame")
		f.Name = "DeckEdge" .. i
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 1 -- under the deck picture (ZIndex 2)
		f.BackgroundColor3 = Color3.fromRGB(58, 34, 92)
		f.Visible = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 2)
		c.Parent = f
		f.Parent = layer
		lines[i] = f
	end
	local rect, steps = nil, CardPolish.DECK_STEPS
	local function lay()
		local edge = CardPolish.deckEdge(steps)
		for i, f in ipairs(lines) do
			local e = edge[i]
			if e and rect then
				f.Visible = true
				f.Position = UDim2.fromOffset(math.floor(rect.x + rect.w * M.INSET), math.floor(rect.y + rect.h * M.BOTTOM) + e.dy)
				f.Size = UDim2.fromOffset(math.floor(rect.w * (1 - 2 * M.INSET)), M.LINE_H)
				f.BackgroundColor3 = Color3.fromRGB(math.floor(120 * e.shade), math.floor(70 * e.shade), math.floor(190 * e.shade))
			else
				f.Visible = false
			end
		end
	end
	return {
		place = function(r) rect = r; lay() end,
		set = function(remaining, total)
			local n = CardPolish.deckSteps(remaining, total)
			if n ~= steps then steps = n; lay() end
		end,
	}
end

return M
