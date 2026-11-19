--[[
	Shared/Tests/CollectionScene.lua
	Test helper: the REAL Collection panel (Client/Collection.lua with the real CollectionRoom, CollectionGallery and CollectionFurniture)
	built on the fake Roblox of Tests/FakeGui.lua, the way the client builds it, with the account panels and the shared tab strip stubbed.
	The tests then open it, click the gallery room's hotspots and count what every section puts on its furniture.

	CollectionScene.build(opts) -> {
	  gui, backdrop, panel, room, grid, quiet, legend, detail   the instances (room = GalleryRoom, grid = SectionGrid, quiet = QuietTabs)
	  open()                      what the Collection button does (the registered opener)
	  hotspot(id)                 the Hotspot_<id> frame of the room (its .Surface is the TextButton that takes the click)
	  pick(id)                    click that hotspot (zooms into the section)
	  tiles()                     the section's tile buttons once every delayed batch has been built
	  resize(vpX, vpY)            set the window and the panel size the way ResponsiveLayout does; fires the layout
	  step()                      what Escape does inside the panel (PanelTabs.setStep's function): true when it went back a level
	  state                       FakeGui's state (warns, prints, runWaiting); latest = the state table getLatestState answers
	}
	opts: discovered = { [tabId] = { id, ... } }, unlockedAchievementIds, equippedTitleId, calm, studio
]]

local FakeGui = require(script.Parent.FakeGui)
local Engine = script.Parent.Parent.Engine

local CollectionScene = {}

function CollectionScene.build(opts)
	opts = opts or {}
	local noop = function() end
	local stubs = {}
	local env, state = FakeGui.env({ studio = opts.studio, stubs = stubs })

	-- the modules the real files reach through ReplicatedStorage.Shared.Engine
	local map = {}
	for _, name in ipairs({ "CollectionBook", "ContentArt", "CollectionSceneLayout", "CollectionRoomLayout", "CollectionFurnitureLayout",
		"StageMotion", "ResponsiveLayout", "MothFlight", "CollectionSectionLayout", "RoomGrid", "VignetteCurve", "CollectionPreload", "PanelLayout", "CollectionCards", "ConceptTPatronArt" }) do
		map[name] = require(Engine[name])
	end
	local engineFolder = FakeGui.folder(map)
	state.services.ReplicatedStorage = { WaitForChild = function() return { WaitForChild = function() return engineFolder end } end }

	-- globals the plain fake does not have
	local camera = { ViewportSize = { X = 1280, Y = 720 }, GetPropertyChangedSignal = function() return FakeGui.signal() end }
	env.workspace = { CurrentCamera = camera }
	env.Font = { new = function() return {} end }
	local fromRGB = env.Color3.fromRGB
	env.Color3.fromRGB = function(r, g, b) -- showDetail blends two colours
		local c = fromRGB(r, g, b)
		return setmetatable(c, { __index = { Lerp = function(a) return a end } })
	end

	local openers, steps, registered = {}, {}, {}
	stubs.ClientSettings = { get = function(key) return opts.calm == true and key == "reduceShake" end }
	stubs.OverlayManager = {
		register = function(id, fn) registered[id] = fn end, registerOpener = function(id, fn) openers[id] = fn end,
		closeAllExcept = noop, close = noop, open = noop,
	}
	stubs.ArtFade = { apply = function() end }
	stubs.PatronPlaque = { applyById = function(frame) local img = FakeGui.new("ImageLabel"); img.Parent = frame; return img end }
	stubs.RarityFrame = { apply = noop, colorFor = function() return fromRGB(180, 160, 120) end }
	stubs.PanelArt = { add = function() return nil end, vignette = noop }
	stubs.CollectionWall = { mount = function() return nil end }
	stubs.CosmeticSetsPanel = noop
	stubs.LazyPanel = { wrap = function(_, init) return init end }
	stubs.BadgesPanel = noop
	stubs.StatsPanel = noop
	stubs.CollectionRewardsPanel = { init = noop }
	stubs.FlairPanel = { init = noop }
	stubs.LegendPanel = { init = noop }
	stubs.ExpandToggle = function() return { setCollapsedSize = noop } end
	stubs.ModalStage = { mount = noop }
	stubs.PanelTabs = { attach = noop, setStep = function(id, fn) steps[id] = fn end }
	stubs.PanelFullScreen = FakeGui.load("src/Client/PanelFullScreen.lua", env)
	stubs.CollectionGallery = FakeGui.load("src/Client/CollectionGallery.lua", env)
	stubs.CollectionFurniture = FakeGui.load("src/Client/CollectionFurniture.lua", env)
	stubs.SmoothVignette = FakeGui.load("src/Client/SmoothVignette.lua", env)
	stubs.RoomHotspots = FakeGui.load("src/Client/RoomHotspots.lua", env)
	stubs.CollectionRoom = FakeGui.load("src/Client/CollectionRoom.lua", env)
	-- the painted section scenes are the real module, but only on when a test asks (opts.painted); otherwise the scrolling grid shows
	-- and the older tests keep counting its tiles
	do
		local real = FakeGui.load("src/Client/CollectionSection.lua", env)
		stubs.CollectionSection = {
			new = function(o)
				local s = real.new(o)
				local can = s.canShow
				s.canShow = function(...) return opts.painted == true and can(...) end
				return s
			end,
		}
	end

	local latest = {
		collection = { discovered = opts.discovered or {}, claimedMilestoneIds = {} },
		unlockedAchievementIds = opts.unlockedAchievementIds or {},
		equippedTitleId = opts.equippedTitleId,
	}
	local gui = FakeGui.new("ScreenGui")
	local deps = {
		screenGui = gui,
		polishPanel = function(p) local s = FakeGui.new("UIStroke"); s.Parent = p end,
		polishButton = noop, roundCorner = function(inst) local c = FakeGui.new("UICorner"); c.Parent = inst end,
		addSoftShadow = noop, playClickSfx = noop, Achievements = {}, EquipTitleRemote = { FireServer = noop },
		getLatestState = function() return latest end,
		popIn = function(backdrop) backdrop.Visible = true end, popOut = function(backdrop) backdrop.Visible = false end,
		addButtonHoverScale = noop, addTooltip = noop, collectionButton = FakeGui.new("TextButton"),
		StateUpdatedRemote = { OnClientEvent = FakeGui.signal() },
	}
	local Collection = FakeGui.load("src/Client/Collection.lua", env)
	Collection(deps)

	local backdrop = assert(gui:FindFirstChild("CollectionBackdrop"), "the Collection builds its backdrop")
	local panel = backdrop:GetChildren()[1]
	local out = {
		gui = gui, backdrop = backdrop, panel = panel, state = state, env = env, camera = camera, latest = latest, registered = registered,
		room = panel:FindFirstChild("GalleryRoom"), grid = panel:FindFirstChild("SectionGrid"), quiet = panel:FindFirstChild("QuietTabs"),
		legend = panel:FindFirstChild("RarityLegend"), detail = panel:FindFirstChild("DetailShade"),
		scene = panel:FindFirstChild("SectionScene"), -- the painted section scene (only on when opts.painted)
	}
	if opts.fullScreen then stubs.PanelFullScreen.apply(backdrop, panel, "collection") end -- what PanelTabs.attach does for the six full screen pages
	function out.open() openers.collection() end
	function out.hotspot(id) return out.room:FindFirstChild("Hotspot_" .. id) end
	function out.pick(id) out.hotspot(id):FindFirstChild("Surface").MouseButton1Click:Fire() end
	function out.tiles()
		for _ = 1, 100 do -- the later batches of tiles wait one frame each
			if state.runWaiting() == 0 then break end
		end
		local list = {}
		for _, c in ipairs(out.grid:GetChildren()) do
			if c.ClassName == "TextButton" then list[#list + 1] = c end
		end
		table.sort(list, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		return list
	end
	function out.resize(vpX, vpY)
		local fit = map.ResponsiveLayout.collectionPanel(vpX, vpY)
		camera.ViewportSize = { X = vpX, Y = vpY }
		panel.AbsoluteSize = { X = math.floor(fit.w * vpX), Y = math.floor(fit.h * vpY) }
	end
	function out.step() return steps.collection() end
	out.resize(1280, 720)
	return out
end

return CollectionScene
