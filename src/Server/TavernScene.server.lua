--[[
	TavernScene.server.lua
	Builds a small 3D tavern room -- floor, walls, a round table, and 4
	seated "Patron" NPCs (Viking / Wizard / Rogue / Goblin) -- entirely out
	of plain Parts and Roblox's built-in SpecialMesh shapes (Pyramid,
	Sphere, ...). No MeshId/ImageId/asset IDs anywhere, on purpose: unlike
	the sound IDs (which you gave us directly), a guessed catalog asset ID
	would just silently fail or error at runtime, so this sticks to
	primitives that are guaranteed to exist.

	This is a first pass at "in-world characters" -- intentionally simple
	and blocky, not aiming to match the painted poster art (that needs
	real art assets, a bigger separate task). Runs once when the server
	starts and builds everything under one Model ("TavernScene") so you
	can select and drag the whole thing to a new spot in Studio if it
	doesn't line up with your baseplate/spawn -- nothing here touches
	SpawnLocation or the player's camera/character.

	Position everything is built relative to TAVERN_ORIGIN below -- change
	that one value if you want the whole scene somewhere else.
]]

local TAVERN_ORIGIN = Vector3.new(0, 1, 0) -- raised 1 stud so the floor doesn't z-fight a default baseplate

local sceneModel = Instance.new("Model")
sceneModel.Name = "TavernScene"
sceneModel.Parent = workspace

-- ===== Mood lighting (poster-art atmosphere) =====
-- This room has no ceiling (see the wall shell below), so Roblox's normal
-- sky/sun lighting still reaches it -- these `Lighting` service settings
-- are what actually set the overall mood, with the torches (further down)
-- filling in the warm highlights on top. Sampled from the game's own
-- thumbnail/poster art: a dim, warm, candlelit tavern at night with a
-- whisper of the Joker card's violet magic in the shadows and haze --
-- same family of colors as the "Neon Joker" cosmetic Theme
-- (Shared/Engine/Themes.lua), so the 3D room and the 2D UI read as one
-- consistent look if you have that Theme equipped (there's currently no
-- code tying the two together beyond sharing hand-picked colors -- the 3D
-- scene doesn't reactively change per-player based on their equipped
-- Theme, it's just one fixed mood for the whole room).
do
	local Lighting = game:GetService("Lighting")

	-- Technology = Future is what actually lets Atmosphere/ColorCorrection
	-- render with real depth (bloom, proper haze) instead of a flatter
	-- fallback look -- standard for a stylized game like this. If it ever
	-- turns out to tank frame rate on a low-end device, ShadowMap is the
	-- safe fallback (just costs some of this atmosphere's richness).
	Lighting.Technology = Enum.Technology.Future
	Lighting.ClockTime = 20 -- dusk/night, so the torches actually read as the light source
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(35, 24, 30) -- dark warm-plum shadow fill
	Lighting.OutdoorAmbient = Color3.fromRGB(45, 32, 40)

	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "TavernColorGrade"
	colorCorrection.TintColor = Color3.fromRGB(255, 225, 205) -- warm amber, matches the candlelight in the poster art
	colorCorrection.Contrast = 0.12
	colorCorrection.Saturation = 0.15 -- a bit more vivid, closer to the poster's punch than flat default lighting
	colorCorrection.Parent = Lighting

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.35
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(199, 170, 140) -- warm haze near the torches
	atmosphere.Decay = Color3.fromRGB(92, 60, 110) -- distant haze picks up a violet cast -- the Joker's magic, at range
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
end

local function makePart(size, cframe, color, material, parent, shape)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.WoodPlanks
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function makeMeshPart(size, cframe, color, meshType, parent)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = meshType
	mesh.Parent = part
	return part
end

-- ===== Room shell =====

local ROOM_SIZE = 40 -- floor is ROOM_SIZE x ROOM_SIZE studs
local WALL_HEIGHT = 16
local WOOD_DARK = Color3.fromRGB(64, 44, 30)
local WOOD_MID = Color3.fromRGB(92, 64, 42)

do
	local floor = makePart(
		Vector3.new(ROOM_SIZE, 1, ROOM_SIZE),
		CFrame.new(TAVERN_ORIGIN),
		WOOD_MID,
		Enum.Material.WoodPlanks,
		sceneModel
	)
	floor.Name = "Floor"

	local wallSpecs = {
		{ size = Vector3.new(ROOM_SIZE, WALL_HEIGHT, 1), offset = Vector3.new(0, WALL_HEIGHT / 2, -ROOM_SIZE / 2) },
		{ size = Vector3.new(ROOM_SIZE, WALL_HEIGHT, 1), offset = Vector3.new(0, WALL_HEIGHT / 2, ROOM_SIZE / 2) },
		{ size = Vector3.new(1, WALL_HEIGHT, ROOM_SIZE), offset = Vector3.new(-ROOM_SIZE / 2, WALL_HEIGHT / 2, 0) },
		{ size = Vector3.new(1, WALL_HEIGHT, ROOM_SIZE), offset = Vector3.new(ROOM_SIZE / 2, WALL_HEIGHT / 2, 0) },
	}
	for i, spec in ipairs(wallSpecs) do
		local wall = makePart(
			spec.size,
			CFrame.new(TAVERN_ORIGIN + spec.offset),
			WOOD_DARK,
			Enum.Material.Wood,
			sceneModel
		)
		wall.Name = "Wall" .. i
	end

	-- Warm wall-mounted torches (Fire + PointLight, both built-in, no assets)
	-- for that lantern-lit tavern glow from the poster art.
	local torchOffsets = {
		Vector3.new(-ROOM_SIZE / 2 + 1, 8, -ROOM_SIZE / 4),
		Vector3.new(-ROOM_SIZE / 2 + 1, 8, ROOM_SIZE / 4),
		Vector3.new(ROOM_SIZE / 2 - 1, 8, -ROOM_SIZE / 4),
		Vector3.new(ROOM_SIZE / 2 - 1, 8, ROOM_SIZE / 4),
	}
	for i, offset in ipairs(torchOffsets) do
		local bracket = makePart(
			Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(TAVERN_ORIGIN + offset),
			Color3.fromRGB(40, 30, 22),
			Enum.Material.Metal,
			sceneModel
		)
		bracket.CanCollide = false
		bracket.Name = "TorchBracket" .. i

		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 170, 60)
		fire.SecondaryColor = Color3.fromRGB(200, 60, 30)
		fire.Parent = bracket

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 180, 110)
		light.Range = 18
		light.Brightness = 2
		light.Parent = bracket
	end
