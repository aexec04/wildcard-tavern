--[[
	Shared/Tests/MapScene.lua
	Test helper: the Tavern Map's layers built by their REAL builders (Client/JourneyMapScenery, JourneyMapGraph,
	JourneyMapDiscoveries, JourneyMapFog) on the fake Roblox of Tests/FakeGui.lua, in the order Client/JourneyMapView builds them,
	inside a plate / scroll / canvas whose ZIndex values are read from the View's own source (so a changed number there is seen
	here). A tile of road (edge, fill, dot) is added the way the View makes them: after the scenery, as children of the canvas.
	The tests then apply the ZIndexBehavior.Global draw order (FakeGui.drawOrder), the rule the live GameUI ScreenGui uses.

	build(opts) -> {
	  gui, plate, scroll, canvas        the fake ScreenGui and the View's TavernMap plate, ScrollingFrame and Canvas
	  scenery, graph, discoveries, fog  what each real builder returned
	  base, holders, tiles, feathers    ParchmentBase, Region1..6 frames, every painting ImageLabel, FeatherTop/FeatherBottom
	  graphRoot, discRoot, fogBand      the WorldGraph, Discoveries and FogBand frames
	  road = { edge, fill, dot }        one piece of each, with the ZIndex the View gives them
	  env, state                        the fake globals and what they collected (state.warns, state.prints)
	}
	opts: canvasW, canvasH (default 4072 x 734), regionArt (set of region keys that have a painting, default all five),
	      decor (doodles drawable and recorded), fogImages (painted fog puffs), studio (RunService:IsStudio()).
]]

local FakeGui = require(script.Parent.FakeGui)
local Engine = script.Parent.Parent.Engine

local MapScene = {}

MapScene.REGION_KEYS = { "region_road", "region_meadow", "region_river", "region_peaks", "region_tavern" }

-- The first "<var>.ZIndex = N" after the line that creates <var> in the View, or nil.
function MapScene.viewZ(src, var)
	local created = src:find("local " .. var .. " = Instance.new(", 1, true)
	if not created then return nil end
	return tonumber(src:match(var .. "%.ZIndex%s*=%s*(%d+)", created))
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

