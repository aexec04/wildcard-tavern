--[[
	Client/Table3D/Scene.lua
	Builds the 3D play table out of a theme and nothing else: every material, light, prop and the felt come from the
	four data modules of Shared/TableThemes/<Name>/ (shape: Engine/TableTheme). The measurements of the table itself
	are Engine/TableScene.TABLE, the same for every theme, because the 2D play screen's layout stands on them.

	Scene.build(theme) -> scene
	  scene.model            the Model in Workspace (client side only, the server never sees it)
	  scene.material(name)   -> { material, color, reflectance, transparency } ready to paint a part with
	  scene.paint(part, name)
	  scene.props            { { name, hop, parts = { BasePart }, rest = { CFrame }, at = Vector3 } }
	  scene.lights           { { light, brightness, range, flicker, lantern } }
	Scene.light(theme)       the Lighting service, its effects and the sky's share of the light
	Scene.destroy(scene)
]]

local Lighting = game:GetService("Lighting")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local TS = require(Engine:WaitForChild("TableScene"))
local Rig = require(script.Parent.Rig)

local Scene = {}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function world(x, y, z)
	return Rig.world({ x, y, z })
end

local function still(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- a part of one of the theme's shapes, upright: a Cylinder's size is { diameter, height }
local function shaped(shape, size)
	local part, turn
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
		part.Size = Vector3.new(size[1], size[2], size[3])
	else
		part = Instance.new("Part")
		if shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(size[2], size[1], size[1]) -- a Roblox cylinder lies along its X axis
			turn = CFrame.Angles(0, 0, math.rad(90))
		elseif shape == "Ball" then
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.new(size[1], size[1], size[1])
		else
			part.Size = Vector3.new(size[1], size[2], size[3])
		end
	end
	return still(part), turn
end

function Scene.build(theme)
	local T = TS.TABLE
	local mats, felt = theme.Materials, theme.Felt
	local scene = { props = {}, lights = {} }

	function scene.material(name)
		return mats[name] or mats.cardEdge
	end
	function scene.paint(part, name)
		local m = scene.material(name)
		part.Material = Enum.Material[m.material] or Enum.Material.SmoothPlastic
		part.Color = rgb(m.color)
		part.Reflectance = m.reflectance or 0
		part.Transparency = m.transparency or 0
		return part
	end

	local model = Instance.new("Model")
	model.Name = "Table3DScene"
	scene.model = model

	local function block(name, sx, sy, sz, x, y, z, mat, shadow)
		local p = still(Instance.new("Part"))
		p.Name = name
		p.Size = Vector3.new(sx, sy, sz)
		p.CFrame = CFrame.new(world(x, y, z))
		p.CastShadow = shadow ~= false
		scene.paint(p, mat)
		p.Parent = model
		return p
	end

	local cx, L, W = T.centreX, T.halfLength, T.halfWidth
	local rw, rh = T.railWidth, T.railHeight
	local lip = 0.42 -- the dark step between the felt and the rail's top
	local lipTop = rh * 0.55

	-- felt, the body under it and the floor
	scene.felt = block("Felt", L * 2, T.feltThickness, W * 2, cx, -T.feltThickness / 2, 0, felt.surface, false)
	block("Body", (L + rw) * 2 - 0.5, T.bodyDrop, (W + rw) * 2 - 0.5, cx, -T.feltThickness - T.bodyDrop / 2, 0, felt.body)
	block("Floor", 420, 1, 320, cx, -T.floorDrop - 0.5, -40, felt.floor, false)

	-- the rail: a low dark lip against the felt, then the plank top, with a brass line where they meet
	local railH = rh + T.feltThickness
	local railY = rh - railH / 2
	local lipH = lipTop + T.feltThickness
	local lipY = lipTop - lipH / 2
	for _, side in ipairs({ -1, 1 }) do
		block("RailLong", (L + rw) * 2, railH, rw - lip, cx, railY, side * (W + lip + (rw - lip) / 2), felt.rail.top)
		block("LipLong", L * 2, lipH, lip, cx, lipY, side * (W + lip / 2), felt.rail.inner)
		block("TrimLong", L * 2 + lip * 2, 0.07, 0.1, cx, rh + 0.03, side * (W + lip + 0.05), felt.rail.trim)
		block("RailShort", rw - lip, railH, W * 2 + lip * 2, cx + side * (L + lip + (rw - lip) / 2), railY, 0, felt.rail.top)
		block("LipShort", lip, lipH, W * 2 + lip * 2, cx + side * (L + lip / 2), lipY, 0, felt.rail.inner)
		block("TrimShort", 0.1, 0.07, W * 2 + lip * 2, cx + side * (L + lip + 0.05), rh + 0.03, 0, felt.rail.trim)
	end

	-- brass studs down the middle of the rail's top
	local studs = felt.rail.studs
	if studs then
		local function stud(x, z)
			local p, _ = shaped("Ball", { studs.size })
			p.Name = "Stud"
			p.CFrame = CFrame.new(world(x, rh + studs.size * 0.18, z))
			p.CastShadow = false
			scene.paint(p, studs.material)
			p.Parent = model
		end
		local mid = lip + (rw - lip) / 2
		local nLong = math.max(2, math.floor((L + rw) * 2 / studs.spacing))
		for i = 0, nLong do
			local x = cx - (L + mid) + (L + mid) * 2 * i / nLong
			stud(x, -(W + mid))
			stud(x, W + mid)
		end
		local nShort = math.max(2, math.floor(W * 2 / studs.spacing))
		for i = 1, nShort - 1 do
			local z = -W + W * 2 * i / nShort
			stud(cx - (L + mid), z)
			stud(cx + (L + mid), z)
		end
	end

	-- the line stitched into the felt
	local line = felt.line
	if line then
		local i, w = line.inset, line.width
		for _, side in ipairs({ -1, 1 }) do
			block("FeltLine", (L - i) * 2 + w, 0.012, w, cx, 0.006, side * (W - i), line.material, false)
			block("FeltLine", w, 0.012, (W - i) * 2 + w, cx + side * (L - i), 0.006, 0, line.material, false)
		end
	end

	-- props: plain parts, placed and painted from data
	for _, prop in ipairs(theme.Props) do
		local folder = Instance.new("Model")
		folder.Name = tostring(prop.name or "Prop")
		local at = world(prop.at[1], prop.at[2], prop.at[3])
		local base = CFrame.new(at) * CFrame.Angles(0, math.rad(prop.yaw or 0), 0)
		local entry = { name = folder.Name, hop = prop.hop or 0, parts = {}, rest = {}, at = at }
		local k = prop.scale or 1 -- a prop can be drawn once and stood at any size
		for _, piece in ipairs(prop.parts) do
			local ok, err = pcall(function()
				local size = {}
				for i, v in ipairs(piece.size) do size[i] = v * k end
				local part, turn = shaped(piece.shape, size)
				local o, r = piece.offset or { 0, 0, 0 }, piece.rot or { 0, 0, 0 }
				local cf = base * CFrame.new(o[1] * k, o[2] * k, o[3] * k) * CFrame.fromOrientation(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
				if piece.shadow == false then part.CastShadow = false end
				if turn then cf = cf * turn end
				part.CFrame = cf
				scene.paint(part, piece.mat)
				if part.Material == Enum.Material.Neon then part.CastShadow = false end
				part.Parent = folder
				entry.parts[#entry.parts + 1] = part
				entry.rest[#entry.rest + 1] = cf
			end)
			if not ok then warn("[Table3D] a part of the prop " .. folder.Name .. " was left out: " .. tostring(err)) end
		end
		local lamp = prop.light
		if lamp then
			local holder = still(Instance.new("Part"))
			holder.Name = "Light"
			holder.Size = Vector3.new(0.2, 0.2, 0.2)
			holder.Transparency = 1
			holder.CastShadow = false
			local o = lamp.offset or { 0, 1, 0 }
			holder.CFrame = base * CFrame.new(o[1] * k, o[2] * k, o[3] * k)
			holder.Parent = folder
			local light = Instance.new("PointLight")
			light.Color = rgb(lamp.color)
			light.Brightness = lamp.brightness or 1
			light.Range = lamp.range or 12
			light.Shadows = lamp.shadows == true
			light.Parent = holder
			scene.lights[#scene.lights + 1] = { light = light, brightness = light.Brightness, range = light.Range, flicker = lamp.flicker or 0 }
		end
		folder.Parent = model
		scene.props[#scene.props + 1] = entry
	end

	-- lamps that are not props
	for _, lamp in ipairs(theme.Lighting.lights or {}) do
		local holder = still(Instance.new("Part"))
		holder.Name = tostring(lamp.name or "Lamp")
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Transparency = 1
		holder.CastShadow = false
		local at = world(lamp.at[1], lamp.at[2], lamp.at[3])
		local look = lamp.lookAt and world(lamp.lookAt[1], lamp.lookAt[2], lamp.lookAt[3]) or (at - Vector3.new(0, 1, 0.001))
		holder.CFrame = CFrame.lookAt(at, look)
		holder.Parent = model
		local light
		if lamp.kind == "Spot" then
			light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Angle = lamp.angle or 70
		else
			light = Instance.new("PointLight")
		end
		light.Color = rgb(lamp.color)
		light.Brightness = lamp.brightness or 1
		light.Range = lamp.range or 30
		light.Shadows = lamp.shadows == true
		light.Parent = holder
		scene.lights[#scene.lights + 1] = {
			light = light, brightness = light.Brightness, range = light.Range, flicker = lamp.flicker or 0,
			lantern = lamp.kind == "Spot", color = light.Color,
		}
	end

	model.Parent = workspace
	return scene
end

-- The Lighting service is the place's own (the repo holds scripts only), so the theme sets it when the table starts.
-- Nothing else in the game draws a 3D world: every other screen is a full, opaque 2D picture. One thing a game script
-- may not set is Lighting.LightingStyle (Roblox keeps that for Studio); the theme is tuned for the place as it is.
function Scene.light(theme)
	local L = theme.Lighting
	for key, value in pairs(L.service or {}) do
		local ok = pcall(function()
			Lighting[key] = type(value) == "table" and rgb(value) or value
		end)
		if not ok then warn("[Table3D] the theme sets Lighting." .. tostring(key) .. ", which this place does not have") end
	end
	for class, props in pairs(L.effects or {}) do
		local ok, err = pcall(function()
			local effect = Lighting:FindFirstChildOfClass(class)
			if not effect then
				effect = Instance.new(class)
				effect.Parent = Lighting
			end
			for key, value in pairs(props) do
				effect[key] = type(value) == "table" and rgb(value) or value
			end
			if effect:IsA("PostEffect") then effect.Enabled = true end
		end)
		if not ok then warn("[Table3D] the theme's " .. tostring(class) .. " was skipped: " .. tostring(err)) end
	end
end

function Scene.destroy(scene)
	if scene and scene.model then scene.model:Destroy() end
end

return Scene