end

-- ===== Round table =====

local TABLE_CENTER = TAVERN_ORIGIN + Vector3.new(0, 0, 0)
local TABLE_RADIUS = 6
local TABLE_TOP_Y = 3

do
	-- Size.X becomes the vertical axis once rotated below (a Cylinder
	-- Part's round end-caps sit on its local X axis by default), so X here
	-- is the pedestal's HEIGHT and Y/Z (equal, for a circular cross
	-- section) are its diameter -- not the usual X/Y/Z = width/height/depth
	-- reading.
	local pedestal = makePart(
		Vector3.new(TABLE_TOP_Y, 2, 2),
		CFrame.new(TABLE_CENTER + Vector3.new(0, TABLE_TOP_Y / 2, 0)),
		WOOD_DARK,
		Enum.Material.Wood,
		sceneModel,
		Enum.PartType.Cylinder
	)
	-- Rotate so the cylinder's axis runs vertically (round faces up/down)
	-- instead of the default horizontal orientation.
	pedestal.CFrame = pedestal.CFrame * CFrame.Angles(0, 0, math.rad(90))
	pedestal.Name = "TablePedestal"

	local tableTop = makePart(
		Vector3.new(1, TABLE_RADIUS * 2, TABLE_RADIUS * 2),
		CFrame.new(TABLE_CENTER + Vector3.new(0, TABLE_TOP_Y, 0)),
		WOOD_MID,
		Enum.Material.WoodPlanks,
		sceneModel,
		Enum.PartType.Cylinder
	)
	tableTop.CFrame = tableTop.CFrame * CFrame.Angles(0, 0, math.rad(90))
	tableTop.Name = "TableTop"

	-- A small violet accent light hovering just over the table -- the
	-- Joker card's magic glow from the poster art, worked into the room
	-- itself rather than just the UI. Same color as the "Neon Joker" Theme's
	-- `cardSelected` (Shared/Engine/Themes.lua), so anyone who's noticed
	-- that Theme's violet gets a subtle real-world echo of it here. Kept
	-- deliberately faint (low Brightness/Range) -- an accent, not a second
	-- sun; the torches (see the room shell below) still do the actual work
	-- of lighting the room.
	local jokerGlowAnchor = Instance.new("Part")
	jokerGlowAnchor.Name = "JokerGlowAnchor"
	jokerGlowAnchor.Anchored = true
	jokerGlowAnchor.CanCollide = false
	jokerGlowAnchor.Transparency = 1
	jokerGlowAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	jokerGlowAnchor.CFrame = CFrame.new(TABLE_CENTER + Vector3.new(0, TABLE_TOP_Y + 3, 0))
	jokerGlowAnchor.Parent = sceneModel

	local jokerGlow = Instance.new("PointLight")
	jokerGlow.Color = Color3.fromRGB(205, 85, 245)
	jokerGlow.Range = 14
	jokerGlow.Brightness = 1.2
	jokerGlow.Parent = jokerGlowAnchor
