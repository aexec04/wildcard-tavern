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

	Outfits are DATA in Shared/Engine/BossOutfits.lua (one entry per boss id, matched to the painted
	portraits; Default for any boss without one, Keeper for the grand Night 8 boss). Fields:
	  skin, shirt, pants   Color3
	  accent               Color3 (default: picked from the boss id)
	  hat                  "tall" | "cap" | "crown" | "chef" | "party" | "none"
	  hatColor             Color3
	  prop                 see BossOutfits.Props (ladle, ledger, scroll, pocketwatch, receipt, paddle, ...)
	  propColor            Color3
	  cape                 bool (default true)
	  scale                body scale (1 = as built; the stage refits the height anyway)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StageLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("StageLayout"))

local M = {}

local BossOutfits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("BossOutfits"))

-- Color triples in BossOutfits become Color3 here.
local COLOR_FIELDS = { "skin", "shirt", "pants", "hatColor", "propColor", "accent" }
local function toColors(outfit)
	for _, field in ipairs(COLOR_FIELDS) do
		local c = outfit[field]
		if type(c) == "table" then
			outfit[field] = Color3.fromRGB(c[1], c[2], c[3])
		end
	end
	return outfit
end

-- One accent per boss, picked from the id unless the outfit sets its own.
M.Accents = {
	Color3.fromRGB(205, 52, 46), -- crimson
	Color3.fromRGB(232, 150, 42), -- amber
	Color3.fromRGB(150, 84, 210), -- violet
	Color3.fromRGB(44, 168, 164), -- teal
	Color3.fromRGB(86, 176, 72), -- green
	Color3.fromRGB(210, 72, 146), -- magenta
}

-- Body proportions. The boss is long-limbed with broad shoulders; the player's fallback is plain.
local PLAIN = { torsoW = 2, torsoH = 2, torsoD = 1, armW = 1, armL = 2, legW = 1, legL = 2, head = Vector3.new(1.2, 1, 1.2) }
local TALL = { torsoW = 2.3, torsoH = 2.6, torsoD = 1.2, armW = 1, armL = 2.8, legW = 1.1, legL = 2.9, head = Vector3.new(1.15, 1.1, 1.15) }

local function part(parent, name, size, color, material, shape)
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
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
	elseif outfit.hat == "chef" then
		-- a band plus a wide puffed top, like the painted cooks and bakers
		local base = part(model, "Hat", Vector3.new(1.3, 0.5, 1.3), outfit.hatColor)
		weld(base, "HatWeld", head, base, CFrame.new(0, top + 0.25, 0))
		local puff = part(model, "HatPuff", Vector3.new(1.65, 0.95, 1.65), outfit.hatColor)
		weld(puff, "PuffWeld", head, puff, CFrame.new(0, top + 0.95, 0))
	elseif outfit.hat == "party" then
		-- a stepped cone with an accent tip
		local lower = part(model, "Hat", Vector3.new(1.1, 0.5, 1.1), outfit.hatColor)
		weld(lower, "HatWeld", head, lower, CFrame.new(0, top + 0.25, 0))
		local mid = part(model, "HatMid", Vector3.new(0.75, 0.5, 0.75), outfit.hatColor)
		weld(mid, "MidWeld", head, mid, CFrame.new(0, top + 0.75, 0))
		local tip = part(model, "HatTip", Vector3.new(0.4, 0.4, 0.4), accent, nil, Enum.PartType.Ball)
		weld(tip, "TipWeld", head, tip, CFrame.new(0, top + 1.15, 0))
	end
end

