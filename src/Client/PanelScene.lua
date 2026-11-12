--[[
	Client/PanelScene.lua
	The painted room under a panel (art `panel_scene`, Engine/PanelSceneLayout.lua): a dark holder with the cover-fitted picture and a soft
	vignette melting its uncovered edges into the holder colour, so the painting reads as the whole body of the panel. Used by the Legend, Card Sets and Stats panels.

	PanelScene.new(panel, { artKey, def, z }) -> scene
	scene.id           the recorded Image id or nil (nil: the caller keeps its plain layout)
	scene.show(areaRect, placed)   areaRect = { x, y, w, h } in the panel; placed = PanelSceneLayout.place result; draws picture and edges
	scene.hide()
]]

local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
local PanelSceneLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelSceneLayout"))

local PanelScene = {}
local FILL = Color3.fromRGB(26, 18, 12) -- the holder colour the vignette fades into

function PanelScene.new(panel, opts)
	local z = opts.z or 41
	local id = ContentArt.getImageId("panel_scene", opts.artKey)
	local scene = { id = id }
	local holder = Instance.new("Frame")
	holder.Name = "PanelScene"
	holder.BackgroundColor3 = FILL
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Visible = false
	holder.Active = false
	holder.ZIndex = z
	holder.Parent = panel
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
		for _, ch in ipairs(holder:GetChildren()) do
			if ch ~= picture then ch:Destroy() end
		end
		for _, it in ipairs(PanelSceneLayout.feather(placed, area.w, area.h)) do
			local f = Instance.new("Frame")
			f.Name = "Vignette_" .. it.name
			f.BackgroundColor3 = FILL
			f.BackgroundTransparency = it.transparency
			f.BorderSizePixel = 0
			f.Position, f.Size = UDim2.fromOffset(it.rect.x, it.rect.y), UDim2.fromOffset(it.rect.w, it.rect.h)
			f.Active = false
			f.ZIndex = z
			f.Parent = holder
		end
		holder.Visible = true
	end

	function scene.hide()
		holder.Visible = false
	end

	return scene
end

return PanelScene
