--[[
	Client/BossRigs.lua
	Builds the blocky boss character shown by CharacterStage (and the player's blocky fallback).

	  BossRigs.build(bossId, opts?) -> Model
	  opts.grand      bool: gold accent, crown if the outfit has no hat, a little bigger
	  opts.tierColor  Color3 accent override (otherwise Outfit.accent, otherwise a per-boss color)

	The model is a Roblox R6-shaped rig made of anchored Parts joined by Motor6Ds
	(RootJoint, Neck, RightShoulder, LeftShoulder, RightHip, LeftHip) plus Welds for the hat, prop and
	trim. Welds run from the body part to the trim part (Part0 = body). No scripts, no assets, no network.
	CharacterStage poses it with its own forward kinematics over these joints.

	Look: a tall, narrow-waisted silhouette (long arms and legs, broad shoulder plates), a dark palette
	and one accent color per boss (sash, shoulder plates, hat band, glowing eyes) so every boss reads as
	menacing but different. The stage rescales every rig to its target height, so proportions matter here,
	not absolute size.

	Outfits: BossRigs.Outfits[bossId] overrides pieces of BossRigs.DefaultOutfit; any boss without an
	entry uses the default. Fields:
	  skin, shirt, pants   Color3
	  accent               Color3 (default: picked from the boss id)
	  hat                  "tall" | "cap" | "crown" | "none"
	  hatColor             Color3
	  prop                 "ladle" | "ledger" | "scroll" | "none"
	  propColor            Color3
	  cape                 bool (default true)
	  scale                body scale (1 = as built; the stage refits the height anyway)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StageLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("StageLayout"))

local M = {}

M.DefaultOutfit = {
	skin = Color3.fromRGB(178, 152, 134),
	shirt = Color3.fromRGB(46, 32, 38),
	pants = Color3.fromRGB(28, 24, 30),
	hat = "tall",
	hatColor = Color3.fromRGB(26, 22, 26),
	prop = "ledger",
	propColor = Color3.fromRGB(86, 58, 40),
	cape = true,
	scale = 1,
}

-- One accent per boss, picked from the id unless the outfit sets its own.
M.Accents = {
	Color3.fromRGB(205, 52, 46), -- crimson
	Color3.fromRGB(232, 150, 42), -- amber
	Color3.fromRGB(150, 84, 210), -- violet
	Color3.fromRGB(44, 168, 164), -- teal
	Color3.fromRGB(86, 176, 72), -- green
	Color3.fromRGB(210, 72, 146), -- magenta
}

-- Fill in per boss later (ids are in Engine/BossRounds.lua). A few examples to show the shape.
M.Outfits = {
	bouncer = { shirt = Color3.fromRGB(24, 24, 32), hat = "none", prop = "none", cape = false },
	the_tab = { hat = "cap", prop = "ledger" },
	thin_soup = { shirt = Color3.fromRGB(70, 74, 82), hat = "tall", hatColor = Color3.fromRGB(226, 226, 220), prop = "ladle" },
	slow_simmer = { shirt = Color3.fromRGB(78, 70, 66), hat = "tall", hatColor = Color3.fromRGB(226, 224, 216), prop = "ladle" },
	house_rules = { shirt = Color3.fromRGB(40, 34, 70), hat = "tall", prop = "scroll" },
}

-- Body proportions. The boss is long-limbed with broad shoulders; the player's fallback is plain.
local PLAIN = { torsoW = 2, torsoH = 2, torsoD = 1, armW = 1, armL = 2, legW = 1, legL = 2, head = Vector3.new(1.2, 1, 1.2) }
local TALL = { torsoW = 2.3, torsoH = 2.6, torsoD = 1.2, armW = 1, armL = 2.8, legW = 1.1, legL = 2.9, head = Vector3.new(1.15, 1.1, 1.15) }

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

-- Part0 = the body part, Part1 = the trim: the trim sits at body * c0.
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
-- colors = { skin, shirt, pants } (Color3), shape = PLAIN (default) or TALL. Returns the Model (not parented).
function M.buildBlocky(colors, name, shape, withFace)
	shape = shape or PLAIN
	if withFace == nil then
		withFace = true
	end
	local model = Instance.new("Model")
	model.Name = name or "BlockyRig"

	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), colors.shirt)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 3, 0)
	local torso = part(model, "Torso", Vector3.new(shape.torsoW, shape.torsoH, shape.torsoD), colors.shirt)
	torso.CFrame = root.CFrame
	local head = part(model, "Head", shape.head, colors.skin)
	local armSize = Vector3.new(shape.armW, shape.armL, shape.torsoD * 0.85)
	local legSize = Vector3.new(shape.legW, shape.legL, shape.torsoD * 0.85)
	local rArm = part(model, "Right Arm", armSize, colors.shirt)
	local lArm = part(model, "Left Arm", armSize, colors.shirt)
	local rLeg = part(model, "Right Leg", legSize, colors.pants)
	local lLeg = part(model, "Left Leg", legSize, colors.pants)

	if withFace then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Face = Enum.NormalId.Front
		face.Texture = "rbxasset://textures/face.png"
		face.Parent = head
	end

	local tw, th = shape.torsoW / 2, shape.torsoH / 2
	local armY = th - 0.5 -- shoulder joint, 0.5 below the top of the torso
	model.PrimaryPart = root
	motor(torso, "RootJoint", root, torso, CFrame.new(), CFrame.new())
	motor(torso, "Neck", torso, head, CFrame.new(0, th, 0), CFrame.new(0, -shape.head.Y / 2, 0))
	motor(torso, "RightShoulder", torso, rArm, CFrame.new(tw, armY, 0), CFrame.new(-shape.armW / 2, shape.armL / 2 - 0.5, 0))
	motor(torso, "LeftShoulder", torso, lArm, CFrame.new(-tw, armY, 0), CFrame.new(shape.armW / 2, shape.armL / 2 - 0.5, 0))
	motor(torso, "RightHip", torso, rLeg, CFrame.new(tw, -th, 0), CFrame.new(shape.legW / 2, shape.legL / 2, 0))
	motor(torso, "LeftHip", torso, lLeg, CFrame.new(-tw, -th, 0), CFrame.new(-shape.legW / 2, shape.legL / 2, 0))

	-- Rest positions for the first frame (CharacterStage recomputes them from the joints).
	head.CFrame = torso.CFrame * CFrame.new(0, th + shape.head.Y / 2, 0)
	rArm.CFrame = torso.CFrame * CFrame.new(tw + shape.armW / 2, (shape.torsoH - shape.armL) / 2, 0)
	lArm.CFrame = torso.CFrame * CFrame.new(-tw - shape.armW / 2, (shape.torsoH - shape.armL) / 2, 0)
	rLeg.CFrame = torso.CFrame * CFrame.new(tw - shape.legW / 2, -th - shape.legL / 2, 0)
	lLeg.CFrame = torso.CFrame * CFrame.new(-tw + shape.legW / 2, -th - shape.legL / 2, 0)
	return model
