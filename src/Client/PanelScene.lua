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
local WASH = 0.3 -- transparency of the dark wash over the backdrop copy of the painting

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
		-- Where the picture does not reach the area (it keeps every slot inside, so it can sit smaller than cover), the same painting is laid
		-- cover-fitted behind it under a dark wash, so the bands read as the room continuing, not as flat brown. The feather strips start at
		-- the wash's own transparency so there is no seam.
		local I = placed.image
		local gap = I.x > 0.5 or I.y > 0.5 or I.x + I.w < area.w - 0.5 or I.y + I.h < area.h - 0.5
		local base = 0
		if gap and id and placed.scale and placed.scale > 0 then
			base = WASH
			local srcW, srcH = I.w / placed.scale, I.h / placed.scale
			local cs = math.max(area.w / srcW, area.h / srcH)
			local back = Instance.new("ImageLabel")
			back.Name = "Backdrop"
			back.BackgroundTransparency = 1
			back.Image = id
			back.ScaleType = Enum.ScaleType.Stretch
			back.Active = false
			back.ZIndex = z
			back.Size = UDim2.fromOffset(math.ceil(srcW * cs), math.ceil(srcH * cs))
			back.Position = UDim2.fromOffset(math.floor((area.w - srcW * cs) / 2), math.floor((area.h - srcH * cs) / 2))
			back.Parent = holder
			local wash = Instance.new("Frame")
			wash.Name = "BackdropWash"
			wash.BackgroundColor3 = FILL
			wash.BackgroundTransparency = WASH
			wash.BorderSizePixel = 0
			wash.Size = UDim2.fromOffset(area.w, area.h)
			wash.Active = false
			wash.ZIndex = z
			wash.Parent = holder
			picture.Parent = nil -- equal ZIndex draws in sibling order: move the painting after the backdrop and wash
			picture.Parent = holder
		end
		for _, it in ipairs(PanelSceneLayout.feather(placed, area.w, area.h)) do
			local f = Instance.new("Frame")
			f.Name = "Vignette_" .. it.name
			f.BackgroundColor3 = FILL
			f.BackgroundTransparency = base + (1 - base) * it.transparency
			f.BorderSizePixel = 0
			f.Position, f.Size = UDim2.fromOffset(it.rect.x, it.rect.y), UDim2.fromOffset(it.rect.w, it.rect.h)
			f.Active = false
			f.ZIndex = z
			f.Parent = holder
		end
		if opts.edgeFade then -- the picture's own border reads as a lighter rectangle on the dim room: fade all four edges into the dark fill
			local steps, w = 8, 6
			for i = 0, steps - 1 do
				local t = 0.15 + 0.85 * (i / steps) ^ 1.5
				local o = i * w
				local specs = {
					{ "EL", o, 0, w, area.h }, { "ER", area.w - o - w, 0, w, area.h },
					{ "ET", 0, o, area.w, w }, { "EB", 0, area.h - o - w, area.w, w },
				}
				for _, sp in ipairs(specs) do
					local f = Instance.new("Frame")
					f.Name = "EdgeFade_" .. sp[1] .. i
					f.BackgroundColor3 = FILL
					f.BackgroundTransparency = t
					f.BorderSizePixel = 0
					f.Position, f.Size = UDim2.fromOffset(math.floor(sp[2]), math.floor(sp[3])), UDim2.fromOffset(math.ceil(sp[4]), math.ceil(sp[5]))
					f.Active = false
					f.ZIndex = z
					f.Parent = holder
				end
			end
		end
		holder.Visible = true
	end

	function scene.hide()
		holder.Visible = false
	end

	return scene
end

return PanelScene
