--[[
	Client/BossRigs.lua
	Builds the blocky boss character shown by CharacterStage.

	  BossRigs.build(bossId, opts?) -> Model
	  opts.tierColor  Color3 accent (shirt tint / hat band), default warm red
	  opts.grand      bool: bigger and golden (Night 8 / Endless milestone bosses)

	The model is a Roblox R6-shaped rig made of anchored Parts joined by Motor6Ds
	(RootJoint, Neck, RightShoulder, LeftShoulder, RightHip, LeftHip) plus Welds for the hat and
	prop. No scripts, no assets, no network. CharacterStage poses it by setting Motor6D.Transform.

	Outfits: BossRigs.Outfits[bossId] overrides pieces of BossRigs.DefaultOutfit; any boss without an
	entry uses the default. Fields:
	  skin, shirt, pants   Color3
	  hat                  "tall" | "cap" | "crown" | "none"
	  hatColor             Color3
	  prop                 "ladle" | "ledger" | "scroll" | "none"
	  propColor            Color3
	  scale                body scale (1 = a normal avatar)
]]

local M = {}

M.DefaultOutfit = {
	skin = Color3.fromRGB(226, 184, 140),
	shirt = Color3.fromRGB(150, 60, 50),
	pants = Color3.fromRGB(60, 48, 40),
	hat = "tall",
	hatColor = Color3.fromRGB(40, 32, 28),
	prop = "ledger",
	propColor = Color3.fromRGB(110, 70, 40),
	scale = 1.15,
}

-- Fill in per boss later (ids are in Engine/BossRounds.lua). A few examples to show the shape.
M.Outfits = {
	bouncer = { shirt = Color3.fromRGB(35, 35, 45), hat = "none", prop = "none", scale = 1.3 },
	the_tab = { hat = "cap", prop = "ledger" },
	thin_soup = { shirt = Color3.fromRGB(235, 235, 225), hat = "tall", hatColor = Color3.fromRGB(245, 245, 240), prop = "ladle" },
	slow_simmer = { shirt = Color3.fromRGB(225, 225, 215), hat = "tall", hatColor = Color3.fromRGB(240, 240, 235), prop = "ladle" },
	house_rules = { shirt = Color3.fromRGB(70, 60, 110), hat = "tall", prop = "scroll" },
}

local function part(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function motor(parent, name, p0, p1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
	return m
end

local function weld(parent, name, p0, p1, c0)
	local w = Instance.new("Weld")
	w.Name = name
	w.Part0 = p0
	w.Part1 = p1
	w.C0 = c0
	w.Parent = parent
	return w
end

-- A plain blocky humanoid rig; used by the boss and as the player's fallback.
-- colors = { skin, shirt, pants } (Color3). Returns the Model (not parented).
function M.buildBlocky(colors, name)
	local model = Instance.new("Model")
	model.Name = name or "BlockyRig"

	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), colors.shirt)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 3, 0)
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), colors.shirt)
	torso.CFrame = root.CFrame
	local head = part(model, "Head", Vector3.new(1.2, 1, 1.2), colors.skin)
	local rArm = part(model, "Right Arm", Vector3.new(1, 2, 1), colors.shirt)
	local lArm = part(model, "Left Arm", Vector3.new(1, 2, 1), colors.shirt)
	local rLeg = part(model, "Right Leg", Vector3.new(1, 2, 1), colors.pants)
	local lLeg = part(model, "Left Leg", Vector3.new(1, 2, 1), colors.pants)

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head

	model.PrimaryPart = root
	motor(torso, "RootJoint", root, torso, CFrame.new(), CFrame.new())
	motor(torso, "Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	motor(torso, "RightShoulder", torso, rArm, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
	motor(torso, "LeftShoulder", torso, lArm, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
	motor(torso, "RightHip", torso, rLeg, CFrame.new(1, -1, 0), CFrame.new(0.5, 1, 0))
	motor(torso, "LeftHip", torso, lLeg, CFrame.new(-1, -1, 0), CFrame.new(-0.5, 1, 0))

	-- Rest positions for the first frame (CharacterStage recomputes them from the joints).
	head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
	rArm.CFrame = torso.CFrame * CFrame.new(1.5, 0, 0)
	lArm.CFrame = torso.CFrame * CFrame.new(-1.5, 0, 0)
	rLeg.CFrame = torso.CFrame * CFrame.new(0.5, -2, 0)
	lLeg.CFrame = torso.CFrame * CFrame.new(-0.5, -2, 0)
	return model
end

local function addHat(model, outfit, accent)
	local head = model:FindFirstChild("Head")
	if not head or outfit.hat == "none" then
		return
	end
	local hat
	if outfit.hat == "tall" then
		hat = part(model, "Hat", Vector3.new(1.3, 1.6, 1.3), outfit.hatColor)
		weld(hat, "HatWeld", head, hat, CFrame.new(0, 0.5 + 0.8, 0))
		local band = part(model, "HatBand", Vector3.new(1.34, 0.25, 1.34), accent)
		weld(band, "BandWeld", head, band, CFrame.new(0, 0.5 + 0.2, 0))
	elseif outfit.hat == "cap" then
		hat = part(model, "Hat", Vector3.new(1.4, 0.45, 1.4), outfit.hatColor)
		weld(hat, "HatWeld", head, hat, CFrame.new(0, 0.5 + 0.2, 0))
	elseif outfit.hat == "crown" then
		hat = part(model, "Hat", Vector3.new(1.3, 0.7, 1.3), Color3.fromRGB(240, 190, 70), Enum.Material.Metal)
		weld(hat, "HatWeld", head, hat, CFrame.new(0, 0.5 + 0.35, 0))
	end
end

local function addProp(model, outfit)
	local arm = model:FindFirstChild("Right Arm")
	if not arm or outfit.prop == "none" then
		return
	end
	local prop
	if outfit.prop == "ladle" then
		prop = part(model, "Prop", Vector3.new(0.25, 0.25, 2.2), outfit.propColor)
		weld(prop, "PropWeld", arm, prop, CFrame.new(0, -1, -1.1))
		local bowl = part(model, "PropBowl", Vector3.new(0.9, 0.35, 0.9), outfit.propColor)
		weld(bowl, "BowlWeld", arm, bowl, CFrame.new(0, -1, -2.3))
	elseif outfit.prop == "ledger" then
		prop = part(model, "Prop", Vector3.new(1.2, 0.3, 1.6), outfit.propColor)
		weld(prop, "PropWeld", arm, prop, CFrame.new(0, -1, -0.9))
	elseif outfit.prop == "scroll" then
		prop = part(model, "Prop", Vector3.new(0.5, 0.5, 2), Color3.fromRGB(235, 220, 180))
		weld(prop, "PropWeld", arm, prop, CFrame.new(0, -1, -1))
	end
end

function M.build(bossId, opts)
	opts = opts or {}
	local outfit = {}
	for k, v in pairs(M.DefaultOutfit) do
		outfit[k] = v
	end
	for k, v in pairs(M.Outfits[bossId] or {}) do
		outfit[k] = v
	end
	local accent = opts.tierColor or Color3.fromRGB(190, 70, 55)
	if opts.grand then
		accent = Color3.fromRGB(235, 190, 80)
		if outfit.hat == "none" then
			outfit.hat = "crown"
		end
	end
	local model = M.buildBlocky({
		skin = outfit.skin,
		shirt = outfit.shirt:Lerp(accent, 0.25),
		pants = outfit.pants,
	}, "BossRig")
	addHat(model, outfit, accent)
	addProp(model, outfit)
	local scale = outfit.scale * (opts.grand and 1.15 or 1)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

return M