end

local function addHat(model, outfit, accent)
	local head = model:FindFirstChild("Head")
	if not head or outfit.hat == "none" then
		return
	end
	local top = head.Size.Y / 2
	if outfit.hat == "tall" then
		local hat = part(model, "Hat", Vector3.new(1.3, 1.9, 1.3), outfit.hatColor)
		weld(hat, "HatWeld", head, hat, CFrame.new(0, top + 0.95, 0))
		local band = part(model, "HatBand", Vector3.new(1.34, 0.28, 1.34), accent)
		weld(band, "BandWeld", head, band, CFrame.new(0, top + 0.2, 0))
	elseif outfit.hat == "cap" then
		local hat = part(model, "Hat", Vector3.new(1.4, 0.45, 1.4), outfit.hatColor)
		weld(hat, "HatWeld", head, hat, CFrame.new(0, top + 0.2, 0))
		local band = part(model, "HatBand", Vector3.new(1.44, 0.12, 1.44), accent)
		weld(band, "BandWeld", head, band, CFrame.new(0, top + 0.02, 0))
	elseif outfit.hat == "crown" then
		local hat = part(model, "Hat", Vector3.new(1.3, 0.7, 1.3), Color3.fromRGB(240, 190, 70), Enum.Material.Metal)
		weld(hat, "HatWeld", head, hat, CFrame.new(0, top + 0.35, 0))
	end
