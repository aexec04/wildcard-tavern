--[[
	Client/RoomWall.lua
	The shared backdrop of the full-panel scene pages (Card Sets, Legend, Stats, Flair): the painted Collection wall (`collection_room`,
	cover-cropped, never stretched) under ONE 16 keypoint scrim gradient frame and two faint lantern glows, so no page shows flat dark side
	voids. A code gradient stands in when the Image id is missing.

	RoomWall.fill(wall, z)   wall = an empty Frame (ClipsDescendants should be true); adds the picture, scrim and glows as its children
	RoomWall.COLOR           the average tone of the finished wall, used to melt picture edges into it
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local ScrimGradient = require(Engine:WaitForChild("ScrimGradient"))

local RoomWall = {}
RoomWall.COLOR = Color3.fromRGB(44, 30, 20)

function RoomWall.fill(wall, z)
	wall.BackgroundColor3 = Color3.fromRGB(58, 38, 24)
	local g = Instance.new("UIGradient") -- Color stops only
	g.Rotation = 90
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(78, 52, 32)), ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 26, 16)) })
	g.Parent = wall
	local id = ContentArt.getImageId("collection_scene", "collection_room")
	if id then
		g:Destroy()
		local pic = Instance.new("ImageLabel")
		pic.Name = "WallPicture"
		pic.BackgroundTransparency = 1
		pic.Image = id
		pic.ScaleType = Enum.ScaleType.Crop
		pic.Size = UDim2.fromScale(1, 1)
		pic.Active = false
		pic.ZIndex = z
		pic.Parent = wall
	end
	local scrim = Instance.new("Frame") -- darker towards the bottom so content stays readable, low contrast and calm
	scrim.Name = "WallScrim"
	scrim.BackgroundColor3 = Color3.fromRGB(14, 8, 4)
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Active = false
	scrim.ZIndex = z
	scrim.Parent = wall
	local sg = Instance.new("UIGradient")
	sg.Rotation = 90
	local keys = {}
	for _, k in ipairs(ScrimGradient.keypoints(16, 1, 1)) do keys[#keys + 1] = NumberSequenceKeypoint.new(k[1], 0.66 - 0.3 * k[1]) end -- 34 percent dark at the top, 64 at the bottom
	sg.Transparency = NumberSequence.new(keys)
	sg.Parent = scrim
	local glow = Instance.new("Frame") -- faint warm light from the side lanterns
	glow.Name = "LanternGlowL"
	glow.BackgroundColor3 = Color3.fromRGB(255, 190, 110)
	glow.BorderSizePixel = 0
	glow.Size = UDim2.fromScale(0.16, 1)
	glow.Active = false
	glow.ZIndex = z
	glow.Parent = wall
	local gg = Instance.new("UIGradient")
	local gk = {}
	for _, k in ipairs(ScrimGradient.keypoints(12, 1, 1)) do gk[#gk + 1] = NumberSequenceKeypoint.new(k[1], 1 - 0.14 * (1 - k[1])) end
	gg.Transparency = NumberSequence.new(gk)
	gg.Parent = glow
	local glowR = glow:Clone()
	glowR.Name = "LanternGlowR"
	glowR.Position = UDim2.fromScale(0.84, 0)
	glowR.UIGradient.Rotation = 180
	glowR.Parent = wall
end

return RoomWall
