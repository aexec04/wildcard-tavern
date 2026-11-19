--[[
	Client/CornerDock.lua
	The only writer of the corner icon dock's (CornerIconRow) Visible. The dock is hidden while a registered full screen scene or account
	page is open (every PanelTabs page, the Tavern Map), while Round Select is up and while the Counter is open, and shown otherwise. That is recomputed from the
	live Visible of the registered backdrops each time anything changes, so open and close in any order (tab switch, Escape, a page opening
	on top of another, a run starting) cannot leave the dock hidden. A slow safety loop recomputes it too, so a missed signal heals itself.

	register(backdrop)    a backdrop whose Visible hides the dock (idempotent; recomputes on every change of its Visible)
	refresh(anyInstance)  recompute now (any instance inside the GameUI ScreenGui)
	isShown()             the last computed answer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("DockRules"))

local CornerDock = {}

local backdrops = {} -- [backdrop] = true
local anchor = nil -- an instance inside the ScreenGui, used to find the dock
local shown = true
local looping = false
local watchedCounter = nil -- the Counter frame whose Visible is listened to
local SAFETY_SECONDS = 0.5

local function findRow()
	if not anchor or not anchor.Parent then return nil, nil end
	local gui = anchor
	while gui and gui.ClassName ~= "ScreenGui" and gui.ClassName ~= "SurfaceGui" and gui.ClassName ~= "BillboardGui" do
		gui = gui.Parent
	end
	local row = gui and gui:FindFirstChild("CornerIconRow", true)
	if row and row:IsA("GuiObject") then return row, row.Parent end
	return nil, nil
end

local function anyPanelOpen()
	for backdrop in pairs(backdrops) do
		if backdrop.Parent == nil then
			backdrops[backdrop] = nil
		elseif backdrop.Visible then
			return true
		end
	end
	return false
end

function CornerDock.refresh(any)
	if any then anchor = any end
	local row, parent = findRow()
	if not row then return end
	local roundSelect = (parent ~= nil and parent:GetAttribute("BannerAtBottom") == true)
		or (anchor.Parent ~= nil and anchor.Parent:GetAttribute("BannerAtBottom") == true) -- RoundSelect sets it on the HUD root
	-- The Counter (the "Shop" frame beside the dock) is a full screen scene drawn over the dock: hidden under it, so the
	-- icons take no pointer there. Its Visible is listened to, so the dock goes and comes back in the same frame.
	local counter = parent ~= nil and parent:FindFirstChild("Shop") or nil
	if counter and counter ~= watchedCounter then
		watchedCounter = counter
		counter:GetPropertyChangedSignal("Visible"):Connect(function() CornerDock.refresh() end)
	end
	shown = Rules.visible({ panelOpen = anyPanelOpen(), roundSelect = roundSelect, counter = counter ~= nil and counter.Visible == true })
	if row.Visible ~= shown then row.Visible = shown end
	pcall(function() require(script.Parent.FxLoop).setOverlay(not shown) end) -- looping effects rest under a full screen page
	pcall(function() require(script.Parent.PatronRow).refresh() end) -- the Patron Row hides under the same pages
end

local function startSafetyLoop()
	if looping then return end
	looping = true
	task.spawn(function()
		while anchor and anchor.Parent do
			task.wait(SAFETY_SECONDS)
			pcall(CornerDock.refresh)
		end
		looping = false
	end)
end

function CornerDock.register(backdrop)
	anchor = anchor or backdrop
	if backdrops[backdrop] then return end
	backdrops[backdrop] = true
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function() CornerDock.refresh(backdrop) end)
	CornerDock.refresh(backdrop)
	startSafetyLoop()
end

function CornerDock.isShown() return shown end

return CornerDock