end

local function addProp(model, outfit)
	local arm = model:FindFirstChild("Right Arm")
	if not arm or outfit.prop == "none" then
		return
	end
	local hand = -arm.Size.Y / 2
	if outfit.prop == "ladle" then
		local prop = part(model, "Prop", Vector3.new(0.25, 0.25, 2.2), outfit.propColor)
		weld(prop, "PropWeld", arm, prop, CFrame.new(0, hand, -1.1))
		local bowl = part(model, "PropBowl", Vector3.new(0.9, 0.35, 0.9), outfit.propColor)
		weld(bowl, "BowlWeld", arm, bowl, CFrame.new(0, hand, -2.3))
	elseif outfit.prop == "ledger" then
		local prop = part(model, "Prop", Vector3.new(1.2, 0.3, 1.6), outfit.propColor)
		weld(prop, "PropWeld", arm, prop, CFrame.new(0, hand, -0.9))
	elseif outfit.prop == "scroll" then
		local prop = part(model, "Prop", Vector3.new(0.5, 0.5, 2), Color3.fromRGB(235, 220, 180))
		weld(prop, "PropWeld", arm, prop, CFrame.new(0, hand, -1))
	end
end

-- Accent trim: sash, shoulder plates, glowing eyes and a heavy brow, plus an optional dark cape.
local function addMenace(model, outfit, accent)
	local torso = model:FindFirstChild("Torso")
	local head = model:FindFirstChild("Head")
	local rArm, lArm = model:FindFirstChild("Right Arm"), model:FindFirstChild("Left Arm")
	if torso then
		local sash = part(model, "Sash", Vector3.new(torso.Size.X + 0.06, 0.4, torso.Size.Z + 0.06), accent)
		weld(sash, "SashWeld", torso, sash, CFrame.new(0, -torso.Size.Y / 2 + 0.55, 0))
		if outfit.cape then
			local cape = part(model, "Cape", Vector3.new(torso.Size.X + 0.3, torso.Size.Y + 1.4, 0.16),
				outfit.shirt:Lerp(Color3.fromRGB(0, 0, 0), 0.35))
			weld(cape, "CapeWeld", torso, cape, CFrame.new(0, -0.5, torso.Size.Z / 2 + 0.12))
		end
	end
	for _, arm in ipairs({ rArm, lArm }) do
		if arm then
			local plate = part(model, "Pauldron", Vector3.new(arm.Size.X + 0.45, 0.45, arm.Size.Z + 0.45), accent, Enum.Material.Metal)
			weld(plate, "PauldronWeld", arm, plate, CFrame.new(0, arm.Size.Y / 2 + 0.05, 0))
		end
	end
	if head then
		local front = -head.Size.Z / 2 - 0.02
		for _, x in ipairs({ -0.24, 0.24 }) do
			local eye = part(model, "Eye", Vector3.new(0.26, 0.13, 0.06), accent, Enum.Material.Neon)
			weld(eye, "EyeWeld", head, eye, CFrame.new(x, 0.08, front))
		end
		local brow = part(model, "Brow", Vector3.new(0.9, 0.12, 0.07), Color3.fromRGB(20, 16, 18))
		weld(brow, "BrowWeld", head, brow, CFrame.new(0, 0.25, front))
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
	local accent = opts.tierColor or outfit.accent or M.Accents[StageLayout.accentIndex(bossId or "boss", #M.Accents)]
	if opts.grand then
		accent = Color3.fromRGB(235, 190, 80)
		if outfit.hat == "none" then
			outfit.hat = "crown"
		end
	end
	local model = M.buildBlocky({
		skin = outfit.skin,
		shirt = outfit.shirt,
		pants = outfit.pants,
	}, "BossRig", TALL, false)
	addMenace(model, outfit, accent)
	addHat(model, outfit, accent)
	addProp(model, outfit)
	local scale = outfit.scale * (opts.grand and 1.1 or 1)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

return M
