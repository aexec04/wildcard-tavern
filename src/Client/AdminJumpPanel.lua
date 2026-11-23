--[[
	Client/AdminJumpPanel.lua
	Studio-only owner tool: a collapsed tab at the right screen edge that opens a scrolling list of jump buttons (one per
	Engine/AdminJumpKeys entry). A click sets the DebugGoto attribute (cleared first, then set after a short wait so the same
	key can repeat), starting a run first when none is live. Built ONLY when RunService:IsStudio(). Prints "[AdminJump] <key>".
	Sits below the toasts (Layers.effect + 20 vs + 40) in a narrow strip on the right edge, clear of Play Hand and Discard.
	AdminJumpPanel.init(gui, getState)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AdminJumpPanel = {}

local Layers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local Z = Layers.effect + 20 -- under the corner toasts (effect + 40)

function AdminJumpPanel.init(gui, getState)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Keys = require(Engine:WaitForChild("AdminJumpKeys"))
	if not Keys.shouldBuild(RunService:IsStudio()) then return nil end
	local player = Players.LocalPlayer
	local ids = {}
	pcall(function() ids.boss = require(Engine.BossRounds).Definitions[1].id end)
	pcall(function() ids.recipe = require(Engine.Recipes).HouseRecipes[1].id end)

	local PANEL_W, TAB_W = 190, 44
	local root = Instance.new("Frame")
	root.Name = "AdminJumpPanel"
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Position = UDim2.new(1, 0, 0.5, 0)
	root.Size = UDim2.new(0, TAB_W, 0, 44)
	root.BackgroundTransparency = 1
	root.ZIndex = Z
	root.Parent = gui

	local list = Instance.new("Frame") -- the open panel
	list.Name = "Panel"
	list.AnchorPoint = Vector2.new(1, 0.5)
	list.Position = UDim2.new(1, -TAB_W, 0.5, 0)
	list.Size = UDim2.new(0, PANEL_W, 0, 360)
	list.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	list.BorderSizePixel = 0
	list.Visible = false
	list.ZIndex = Z
	list.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -48)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = Z
	scroll.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = scroll

	local function styleButton(b, text)
		b.BackgroundColor3 = Color3.fromRGB(86, 58, 36)
		b.BorderSizePixel = 0
		b.TextColor3 = Color3.fromRGB(250, 240, 220)
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 16
		b.Text = text
		b.AutoButtonColor = true
		b.ZIndex = Z
	end

	local token = 0
	local function setKey(value)
		player:SetAttribute("DebugGoto", nil)
		task.wait(Keys.REPEAT_GAP)
		player:SetAttribute("DebugGoto", value)
	end
	local function jump(entry)
		token += 1
		local mine = token
		task.spawn(function()
			local state = getState and getState()
			if entry.needsRun and not (state and state.night ~= nil) then
				setKey("round1") -- no live run yet: start one first
				local t0 = os.clock()
				while os.clock() - t0 < Keys.RUN_WAIT do
					local st = getState and getState()
					if st and st.night ~= nil and st.phase == "playing" then break end
					task.wait(0.2)
				end
				if token ~= mine then return end
			end
			setKey(entry.value)
			print("[AdminJump] " .. entry.value)
		end)
	end

	for i, entry in ipairs(Keys.list(ids)) do
		local b = Instance.new("TextButton")
		b.Name = "Jump_" .. entry.value
		b.LayoutOrder = i
		b.Size = UDim2.new(1, -10, 0, Keys.ROW_HEIGHT)
		styleButton(b, entry.label)
		b.Parent = scroll
		b.Activated:Connect(function() jump(entry) end)
	end

	local hide = Instance.new("TextButton") -- hide toggle: removes the whole tab until the next Play
	hide.Name = "Hide"
	hide.AnchorPoint = Vector2.new(0, 1)
	hide.Position = UDim2.new(0, 0, 1, 0)
	hide.Size = UDim2.new(1, 0, 0, 44)
	styleButton(hide, "Hide tab")
	hide.Parent = list
	hide.Activated:Connect(function() root.Visible = false end)

	local tab = Instance.new("TextButton")
	tab.Name = "Tab"
	tab.AnchorPoint = Vector2.new(1, 0.5)
	tab.Position = UDim2.new(1, 0, 0.5, 0)
	tab.Size = UDim2.new(0, TAB_W, 0, 44)
	styleButton(tab, "Go")
	tab.Parent = root
	tab.Activated:Connect(function() list.Visible = not list.Visible end)
	return root
end

return AdminJumpPanel