end

-- ===== Patron NPCs, seated around the table =====

-- Simple blocky "chibi" figure: a ball head, a block torso, two arm
-- blocks. No legs -- the table and chair both hide the lower body from
-- normal player eye level, so it's not worth the extra parts.
local function buildChair(cframe)
	local chair = Instance.new("Model")
	chair.Name = "Chair"
	local seat = makePart(Vector3.new(2.4, 0.4, 2.2), cframe, WOOD_DARK, Enum.Material.Wood, chair)
	seat.Name = "Seat"
	-- +Z here is "away from the table" (a CFrame's forward/LookVector runs
	-- along local -Z, and this chair looks toward the table), so the
	-- backrest sits behind the sitter, not in front of them.
	local backrest = makePart(
		Vector3.new(2.4, 2.4, 0.4),
		cframe * CFrame.new(0, 1.4, 1.1),
		WOOD_DARK,
		Enum.Material.Wood,
		chair
	)
	backrest.Name = "Backrest"
	chair.Parent = sceneModel
	return chair
end

local function buildNPC(name, seatCFrame, skinColor, outfitColor, accentColor, hatStyle)
	local npc = Instance.new("Model")
	npc.Name = name

	-- Seated eye level, facing the table (seatCFrame already looks inward).
	local hipCFrame = seatCFrame * CFrame.new(0, 1.1, 0)

	local torso = makePart(
		Vector3.new(1.8, 1.6, 1.1),
		hipCFrame * CFrame.new(0, 1, 0),
		outfitColor,
		Enum.Material.Fabric,
		npc
	)
	torso.CanCollide = false
	torso.Name = "Torso"

	local head = makeMeshPart(Vector3.new(1.3, 1.3, 1.3), hipCFrame * CFrame.new(0, 2.1, 0), skinColor, Enum.MeshType.Sphere, npc)
	head.Name = "Head"

	-- Slightly -Z (toward the table) so the arms read as "resting near the
	-- table edge" rather than tucked behind the body.
	local armCFrames = {
		hipCFrame * CFrame.new(-1.1, 1, -0.2),
		hipCFrame * CFrame.new(1.1, 1, -0.2),
	}
	for i, armCFrame in ipairs(armCFrames) do
		local arm = makePart(Vector3.new(0.5, 1.4, 0.5), armCFrame, skinColor, Enum.Material.Fabric, npc)
		arm.CanCollide = false
		arm.Name = "Arm" .. i
	end

	-- Persona hat/accessory -- built entirely from SpecialMesh primitives
	-- (Pyramid, Sphere), never a downloaded asset.
	if hatStyle == "viking" then
		local helmet = makeMeshPart(Vector3.new(1.45, 0.9, 1.45), hipCFrame * CFrame.new(0, 2.55, 0), Color3.fromRGB(150, 150, 155), Enum.MeshType.Sphere, npc)
		helmet.Name = "Helmet"
		for _, side in ipairs({ -1, 1 }) do
			local horn = makeMeshPart(
				Vector3.new(0.35, 0.9, 0.35),
				hipCFrame * CFrame.new(0.85 * side, 2.6, 0) * CFrame.Angles(0, 0, math.rad(20 * side)),
				Color3.fromRGB(235, 225, 200),
				Enum.MeshType.Pyramid,
				npc
			)
			horn.Name = "Horn"
		end
	elseif hatStyle == "wizard" then
		local hat = makeMeshPart(
			Vector3.new(1.6, 2.6, 1.6),
			hipCFrame * CFrame.new(0, 3.3, 0),
			accentColor,
			Enum.MeshType.Pyramid,
			npc
		)
		hat.Name = "WizardHat"
		local beard = makeMeshPart(Vector3.new(0.9, 0.9, 0.6), hipCFrame * CFrame.new(0, 1.6, -0.7), Color3.fromRGB(235, 235, 235), Enum.MeshType.Sphere, npc)
		beard.Name = "Beard"
	elseif hatStyle == "rogue" then
		local hood = makeMeshPart(Vector3.new(1.6, 1.5, 1.6), hipCFrame * CFrame.new(0, 2.25, 0.15), accentColor, Enum.MeshType.Sphere, npc)
		hood.Name = "Hood"
	elseif hatStyle == "goblin" then
		for _, side in ipairs({ -1, 1 }) do
			local ear = makeMeshPart(
				Vector3.new(0.3, 0.7, 0.3),
				hipCFrame * CFrame.new(0.75 * side, 2.15, 0) * CFrame.Angles(0, 0, math.rad(35 * side)),
				outfitColor,
				Enum.MeshType.Pyramid,
				npc
			)
			ear.Name = "Ear"
		end
	end

	npc.Parent = sceneModel
	return npc
