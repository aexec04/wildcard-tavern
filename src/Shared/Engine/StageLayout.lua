--[[
	Shared/Engine/StageLayout.lua
	Pure layout math for the live character stage (Client/CharacterStage.lua), so it can be tested.

	The stage is a full-height ViewportFrame. Characters must stand on a floor line that sits above
	the hand row and below the boss plaque and HP bar, with their feet visible, so sizes come from the
	free band between those two, not from a fixed fraction of the screen:

	  top of band    = TOP_FRACTION * screen height   (plaque + HP bar end near 34% of the height)
	  floor line     = screen height - HAND_CLEARANCE (the hand row is 176px tall and starts 272px
	                   above the bottom, see handFrame in init.client.lua; 10px of air on top)

	All heights are in pixels of the viewport; CharacterStage converts them to studs.
]]

local StageLayout = {}

StageLayout.HAND_CLEARANCE = 282 -- px from the bottom of the screen to keep clear of the hand row
StageLayout.TOP_FRACTION = 0.36 -- band starts below the boss plaque / HP bar
StageLayout.PLAYER_BAND_FRACTION = 0.8 -- player height in a Boss Round, as a share of the free band
StageLayout.NORMAL_BAND_FRACTION = 0.98 -- square avatar box in a normal round (about 2.5x the old 0.62 look at 1080p: ~400px box, ~300px visible figure)
StageLayout.AVATAR_FOOT_PAD = 0.07 -- share of the 420x420 thumbnail left empty under the feet; the client sinks the box by it
StageLayout.BOSS_TALLER = 1.12 -- the boss stands a little taller than the player
StageLayout.GRAND_TALLER = 1.08 -- Night 8 / Endless milestone bosses on top of that
StageLayout.MIN_HEIGHT = 90
StageLayout.MAX_BAND_USE = 0.98

-- Floor line as a fraction of the screen height (0 top, 1 bottom).
function StageLayout.floorFraction(screenHeight, clearance)
	screenHeight = math.max(1, screenHeight)
	clearance = clearance or StageLayout.HAND_CLEARANCE
	return math.min(0.85, math.max(0.5, 1 - clearance / screenHeight))
end

-- Free vertical band in pixels between the plaque area and the floor line.
function StageLayout.bandPixels(screenHeight, floorFrac, topFrac)
	floorFrac = floorFrac or StageLayout.floorFraction(screenHeight)
	return math.max(StageLayout.MIN_HEIGHT, (floorFrac - (topFrac or StageLayout.TOP_FRACTION)) * screenHeight)
end

-- On the painted play table (Engine/PlayTableLayout) the felt starts about 38 percent down, so the stage stands in the band
-- between the top bar and the felt's back edge and the table front never covers a character. Returns floorFrac, topFrac, or
-- nil when the painted table is not used (screen too narrow), which keeps the old band.
StageLayout.TABLE_TOP_PX = 100 -- clear of the boss name plate and HP bar (plate ends at 60 px)
StageLayout.TABLE_TOP_MIN = 0.12
function StageLayout.tableBand(screenW, screenH)
	local PlayTableLayout = require(script.Parent:WaitForChild("PlayTableLayout"))
	if not PlayTableLayout.usable(screenW) or screenH < 1 then return nil end
	local m = PlayTableLayout.map(screenW, screenH)
	local floorFrac = math.min(0.85, math.max(0.2, m.felt.y / screenH))
	local topFrac = math.max(StageLayout.TABLE_TOP_MIN, StageLayout.TABLE_TOP_PX / screenH)
	if floorFrac - topFrac < 0.1 then topFrac = math.max(0.02, floorFrac - 0.1) end
	return floorFrac, topFrac
end

-- The boss portrait on the painted table: a framed picture hung in the free band between the name plate and the felt's back
-- edge (the table front covers everything below it). Returns { top, height, width } in screen pixels, or nil when the painted
-- table is not used or the band is too short to read (the caller then keeps the full-area backdrop).
StageLayout.PORTRAIT_TOP = 76 -- below the name plate (ends at 60) and the taunt bubble (ends at 72)
StageLayout.PORTRAIT_GAP = 6 -- air between the frame (and its nameplate) and the felt back edge
StageLayout.PORTRAIT_PLATE = 24 -- nameplate hung across the frame's bottom border: its lower half sits below the frame
StageLayout.PORTRAIT_SHRINK = 0.88 -- the band is not used to the brim: the table's rim reads a little above the measured felt line
StageLayout.PORTRAIT_MIN = 90
function StageLayout.bossFrame(screenW, screenH)
	local PlayTableLayout = require(script.Parent:WaitForChild("PlayTableLayout"))
	if not PlayTableLayout.usable(screenW) or screenH < 1 then return nil end
	local feltY = PlayTableLayout.map(screenW, screenH).felt.y
	local top = StageLayout.PORTRAIT_TOP
	local free = feltY - StageLayout.PORTRAIT_GAP - math.floor(StageLayout.PORTRAIT_PLATE / 2) - top
	local height = math.floor(math.min(free * StageLayout.PORTRAIT_SHRINK, screenH * 0.5))
	if height < StageLayout.PORTRAIT_MIN then return nil end
	return { top = top, height = height, width = height, plateH = StageLayout.PORTRAIT_PLATE }
end

-- Pixel heights for the rigs. mode = "normal" (player only) or "boss". Returns player, boss (boss nil in normal).
function StageLayout.heights(screenHeight, floorFrac, mode, grand, topFrac)
	local band = StageLayout.bandPixels(screenHeight, floorFrac, topFrac)
	if mode ~= "boss" then
		return math.max(StageLayout.MIN_HEIGHT, band * StageLayout.NORMAL_BAND_FRACTION), nil
	end
	local player = math.max(StageLayout.MIN_HEIGHT, band * StageLayout.PLAYER_BAND_FRACTION)
	local boss = player * StageLayout.BOSS_TALLER * (grand and StageLayout.GRAND_TALLER or 1)
	boss = math.min(boss, band * StageLayout.MAX_BAND_USE)
	return player, boss
end

-- Deterministic small index (1..count) from a string id, for per-boss accent colors.
function StageLayout.accentIndex(id, count)
	local sum = 0
	for i = 1, #tostring(id) do
		sum = sum + tostring(id):byte(i) * i
	end
	return (sum % count) + 1
end

return StageLayout
