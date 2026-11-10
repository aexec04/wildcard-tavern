--[[
	Client/CollectionWall.lua
	Collection Gallery back layer: the painted back-room wall (panelled wood, two lanterns, floor edge) filling the
	Collection panel, a soft edge vignette and a calm dark scrim over the tile grid so it stays readable.
	Look only and static (no loops or tweens, so calm mode needs nothing). Mounts only when collection_scene
	collection_wall has an Image id, so the Collection looks exactly as before until the art is recorded.
	Geometry comes from Engine/CollectionSceneLayout.lua.

	CollectionWall.mount(panel) -> ImageLabel or nil
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local Layout = require(Engine:WaitForChild("CollectionSceneLayout"))

local CollectionWall = {}

function CollectionWall.mount(panel)
	local id = ContentArt.getImageId("collection_scene", "collection_wall")
	if not id then
		return nil
	end
	local wall = Instance.new("ImageLabel")
	wall.Name = "CollectionWall"
	wall.Size = UDim2.fromScale(1, 1)
	wall.BackgroundTransparency = 1
	wall.BorderSizePixel = 0
	wall.Image = id
	wall.ScaleType = Enum.ScaleType.Crop
	wall.Active = false
	wall.ZIndex = panel.ZIndex
	wall.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = wall

	-- calm dark scrim over the grid area so tiles and text read on the painted wall
	local scrim = Instance.new("Frame")
	scrim.Name = "CollectionWallScrim"
	scrim.BackgroundColor3 = Color3.fromRGB(14, 8, 4)
	scrim.BackgroundTransparency = 0.45
	scrim.BorderSizePixel = 0
	scrim.Active = false
	scrim.ZIndex = panel.ZIndex
	scrim.Parent = wall
	local function relayout()
		local size = panel.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local c = Layout.content(size.X, size.Y)
		scrim.Position = UDim2.fromOffset(c.x, c.y)
		scrim.Size = UDim2.fromOffset(c.w, c.h)
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	relayout()
	return wall
end

return CollectionWall