-- Props are held in the right hand. Each entry is a list of { name, size, offset(z is forward), colorKey, material, shape }.
-- `hand` is the bottom of the arm; "c" = the prop color, "gold" and "paper" are fixed.
local GOLD_C = Color3.fromRGB(240, 190, 70)
local PAPER_C = Color3.fromRGB(236, 224, 190)
local PROP_PARTS = {
	ladle = {
		{ "Prop", Vector3.new(0.25, 0.25, 2.2), Vector3.new(0, 0, -1.1), "c" },
		{ "PropBowl", Vector3.new(0.9, 0.35, 0.9), Vector3.new(0, 0, -2.3), "c" },
	},
	ledger = { { "Prop", Vector3.new(1.2, 0.3, 1.6), Vector3.new(0, 0, -0.9), "c" } },
	scroll = {
		{ "Prop", Vector3.new(0.5, 0.5, 2), Vector3.new(0, 0, -1), "paper" },
		{ "PropRibbon", Vector3.new(0.56, 0.56, 0.3), Vector3.new(0, 0, -1), "gold" },
	},
	pocketwatch = {
		{ "Prop", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, -0.2, -0.8), "gold", Enum.Material.Metal, Enum.PartType.Ball },
		{ "PropChain", Vector3.new(0.08, 0.9, 0.08), Vector3.new(0, 0.5, -0.8), "gold", Enum.Material.Metal },
	},
	receipt = { -- a long paper strip hanging toward the floor
		{ "Prop", Vector3.new(0.9, 3.4, 0.06), Vector3.new(0, -1.5, -0.7), "paper" },
		{ "PropInk", Vector3.new(0.6, 0.08, 0.08), Vector3.new(0, -0.6, -0.74), "c" },
	},
	paddle = {
		{ "Prop", Vector3.new(0.2, 0.2, 1.2), Vector3.new(0, 0, -0.6), "c" },
		{ "PropDisc", Vector3.new(1.5, 0.15, 1.5), Vector3.new(0, 0, -1.7), "c" },
	},
	broom = {
		{ "Prop", Vector3.new(0.2, 3.2, 0.2), Vector3.new(0, 0.2, -0.5), "c" },
		{ "PropBristles", Vector3.new(0.9, 0.7, 0.5), Vector3.new(0, -1.6, -0.5), "paper" },
	},
	sign = {
		{ "Prop", Vector3.new(0.15, 1.8, 0.15), Vector3.new(0, 0.5, -0.6), "wood" },
		{ "PropBoard", Vector3.new(1.4, 1.1, 0.12), Vector3.new(0, 1.5, -0.6), "c" },
	},
	coins = {
		-- Cylinders run along X, so the size is (thickness, diameter, diameter) and addProp turns them flat.
		{ "Prop", Vector3.new(0.14, 0.9, 0.9), Vector3.new(0, 0, -0.8), "c", Enum.Material.Metal, Enum.PartType.Cylinder },
		{ "PropCoin2", Vector3.new(0.14, 0.9, 0.9), Vector3.new(0, 0.16, -0.8), "c", Enum.Material.Metal, Enum.PartType.Cylinder },
		{ "PropCoin3", Vector3.new(0.14, 0.9, 0.9), Vector3.new(0, 0.32, -0.8), "c", Enum.Material.Metal, Enum.PartType.Cylinder },
	},
	tray = {
		{ "Prop", Vector3.new(2, 0.12, 1.6), Vector3.new(0, 0.1, -1.0), "c" },
		{ "PropPlate1", Vector3.new(0.6, 0.18, 0.6), Vector3.new(-0.4, 0.28, -1.0), "paper" },
		{ "PropPlate2", Vector3.new(0.6, 0.18, 0.6), Vector3.new(0.45, 0.28, -0.9), "gold" },
	},
	lantern = {
		{ "Prop", Vector3.new(0.7, 0.9, 0.7), Vector3.new(0, -0.5, -0.5), "c", Enum.Material.Neon },
		{ "PropCap", Vector3.new(0.8, 0.15, 0.8), Vector3.new(0, 0.02, -0.5), "wood" },
	},
	rollingpin = {
		{ "Prop", Vector3.new(0.45, 0.45, 2.2), Vector3.new(0, 0, -1.1), "c" },
		{ "PropGrip", Vector3.new(0.25, 0.25, 3), Vector3.new(0, 0, -1.1), "c" },
	},
	loaf = { { "Prop", Vector3.new(1.4, 0.7, 0.8), Vector3.new(0, 0, -0.9), "c" } },
	stick = {
		{ "Prop", Vector3.new(0.2, 4.2, 0.2), Vector3.new(0, 1.2, -0.4), "c" },
		{ "PropBand", Vector3.new(0.3, 0.3, 0.3), Vector3.new(0, 3.2, -0.4), "gold", Enum.Material.Metal, Enum.PartType.Ball },
	},
	cards = {
		{ "Prop", Vector3.new(0.7, 0.05, 1), Vector3.new(0, 0, -0.8), "c" },
		{ "PropCard2", Vector3.new(0.7, 0.05, 1), Vector3.new(0.12, 0.06, -0.85), "paper" },
		{ "PropCard3", Vector3.new(0.7, 0.05, 1), Vector3.new(-0.1, 0.12, -0.9), "c" },
	},
}
local WOOD_C = Color3.fromRGB(110, 76, 46)

local function addProp(model, outfit)
	local arm = model:FindFirstChild("Right Arm")
	local parts = PROP_PARTS[outfit.prop]
	if not arm or not parts then
		return
	end
	local hand = -arm.Size.Y / 2
	for _, def in ipairs(parts) do
		local colors = { c = outfit.propColor, gold = GOLD_C, paper = PAPER_C, wood = WOOD_C }
		local prop = part(model, def[1], def[2], colors[def[4]] or outfit.propColor, def[5], def[6])
		local cf = CFrame.new(def[3].X, hand + def[3].Y, def[3].Z)
		if def[6] == Enum.PartType.Cylinder then
			cf = cf * CFrame.Angles(0, 0, math.rad(90)) -- stand the disc flat
		end
		weld(prop, def[1] .. "Weld", arm, prop, cf)
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
	local outfit = toColors(BossOutfits.resolve(bossId, opts.grand))
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
