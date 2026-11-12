--[[
	Client/BoardDrawer.lua
	Slides the whole left HUD (Engine/BoardDrawer.NAMES: painted board, Sidebar rows with the Tips and hint plates, medallion, shadow) off to
	the left, leaving a brass tab handle and a small chip with Score, Tips, Hands and Discards. Click the handle or press Tab (not while a
	text box is focused) to toggle. The choice is remembered for the session and saved as the setting boardCollapsed.

	The pieces are moved by an extra offset on top of whatever other modules write: the same base and applied pattern as Client/PlayMotion's
	layers, so a module that re-places the board while it is away does not pull it back. Roots outside the "playing" phase (Round Select, the
	Counter, Run Over) are put back at once; Client/SidebarSlide owns those. Windows under 900 px keep Client/CompactLayout's own drawer.

	install(root)            builds the handle and the chip (idempotent)
	update(state)            the hub calls this on every render: phase, numbers for the chip
	forceOpen(reason, on)    a reason (tutorial, tooltip) that keeps the board open; the user's choice returns after
	toggle()                 for the handle, the Tab key and DebugGoto
	setCollapsed(on)         DebugGoto drawer:closed and drawer:open
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("BoardDrawer"))
local SidebarMetrics = require(Engine:WaitForChild("SidebarMetrics"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local BoardDrawer = {}

local BRASS = Color3.fromRGB(176, 138, 66)
local DARK = Color3.fromRGB(40, 26, 14)
local CREAM = Color3.fromRGB(250, 240, 220)

local rt = nil -- runtime, built by install
local userCollapsed = false
local forced = {} -- [reason] = true
local playing = false
local numbers = { score = 0, target = 0, tips = 0, hands = 0, discards = 0 }

local function boardWidth(root)
	local size = root.AbsoluteSize
	return SidebarMetrics.width(size.X, size.Y)
end

local function wantCollapsed(root)
	local anyForced = next(forced) ~= nil
	return playing and Rules.collapsed(userCollapsed, anyForced, root.AbsoluteSize.X)
end

-- put every piece at base + (dx, 0); a Position some other module wrote becomes the new base
local function place(dx)
	if not rt then return end
	rt.dx = dx
	for _, name in ipairs(Rules.NAMES) do
		local inst = rt.root:FindFirstChild(name)
		if inst then
			local rec = rt.pieces[inst]
			if not rec then
				rec = { base = inst.Position }
				rt.pieces[inst] = rec
				rt.conns[#rt.conns + 1] = inst:GetPropertyChangedSignal("Position"):Connect(function()
					if rt.placing then return end
					task.defer(function() if rt then place(rt.dx) end end)
				end)
			elseif rec.applied ~= inst.Position then
				rec.base = inst.Position
			end
			rec.applied = rec.base + UDim2.fromOffset(dx, 0)
			rt.placing = true
			inst.Position = rec.applied
			rt.placing = false
		end
	end
end

local function layoutPieces(animate)
	local root = rt.root
	local size = root.AbsoluteSize
	local collapsed = wantCollapsed(root)
	local bw = boardWidth(root)
	local target = collapsed and -Rules.distance(bw) or 0
	local show = playing and Rules.enabled(size.X)
	rt.handle.Visible = show
	rt.chip.Visible = show and collapsed
	if show then
		local hr = Rules.handleRect(size.X, size.Y, bw, collapsed)
		rt.handle.Position = UDim2.fromOffset(hr.x, hr.y)
		rt.handle.Size = UDim2.fromOffset(hr.hit, hr.h)
		rt.arrow.Text = collapsed and ">" or "<"
		local cr = Rules.chipRect(size.X, size.Y)
		rt.chip.Position = UDim2.fromOffset(cr.x, cr.y)
		rt.chip.Size = UDim2.fromOffset(cr.w, cr.h)
	end
	root:SetAttribute("BoardCollapsed", collapsed) -- Client/PlayScenePaint recentres the hand on this
	if not playing then
		rt.tweenId = (rt.tweenId or 0) + 1
		place(0)
		return
	end
	if rt.dx == target then return end
	rt.tweenId = (rt.tweenId or 0) + 1
	local id = rt.tweenId
	if not animate or not ClientSettings.motionAllowed() then
		place(target)
		return
	end
	local from, t0 = rt.dx, os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if rt == nil or rt.tweenId ~= id then conn:Disconnect() return end
		local a = math.min(1, (os.clock() - t0) / Rules.SLIDE_TIME)
		local eased = 1 - (1 - a) * (1 - a) -- Quad Out
		place(math.floor(from + (target - from) * eased + 0.5))
		if a >= 1 then conn:Disconnect() end
	end)
end

local function refreshChip()
	if not rt then return end
	local lines = Rules.chipLines(numbers.score, numbers.target, numbers.tips, numbers.hands, numbers.discards)
	rt.chipText.Text = table.concat(lines, "\n")
end

function BoardDrawer.install(root)
	if rt then return rt end
	rt = { root = root, pieces = setmetatable({}, { __mode = "k" }), conns = {}, dx = 0 }

	local handle = Instance.new("TextButton") -- 48 px hit area, the 36 px brass tab is inside it
	handle.Name = "BoardDrawerHandle"
	handle.Text = ""
	handle.AutoButtonColor = false
	handle.BackgroundTransparency = 1
	handle.BorderSizePixel = 0
	handle.ZIndex = 20
	handle.Visible = false
	handle.Parent = root
	local tab = Instance.new("Frame")
	tab.Name = "Tab"
	tab.Size = UDim2.new(0, Rules.HANDLE.w, 1, 0)
	tab.BackgroundColor3 = BRASS
	tab.BorderSizePixel = 0
	tab.Active = false
	tab.ZIndex = 20
	tab.Parent = handle
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tab
	local stroke = Instance.new("UIStroke")
	stroke.Color = DARK
	stroke.Thickness = 2
	stroke.Parent = tab
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Chevron"
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 24
	arrow.TextColor3 = DARK
	arrow.TextStrokeTransparency = 1
	arrow.TextTransparency = 0
	arrow.Active = false
	arrow.ZIndex = 21
	arrow.Parent = tab
	rt.handle, rt.arrow = handle, arrow
	handle.Activated:Connect(function() BoardDrawer.toggle() end)

	local chip = Instance.new("Frame")
	chip.Name = "BoardDrawerChip"
	chip.BackgroundColor3 = DARK
	chip.BackgroundTransparency = 0.12
	chip.BorderSizePixel = 0
	chip.Active = false
	chip.ZIndex = 20
	chip.Visible = false
	chip.Parent = root
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 10)
	cc.Parent = chip
	local cs = Instance.new("UIStroke")
	cs.Color = BRASS
	cs.Thickness = 2
	cs.Parent = chip
	local text = Instance.new("TextLabel")
	text.Name = "Numbers"
	text.Size = UDim2.new(1, -16, 1, -8)
	text.Position = UDim2.fromOffset(8, 4)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 17
	text.TextColor3 = CREAM
	text.TextStrokeTransparency = 1
	text.TextTransparency = 0
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Active = false
	text.ZIndex = 21
	text.Parent = chip
	rt.chip, rt.chipText = chip, text

	userCollapsed = ClientSettings.getRaw("boardCollapsed") == true
	ClientSettings.onChanged(function(key, value)
		if key == "boardCollapsed" and value ~= userCollapsed then
			userCollapsed = value == true
			if rt then layoutPieces(true) end
		end
	end)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() layoutPieces(false) end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.Tab or UserInputService:GetFocusedTextBox() then return end
		BoardDrawer.toggle()
	end)
	refreshChip()
	return rt
end

function BoardDrawer.update(state)
	if not rt or type(state) ~= "table" then return end
	local nowPlaying = state.phase == "playing"
	numbers.score, numbers.target = state.roundScore, state.targetScore
	numbers.tips, numbers.hands, numbers.discards = state.tips, state.handsRemaining, state.discardsRemaining
	refreshChip()
	if nowPlaying ~= playing then
		playing = nowPlaying
		layoutPieces(false)
	end
end

function BoardDrawer.setCollapsed(on)
	userCollapsed = on == true
	ClientSettings.set("boardCollapsed", userCollapsed)
	if rt then layoutPieces(true) end
end

function BoardDrawer.toggle()
	if not playing then return end
	BoardDrawer.setCollapsed(not userCollapsed)
end

function BoardDrawer.forceOpen(reason, on)
	forced[reason] = on and true or nil
	if rt then layoutPieces(true) end
end

return BoardDrawer
