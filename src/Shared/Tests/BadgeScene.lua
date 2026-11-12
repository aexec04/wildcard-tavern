--[[
	Shared/Tests/BadgeScene.lua
	Test helper: the REAL Badges panel (Client/BadgesPanel.lua with the real BadgeRoom, RoomHotspots and BadgeWall) built on the fake
	Roblox of Tests/FakeGui.lua, the way the client builds it, with the shared tab strip stubbed. The tests then open it, click the
	trophy room's hotspots and look at the medals each wall puts on its furniture.

	BadgeScene.build(opts) -> {
	  gui, backdrop, panel, room, board, quiet, plaque, detail   the instances (room = TrophyRoom, board = WallBoard, quiet = QuietTabs)
	  open()                      what the Collection group tab does (the registered opener)
	  hotspot(shelf)              the Hotspot_<shelf> frame of the room (its .Surface is the TextButton that takes the click)
	  pick(shelf)                 click that hotspot (zooms into the wall)
	  resize(vpX, vpY)            set the window and the panel size the way BadgesPanel does; fires the layout
	  step()                      what Escape does inside the panel (PanelTabs.setStep's function): true when it went back a level
	  state, latest, equipped     FakeGui's state; the table getLatestState answers; the ids EquipBadge was asked for
	}
	opts: badgeIds = { id, ... } (earned), calm
]]

local FakeGui = require(script.Parent.FakeGui)
local Engine = script.Parent.Parent.Engine

local BadgeScene = {}

function BadgeScene.build(opts)
	opts = opts or {}
	local noop = function() end
	local stubs = {}
	local env, state = FakeGui.env({ stubs = stubs })

	local map = {}
	for _, name in ipairs({ "Badges", "BadgeWallLayout", "BadgeWallArt", "BadgeSocketArt", "BadgeRoomLayout", "RoomGrid", "ContentArt", "ResponsiveLayout", "PanelLayout" }) do
		map[name] = require(Engine[name])
	end
	if opts.wallArt then map.BadgeWallArt = opts.wallArt end -- tests can record the painted scene ids
	local engineFolder = FakeGui.folder(map)
	local equipped = {}
	local equipRemote = { FireServer = function(_, ...) equipped[#equipped + 1] = { ... } end }
	state.services.ReplicatedStorage = { WaitForChild = function(_, name)
		if name == "Remotes" then
			return { WaitForChild = function() return equipRemote end }
		end
		return { WaitForChild = function() return engineFolder end }
	end }

	local camera = { ViewportSize = { X = 1280, Y = 720 }, GetPropertyChangedSignal = function() return FakeGui.signal() end }
	env.workspace = { CurrentCamera = camera }

	local openers, steps = {}, {}
	stubs.ClientSettings = { get = function(key) return opts.calm == true and key == "reduceShake" end }
	stubs.OverlayManager = {
		register = noop, registerOpener = function(id, fn) openers[id] = fn end, closeAllExcept = noop, close = noop, open = noop,
	}
	stubs.PatronPlaque = { applyById = function(frame) local img = FakeGui.new("ImageLabel"); img.Parent = frame; return img end }
	stubs.RarityFrame = { apply = noop }
	stubs.PanelTabs = { attach = noop, setStep = function(id, fn) steps[id] = fn end }
	stubs.PanelFullScreen = FakeGui.load("src/Client/PanelFullScreen.lua", env)
	stubs.RoomHotspots = FakeGui.load("src/Client/RoomHotspots.lua", env)
	stubs.BadgeRoom = FakeGui.load("src/Client/BadgeRoom.lua", env)
	stubs.BadgeWall = FakeGui.load("src/Client/BadgeWall.lua", env)

	local latest = { badgeIds = opts.badgeIds or {}, store = {} }
	local gui = FakeGui.new("ScreenGui")
	local deps = {
		screenGui = gui,
		polishPanel = noop, polishButton = noop, roundCorner = function(inst) local c = FakeGui.new("UICorner"); c.Parent = inst end,
		addSoftShadow = noop, playClickSfx = noop, addButtonHoverScale = noop, addTooltip = noop,
		getLatestState = function() return latest end,
		popIn = function(backdrop) backdrop.Visible = true end, popOut = function(backdrop) backdrop.Visible = false end,
		openButton = FakeGui.new("TextButton"), StateUpdatedRemote = { OnClientEvent = FakeGui.signal() },
	}
	local BadgesPanel = FakeGui.load("src/Client/BadgesPanel.lua", env)
	BadgesPanel(deps)

	local backdrop = assert(gui:FindFirstChild("BadgesBackdrop"), "the Badges panel builds its backdrop")
	local panel = backdrop:GetChildren()[1]
	local out = {
		gui = gui, backdrop = backdrop, panel = panel, state = state, env = env, camera = camera, latest = latest, equipped = equipped,
		room = panel:FindFirstChild("TrophyRoom"), board = panel:FindFirstChild("WallBoard"), quiet = panel:FindFirstChild("QuietTabs"),
		plaque = panel:FindFirstChild("HeaderPlate"), detail = panel:FindFirstChild("BadgeDetail"),
	}
	function out.open() openers.badges() end
	function out.hotspot(shelf) return out.room:FindFirstChild("Hotspot_" .. shelf) end
	function out.pick(shelf) out.hotspot(shelf):FindFirstChild("Surface").MouseButton1Click:Fire() end
	function out.step() return steps.badges() end
	function out.resize(vpX, vpY)
		local fit = map.ResponsiveLayout.badgesPanel(vpX, vpY)
		camera.ViewportSize = { X = vpX, Y = vpY }
		local W, H = fit.w, math.max(fit.h, math.floor(vpY * 0.84))
		panel.AbsoluteSize = { X = W, Y = H }
		local area = map.BadgeRoomLayout.panel(W, H).area
		out.board.AbsoluteSize = { X = area.w, Y = area.h }
		out.room.AbsoluteSize = { X = area.w, Y = area.h }
	end
	out.resize(1280, 720)
	return out
end

return BadgeScene