end

-- 4 seats evenly spaced around the table, each facing inward toward the
-- center. angle 0 = +Z side, going clockwise.
local PATRON_SEATS = {
	{ name = "Viking Patron", angle = 0, skin = Color3.fromRGB(235, 190, 150), outfit = Color3.fromRGB(120, 40, 35), accent = Color3.fromRGB(150, 150, 155), hat = "viking" },
	{ name = "Wizard Patron", angle = 90, skin = Color3.fromRGB(230, 195, 165), outfit = Color3.fromRGB(45, 55, 130), accent = Color3.fromRGB(80, 60, 150), hat = "wizard" },
	{ name = "Rogue Patron", angle = 180, skin = Color3.fromRGB(200, 165, 140), outfit = Color3.fromRGB(35, 30, 40), accent = Color3.fromRGB(25, 20, 30), hat = "rogue" },
	{ name = "Goblin Patron", angle = 270, skin = Color3.fromRGB(120, 170, 90), outfit = Color3.fromRGB(90, 130, 60), accent = Color3.fromRGB(70, 100, 50), hat = "goblin" },
}

for _, seatSpec in ipairs(PATRON_SEATS) do
	local angleRad = math.rad(seatSpec.angle)
	local seatDistance = TABLE_RADIUS + 2.4
	local seatPosition = TABLE_CENTER
		+ Vector3.new(math.sin(angleRad) * seatDistance, 0.2, math.cos(angleRad) * seatDistance)
	-- Face back toward the table center.
	local seatCFrame = CFrame.new(seatPosition, TABLE_CENTER + Vector3.new(0, 0.2, 0))

	buildChair(seatCFrame)
	buildNPC(seatSpec.name, seatCFrame, seatSpec.skin, seatSpec.outfit, seatSpec.accent, seatSpec.hat)
end

print("[TavernScene] Built room + table + " .. #PATRON_SEATS .. " seated Patron NPCs under workspace.TavernScene")
