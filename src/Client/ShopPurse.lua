--[[
	Client/ShopPurse.lua
	The Counter hides the round sidebar, so the player's Tips stay visible on the same painted Tips plate and bulb as the table
	(TavernKit pill, `wh_target` picture, `bulb` icon) in the top right corner of the Shop. One call per rebuild:
	ShopPurse.update(shopFrame, tips). A missing picture keeps the kit pill (wood fill, gold trim).
]]

local ShopPurse = {}

local NAME = "PursePlate"

function ShopPurse.update(shopFrame, tips)
	local plate = shopFrame:FindFirstChild(NAME)
	if not plate then
		local Kit = require(script.Parent.TavernKit)
		plate = Kit.pill(shopFrame, "", "wood")
		plate.Name = NAME
		plate.AnchorPoint = Vector2.new(1, 0)
		plate.Size = UDim2.fromOffset(170, 44)
		plate.Position = UDim2.new(1, -16, 0, 6)
		plate.ZIndex = 12
		local word = plate:FindFirstChild("Word")
		if word then word.TextSize = 20; word.ZIndex = 14 end
		pcall(function()
			Kit.painted(plate, "wh_target")
			local bulb = Kit.icon(plate, "bulb")
			if bulb and word and not word:FindFirstChild("KitIconPad") then
				local up = Instance.new("UIPadding"); up.Name = "KitIconPad"; up.PaddingLeft = UDim.new(0.18, 0); up.Parent = word
			end
		end)
	end
	local word = plate:FindFirstChild("Word")
	if word then word.Text = string.format("Tips  %d", math.floor(tips or 0)) end
	return plate
end

return ShopPurse
