--[[
	Client/PatronSeatStrip.lua
	The seat order strip under the My Patrons cards: one group per Patron, "<" button, "<n> of <total>" and the name, ">" button,
	every button at least 44 px (TavernKit brown plates, ASCII arrows so no glyph can show as a box). A button at either end is
	dimmed and does nothing. Static: no tween, so Calm mode and Reduce motion are the same. Numbers and words come from
	Engine/PatronSeats (tested); the server move is RunState.movePatron through the MovePatron remote.

	PatronSeatStrip.build(parent, layoutOrder, owned, zoneW, onMove) -> the strip frame
	    owned = array of { id, name }; onMove(patronId, dir) is called with dir -1 or 1
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Seats = require(Engine:WaitForChild("PatronSeats"))
local Kit = require(script.Parent.TavernKit)

local M = {}

local CREAM = Color3.fromRGB(250, 240, 220)
local OUTLINE = Color3.fromRGB(26, 17, 10)

function M.build(parent, layoutOrder, owned, zoneW, onMove)
	local n = #owned
	local size = Seats.stripSize(zoneW, math.max(1, n))
	local strip = Instance.new("Frame")
	strip.Name = "PatronSeatStrip"
	strip.LayoutOrder = layoutOrder
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(1, 0, 0, size.h + 8)
	strip.Parent = parent
	if n < 2 then return strip end -- nothing to reorder with one Patron or none
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Seats.GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = strip
	for i, p in ipairs(owned) do
		local group = Instance.new("Frame")
		group.Name = "Seat" .. i
		group.LayoutOrder = i
		group.BackgroundTransparency = 1
		group.Size = UDim2.fromOffset(size.groupW, size.h)
		group.Parent = strip
		local function arrow(dir, text, x)
			local b = Instance.new("TextButton")
			b.Name = dir < 0 and "MoveLeft" or "MoveRight"
			b.Size = UDim2.fromOffset(size.btn, size.h)
			b.Position = UDim2.fromOffset(x, 0)
			Kit.skin(b, text, "secondary")
			b.TextSize = 20
			b.Parent = group
			if Seats.canMove(i, n, dir) then
				b.MouseButton1Click:Connect(function() onMove(p.id, dir) end)
			else
				b.Active = false
				b.TextTransparency = 0.55 -- the end of the row: no seat to swap with
				b.TextStrokeTransparency = 0.7
			end
			return b
		end
		arrow(-1, "<", 0)
		arrow(1, ">", size.groupW - size.btn)
		local label = Instance.new("TextLabel")
		label.Name = "Order"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(size.btn + 2, 0)
		label.Size = UDim2.fromOffset(size.groupW - size.btn * 2 - 4, size.h)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextColor3 = CREAM
		label.TextTransparency = 0
		label.TextStrokeColor3 = OUTLINE
		label.TextStrokeTransparency = 0.2
		label.TextWrapped = true
		label.Text = Seats.orderText(i, n) .. "\n" .. tostring(p.name or "")
		label.Parent = group
	end
	return strip
end

return M