function MapScene.build(opts)
	opts = opts or {}
	local W, H = opts.canvasW or 4072, opts.canvasH or 734
	local viewSrc = assert(readFile("src/Client/JourneyMapView.lua"), "JourneyMapView.lua not found (run from the repo root)")
	local z = {}
	for key, var in pairs({ plate = "frame", scroll = "scroll", canvas = "canvas", edge = "fill", fill = "fill", dot = "dot" }) do
		z[key] = assert(MapScene.viewZ(viewSrc, var), "JourneyMapView.lua no longer sets " .. var .. ".ZIndex after creating it")
	end

	local hoverStub = { new = function() return { bind = function() end, hide = function() end } end }
	local env, state = FakeGui.env({
		studio = opts.studio,
		stubs = { MapHover = hoverStub, RoadLock = { keys = function() return 0 end, isLocked = function() return false end, pick = function() end }, ClientSettings = { get = function() return false end } },
	})
	local mods = {}
	for _, name in ipairs({ "RegionTiles", "MapSeams", "MapPropRules", "WorldMap", "WorldMapLayout", "Discoveries", "MapNodeRules", "MapRouteRules", "MapTooltips" }) do
		mods[name] = require(Engine[name])
	end
	local JourneyMap = require(Engine.JourneyMap)

	-- the View's ScreenGui > TavernMap plate > ScrollingFrame > Canvas
	local gui = FakeGui.new("ScreenGui")
	local plate = FakeGui.new("Frame")
	plate.Name, plate.ZIndex, plate.BackgroundTransparency, plate.Parent = "TavernMap", z.plate, 0, gui
	local scroll = FakeGui.new("ScrollingFrame")
	scroll.ZIndex, scroll.BackgroundTransparency, scroll.Parent = z.scroll, 1, plate
	local canvas = FakeGui.new("Frame")
	canvas.Name, canvas.ZIndex, canvas.BackgroundTransparency, canvas.Parent = "Canvas", z.canvas, 1, scroll

	local have = {} -- regionArt may be a list of keys or a set { key = true }; default: every painting recorded
	for k, v in pairs(opts.regionArt or MapScene.REGION_KEYS) do
		if type(k) == "number" then have[v] = true elseif v then have[k] = true end
	end
	local nextId = 0
	local function id()
		nextId = nextId + 1
		return "rbxassetid://" .. (900000 + nextId)
	end
	local ContentArt = {
		getImageId = function(tab, key)
			if tab == "map_regions" then return have[key] and id() or nil end
			if tab == "map_decor" then return opts.decor and id() or nil end
			if tab == "fx" then return opts.fogImages and id() or nil end
			return nil
		end,
	}
	local PropRules = mods.MapPropRules
	if opts.decor then PropRules = { isDrawable = function() return true end } end
	local noop = function() end

	local function load(name, deps)
		return FakeGui.load("src/Client/" .. name .. ".lua", env)(deps)
	end
	local scene = { gui = gui, plate = plate, scroll = scroll, canvas = canvas, env = env, state = state, z = z }
	scene.scenery = load("JourneyMapScenery", {
		canvas = canvas, roundCorner = noop, ContentArt = ContentArt, RegionTiles = mods.RegionTiles, MapSeams = mods.MapSeams, MapTips = mods.MapTooltips,
		PropRules = PropRules, TweenService = state.services.TweenService, calm = function() return false end,
		parentFrame = plate, addTooltip = noop,
	})
	local engineFolder = FakeGui.folder(mods)
	scene.graph = load("JourneyMapGraph", {
		canvas = canvas, roundCorner = noop, ReplicatedStorage = state.services.ReplicatedStorage, Engine = engineFolder,
		confirmParent = plate, rewardText = function() return nil end, avoidRect = opts.avoidRect, bandTop = opts.bandTop,
	})
	scene.discoveries = load("JourneyMapDiscoveries", {
		canvas = canvas, scroll = scroll, roundCorner = noop, TweenService = state.services.TweenService, Engine = engineFolder,
		calm = function() return false end, graph = scene.graph,
	})
	scene.fog = load("JourneyMapFog", {
		canvas = canvas, TweenService = state.services.TweenService, roundCorner = noop, calm = function() return false end,
		pace = function() return 1 end, ContentArt = ContentArt,
	})

	-- lay the scenery out the way the View does: the nodes spread across the canvas, doodle room above and below them
	local count = #JourneyMap.allNodes()
	local nodeXs = {}
	for i = 1, count do nodeXs[i] = math.floor(W * i / (count + 1)) end
	scene.scenery.layout(W, H, H * 0.35, H * 0.62, nodeXs)
	scene.fog.layout(W, H)
	scene.fog.update({ edgeX = W * 0.55, teaser = { x = W * 0.56, y = H * 0.5, size = 90 }, hintX = W * 0.58, hintY = H * 0.5 })

	-- one road piece of each kind, created after the scenery as the View does (children of the canvas)
	scene.road = {}
	for key, spec in pairs({ edge = z.edge, fill = z.fill, dot = z.dot }) do
		local piece = FakeGui.new("Frame")
		piece.Name, piece.ZIndex, piece.Parent = "Road_" .. key, spec, canvas
		scene.road[key] = piece
	end

	local layer = canvas:FindFirstChild("Scenery")
	scene.base = layer:FindFirstChild("ParchmentBase")
	scene.featherTop, scene.featherBottom = layer:FindFirstChild("FeatherTop"), layer:FindFirstChild("FeatherBottom")
	scene.graphRoot, scene.discRoot, scene.fogBand = canvas:FindFirstChild("WorldGraph"), canvas:FindFirstChild("Discoveries"), canvas:FindFirstChild("FogBand")
	scene.holders, scene.tiles, scene.doodles = {}, {}, {}
	for i = 1, 6 do
		local holder = layer:FindFirstChild("Region" .. i)
		scene.holders[i] = holder
		scene.tiles[i] = holder and holder:GetChildren() or {}
	end
	local decorLayer = layer:FindFirstChild("Decor")
	if decorLayer then scene.doodles = decorLayer:GetChildren() end
	return scene
end

return MapScene
