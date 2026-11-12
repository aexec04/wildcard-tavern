--[[
	Client/ShopPurse.lua
	The Counter hides the round sidebar, so the player's Tips stay visible on a small dark plate
	in the top right corner of the Shop. One call per rebuild: ShopPurse.update(shopFrame, tips).
]]

local ShopPurse = {}

local NAME = "PursePlate"

function ShopPurse.update(shopFrame, tips)
	local plate = shopFrame:FindFirstChild(NAME)
	if not plate then
		plate = Instance.new("TextLabel")
		plate.Name = NAME
		plate.AnchorPoint = Vector2.new(1, 0)
		plate.Size = UDim2.fromOffset(150, 36)
		plate.Position = UDim2.new(1, -16, 0, 6)
		plate.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
		plate.BackgroundTransparency = 0
		plate.BorderSizePixel = 0
		plate.Font = Enum.Font.GothamBold
		plate.TextSize = 20
		plate.TextColor3 = Color3.fromRGB(250, 235, 200)
		plate.TextTransparency = 0
		plate.TextStrokeTransparency = 1
		plate.ZIndex = 12
		plate.Parent = shopFrame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = plate
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.fromRGB(200, 160, 80)
		stroke.Thickness = 2
		stroke.Parent = plate
	end
	plate.Text = string.format("Tips  %d", math.floor(tips or 0))
	return plate
end

return ShopPurse
