--[[
	Client/PlayScenePaint.lua
	The painted play table (art key play_table_front_b): a bottom anchored, full width, never stretched foreground above the
	scene and below the hand and every other UI, with the hand row standing on its rail groove and the Actions row on the
	wooden front. Numbers come from Engine/PlayTableLayout (pure, tested). Gameplay logic, keys and hit areas are untouched:
	only the position of HandFrame and Actions changes, and only while the picture has loaded and the window is at least
	900 px wide. Anything else (no id, load failure, phone) leaves the old layout and the code-drawn hand tray as they are.

	install{ root, handFrame, actionFrame, SIDEBAR_WIDTH } -> { isPainted() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayTableLayout = require(Engine:WaitForChild("PlayTableLayout"))
local R = require(Engine:WaitForChild("ResponsiveLayout"))

local PlayScenePaint = {}

function PlayScenePaint.install(deps)
	local root, handFrame, actionFrame = deps.root, deps.handFrame, deps.actionFrame
	local sidebarW = deps.SIDEBAR_WIDTH or R.SIDEBAR_W
	local okArt, art = pcall(function() return require(Engine:WaitForChild("PlaySceneArt")) end)
	local id = okArt and type(art) == "table" and art.play_table_front_b or nil
	if not id or id == "" then return { isPainted = function() return false end } end

	local image = Instance.new("ImageLabel")
	image.Name = "PlayTableFront"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Active = false
	image.Image = id
	image.ScaleType = Enum.ScaleType.Stretch -- the rect already has the picture's own aspect (PlayTableLayout.map)
	image.ZIndex = 0 -- created after the scene stack and TableLook, so it draws above them; hand and HUD are >= 1
	image.Visible = false
	image.Parent = root

	local loaded, painted = false, false
	local platesId = art.play_plates_b
	local PlayPlates = require(script.Parent.PlayPlates)
	local function plates(p)
		pcall(function() PlayPlates.apply(actionFrame, p, platesId) end) -- a failure leaves the flat buttons
	end

	local function apply()
		local size = root.AbsoluteSize
		local p = loaded and PlayTableLayout.placement(size.X, size.Y, sidebarW + 20, R.PILE_RESERVE) or nil
		if p then
			painted = true
			local m = p.map.image
			image.Position = UDim2.fromOffset(m.x, m.y)
			image.Size = UDim2.fromOffset(m.w, m.h)
			image.Visible = handFrame.Visible
			handFrame:SetAttribute("PaintedRail", true) -- CardFace hides its code-drawn tray
			handFrame.Position = UDim2.fromOffset(p.hand.x, p.hand.y)
			handFrame.Size = UDim2.fromOffset(p.hand.w, p.hand.h)
			actionFrame.Position = UDim2.fromOffset(p.actions.x, p.actions.y)
			actionFrame.Size = UDim2.fromOffset(p.actions.w, p.actions.h)
			plates(p)
		elseif painted then
			-- leaving the painted layout: back to the flat one (a narrow window is then handled by CompactLayout)
			painted = false
			image.Visible = false
			handFrame:SetAttribute("PaintedRail", nil)
			plates(nil)
			if size.X >= PlayTableLayout.MIN_W then
				handFrame.Position = UDim2.new(0, sidebarW + 20, 1, -272)
				handFrame.Size = UDim2.new(1, -(sidebarW + 40 + R.PILE_RESERVE), 0, 176)
				actionFrame.Position = UDim2.new(0, sidebarW + 20, 1, -80)
				actionFrame.Size = UDim2.new(1, -(sidebarW + 40 + R.PILE_RESERVE), 0, R.ACTION_H)
			end
		end
	end

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	handFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if painted then image.Visible = handFrame.Visible end
	end)
	-- CompactLayout re-applies its own numbers on viewport changes; put the painted ones back right after
	handFrame:GetPropertyChangedSignal("Position"):Connect(apply)
	handFrame:GetPropertyChangedSignal("Size"):Connect(apply)
	actionFrame:GetPropertyChangedSignal("Position"):Connect(apply)

	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({ image }) end)
		loaded = image.IsLoaded == true
		if loaded then apply() end
	end)

	return { isPainted = function() return painted end }
end

return PlayScenePaint
