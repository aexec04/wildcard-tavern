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
local FILL = Color3.fromRGB(32, 22, 15) -- the wall colour of the holder the vignette fades into
local OVERSHOOT = 24 -- the holder runs this far below the area so no dark strip shows under it (the panel clips it)

-- the picture fades its own uncovered sides into the wall: one horizontal UIGradient on the picture (Roblox keeps one, so replace it)
local function sideFade(picture, pts)
	local old = picture:FindFirstChild("SideFade")
	if old then old:Destroy() end
	if not pts then return end
	local g = Instance.new("UIGradient")
	g.Name = "SideFade"
	local keys = {}
	for _, k in ipairs(pts) do keys[#keys + 1] = NumberSequenceKeypoint.new(k[1], k[2]) end
	g.Transparency = NumberSequence.new(keys)
	g.Parent = picture
end

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
	local wall = Instance.new("Frame") -- the shared painted Collection wall under a scrim fills every uncovered side (no flat dark voids)
	wall.Name = "Wall"
	wall.BorderSizePixel = 0
	wall.Size = UDim2.fromScale(1, 1)
	wall.ClipsDescendants = true
	wall.Active = false
	wall.ZIndex = z
	wall.Parent = holder
	require(script.Parent.RoomWall).fill(wall, z)
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.Image = id or ""
	picture.ScaleType = Enum.ScaleType.Stretch
	picture.Active = false
	picture.ZIndex = z
	picture.Parent = holder

	function scene.show(area, placed)
		local fullH = area.h + OVERSHOOT
		holder.Position, holder.Size = UDim2.fromOffset(area.x, area.y), UDim2.fromOffset(area.w, fullH)
		picture.Position, picture.Size = UDim2.fromOffset(placed.image.x, placed.image.y), UDim2.fromOffset(placed.image.w, placed.image.h)
		for _, ch in ipairs(holder:GetChildren()) do
			if ch ~= picture and ch ~= wall then ch:Destroy() end
		end
		sideFade(picture, PanelSceneLayout.sideFade(placed, area.w))
		-- Where the picture does not reach the area, the holder's flat wall colour shows (never a second copy of the painting, which read as
		-- giant candles and lanterns); the feather strips fade the picture into it.
		local base = 0
		for _, it in ipairs(PanelSceneLayout.verticalEdges(placed, area.w, area.h)) do
			local f = Instance.new("Frame")
			f.Name = "Vignette_" .. it.name
			f.BackgroundColor3 = require(script.Parent.RoomWall).COLOR -- the wall's tone, so the picture edge melts into the wall
			f.BackgroundTransparency = 0
			f.BorderSizePixel = 0
			f.Position, f.Size = UDim2.fromOffset(it.rect.x, it.rect.y), UDim2.fromOffset(it.rect.w, it.rect.h)
			f.Active = false
			f.ZIndex = z
			local g = Instance.new("UIGradient")
			g.Rotation = it.rotation
			local keys = {}
			for _, k in ipairs(it.points) do keys[#keys + 1] = NumberSequenceKeypoint.new(k[1], base + (1 - base) * k[2]) end
			g.Transparency = NumberSequence.new(keys)
			g.Parent = f
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
