--[[
	Client/PlayFloorShade.lua
	The soft dark floor shadow under the hand in a per-Card-Set room (Engine/PlayTableLayout FLOOR): the room's own painting shows behind the
	hand, the deck and the action row, and this 55 percent black shadow over the bottom 35 percent of the screen (fading up) keeps the cards
	and plates readable. Stacked solid bands, colour only. Hidden for the classic table, which has its own painted wood.

	PlayFloorShade.install(root) -> { holder, setVisible(bool) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayTableLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayTableLayout"))

local PlayFloorShade = {}

function PlayFloorShade.install(root)
	local holder = Instance.new("Frame")
	holder.Name = "PlayFloorShade"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 0
	holder.Visible = false
	holder.Parent = root
	for k, band in ipairs(PlayTableLayout.floorBands()) do
		local f = Instance.new("Frame")
		f.Name = "Band" .. k
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.fromScale(0, 1)
		f.Size = UDim2.fromScale(1, band.height)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = band.transparency
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 0
		f.Parent = holder
	end
	return { holder = holder, setVisible = function(v) holder.Visible = v == true end }
end

return PlayFloorShade
