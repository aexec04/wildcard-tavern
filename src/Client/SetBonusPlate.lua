--[[
	Client/SetBonusPlate.lua
	On the My Patrons tab: one small TavernKit style plate per Patron set bonus the owned Patrons form (Engine/SetBonuses),
	a gold line with the set name and its reward, plus the members' names. Nothing is shown with no set formed. Static: no tween,
	so Calm mode and Reduce motion are the same. Display only; Scoring applies the bonus on the server side.

	SetBonusPlate.build(parent, layoutOrder, owned) -> the frame (height 0 when nothing is formed)
	    owned = array of { id, name } in seat order
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local SetBonuses = require(Engine:WaitForChild("SetBonuses"))
local Style = require(Engine:WaitForChild("TavernStyle"))

local M = {}

local function rgb(name)
	local c = Style.COLORS[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

function M.build(parent, layoutOrder, owned)
	local ids = {}
	for i, p in ipairs(owned or {}) do ids[i] = p.id end
	local sets = SetBonuses.formed(ids)
	local wrap = Instance.new("Frame")
	wrap.Name = "SetBonusPlates"
	wrap.LayoutOrder = layoutOrder
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, #sets * (Style.SIZES.minTouch + 4))
	wrap.Parent = parent
	for i, set in ipairs(sets) do
		local names = {}
		for _, seat in ipairs(set.members) do names[#names + 1] = tostring(owned[seat].name or owned[seat].id) end
		local plate = Instance.new("Frame")
		plate.Name = "SetPlate_" .. set.id
		plate.Position = UDim2.fromOffset(0, (i - 1) * (Style.SIZES.minTouch + 4))
		plate.Size = UDim2.new(1, 0, 0, Style.SIZES.minTouch)
		plate.BackgroundColor3 = rgb("plateFill")
		plate.BorderSizePixel = 0
		plate.Parent = wrap
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Style.RADIUS.panel)
		corner.Parent = plate
		local stroke = Instance.new("UIStroke")
		stroke.Color = rgb("goldTrim")
		stroke.Thickness = Style.STROKE.plate
		stroke.Parent = plate
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromOffset(10, 0)
		text.Size = UDim2.new(1, -20, 1, 0)
		text.Font = Enum.Font.GothamBold
		text.TextSize = 15
		text.TextWrapped = true
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextColor3 = rgb("goldBright")
		text.TextTransparency = 0
		text.TextStrokeTransparency = 0.4
		text.Text = SetBonuses.lineOf(set) .. "  (" .. table.concat(names, ", ") .. ")"
		text.Parent = plate
		pcall(function() -- the equipped Card Set's plate, edge and ink (7:1); classic keeps the gold on dark look
			require(script.Parent.PopupSkin).dark(plate, stroke, { { text, rgb("goldBright") } }, { plate = rgb("plateFill"), edge = rgb("goldTrim") })
		end)
	end
	return wrap
end

return M
