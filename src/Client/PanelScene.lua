--[[
	Client/PanelScene.lua
	The painted room under a panel (art `panel_scene`, Engine/PanelSceneLayout.lua): a holder with the 4 px edge slices under the
	cover-fitted picture, so the painting reads as the whole body of the panel. Used by the Legend, Card Sets and Stats panels.

	PanelScene.new(panel, { artKey, def, z }) -> scene
	scene.id           the recorded Image id or nil (nil: the caller keeps its plain layout)
	scene.show(areaRect, placed)   areaRect = { x, y, w, h } in the panel; placed = PanelSceneLayout.place result; draws picture and edges
	scene.hide()
]]

local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
local PanelSceneLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelSceneLayout"))

local PanelScene = {}

function PanelScene.new(panel, opts)
	local z = opts.z or 41
	local id = ContentArt.getImageId("panel_scene", opts.artKey)
	local scene = { id = id }
	local holder = Instance.new("Frame")
	holder.Name = "PanelScene"
	holder.BackgroundColor3 = Color3.fromRGB(26, 18, 12)
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Visible = false
	holder.Active = false
	holder.ZIndex = z
	holder.Parent = panel
	local edges = Instance.new("Frame")
	edges.Name = "Edges"
	edges.BackgroundTransparency = 1
	edges.Size = UDim2.fromScale(1, 1)
	edges.Active = false
	edges.ZIndex = z
	edges.Parent = holder
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.Image = id or ""
	picture.ScaleType = Enum.ScaleType.Stretch
	picture.Active = false
	picture.ZIndex = z
	picture.Parent = holder

	function scene.show(area, placed)
		holder.Position, holder.Size = UDim2.fromOffset(area.x, area.y), UDim2.fromOffset(area.w, area.h)
		picture.Position, picture.Size = UDim2.fromOffset(placed.image.x, placed.image.y), UDim2.fromOffset(placed.image.w, placed.image.h)
		for _, ch in ipairs(edges:GetChildren()) do ch:Destroy() end
		for _, it in ipairs(PanelSceneLayout.edgeFill(opts.def, placed, area.w, area.h)) do
			local f = Instance.new("ImageLabel")
			f.Name = it.name
			f.BackgroundTransparency = 1
			f.Image = id or ""
			f.ScaleType = Enum.ScaleType.Stretch
			f.ImageRectOffset = Vector2.new(it.src.x, it.src.y)
			f.ImageRectSize = Vector2.new(it.src.w, it.src.h)
			f.Position, f.Size = UDim2.fromOffset(it.rect.x, it.rect.y), UDim2.fromOffset(it.rect.w, it.rect.h)
			f.Active = false
			f.ZIndex = z
			f.Parent = edges
		end
		holder.Visible = true
	end

	function scene.hide()
		holder.Visible = false
	end

	return scene
end

return PanelScene
