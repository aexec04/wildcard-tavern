--[[
	Client/BoardDrawer.lua
	The player moves the whole left HUD (Engine/BoardDrawer.NAMES: painted board, Sidebar rows with the Tips and hint plates, medallion,
	shadow) out of the way by pressing on the board background and dragging it sideways. Past about 40 percent of the way it settles away to
	the left (0.2 s), leaving a 28 px strip of its wood post with a faint grip mark; dragging the strip back, or a plain click on it, opens it
	again. No handle tab and no info chip. Tab still toggles (not while a text box is focused). The choice is saved as the setting
	boardCollapsed. A drag starts only on input no button took, so a Patron ring, the Blessing row or Play Hand never starts or receives one.

	The pieces are moved by an extra offset on top of whatever other modules write: the same base and applied pattern as Client/PlayMotion's
	layers, so a module that re-places the board while it is away does not pull it back. Roots outside the "playing" phase (Round Select, the
	Counter, Run Over) are put back at once; Client/SidebarSlide owns those. Windows under 900 px keep Client/CompactLayout's own drawer
	(not draggable).

	install(root)            builds the strip and the drag input (idempotent)
	update(state)            the hub calls this on every render: phase
	forceOpen(reason, on)    a reason (tutorial, tooltip) that keeps the board open; the user's choice returns after
	toggle()                 for the Tab key and DebugGoto
	setCollapsed(on)         DebugGoto drawer:closed and drawer:open
	While a drag is on, the root has the attribute BoardDragging = true.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("BoardDrawer"))
local SidebarMetrics = require(Engine:WaitForChild("SidebarMetrics"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local BoardDrawer = {}

local BRASS = Color3.fromRGB(176, 138, 66)

local rt = nil -- runtime, built by install
local userCollapsed = false
local forced = {} -- [reason] = true
local playing = false

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

-- the board's rect in root coordinates at its open position (the sliding offset removed)
local function boardRect()
	local board = rt.root:FindFirstChild("SidebarBoard")
	if not board then return nil end
	local rp = board.AbsolutePosition - rt.root.AbsolutePosition
	return { x = rp.X - (rt.dx or 0), y = rp.Y, w = board.AbsoluteSize.X, h = board.AbsoluteSize.Y }
end

local function layoutPieces(animate)
	local root = rt.root
	local size = root.AbsoluteSize
	local collapsed = wantCollapsed(root)
	local bw = boardWidth(root)
	local target = collapsed and -Rules.distance(bw) or 0
	local br = boardRect()
	rt.strip.Visible = playing and collapsed and Rules.enabled(size.X) and br ~= nil
	if rt.strip.Visible then
		local sr = Rules.stripRect(size.Y, br.y, br.h)
		rt.strip.Position = UDim2.fromOffset(sr.x, sr.y)
		rt.strip.Size = UDim2.fromOffset(sr.w, sr.h)
	end
	root:SetAttribute("BoardCollapsed", collapsed) -- Client/PlayScenePaint recentres the hand on this
	if not playing then
		rt.tweenId = (rt.tweenId or 0) + 1
		place(0)
		return
	end
	if rt.drag then return end -- the pointer owns the position until release
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

local function pointerPos(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function beginDrag(input, collapsedAtStart)
	if not rt or not playing or not Rules.enabled(rt.root.AbsoluteSize.X) or next(forced) ~= nil then return end
	rt.tweenId = (rt.tweenId or 0) + 1 -- stop any slide in flight
	rt.drag = { startX = input.Position.X, startDx = rt.dx, startCollapsed = collapsedAtStart, moved = false }
	rt.root:SetAttribute("BoardDragging", true)
end

local function moveDrag(input)
	local d = rt and rt.drag
	if not d then return end
	local delta = input.Position.X - d.startX
	if not d.moved and not Rules.isDrag(delta) then return end
	d.moved = true
	place(Rules.dragDx(d.startDx, delta, boardWidth(rt.root)))
end

local function endDrag()
	local d = rt and rt.drag
	if not d then return end
	rt.drag = nil
	rt.root:SetAttribute("BoardDragging", false)
	local collapsed
	if d.moved then
		collapsed = Rules.settle(d.startCollapsed, rt.dx, boardWidth(rt.root))
	elseif d.startCollapsed then
		collapsed = false -- a plain click on the strip brings the board back
	else
		return -- a press on the board that went nowhere
	end
	pcall(function() require(script.Parent.Cue).play("button_click", 1) end) -- the click cue only on settle
	BoardDrawer.setCollapsed(collapsed)
end

function BoardDrawer.install(root)
	if rt then return rt end
	rt = { root = root, pieces = setmetatable({}, { __mode = "k" }), conns = {}, dx = 0 }

	-- the 28 px strip of the board's wood post that stays on the left edge while the board is away
	local strip = Instance.new("TextButton")
	strip.Name = "BoardDrawerStrip"
	strip.Text = ""
	strip.AutoButtonColor = false
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ZIndex = 20
	strip.Visible = false
	strip.Parent = root
	for n = 1, 3 do -- a faint grip mark: three short dashes
		local dash = Instance.new("Frame")
		dash.Name = "Grip" .. n
		dash.AnchorPoint = Vector2.new(0.5, 0.5)
		dash.Position = UDim2.new(0.5, 0, 0.5, (n - 2) * 7)
		dash.Size = UDim2.fromOffset(12, 3)
		dash.BackgroundColor3 = BRASS
		dash.BackgroundTransparency = 0.45
		dash.BorderSizePixel = 0
		dash.Active = false
		dash.ZIndex = 21
		dash.Parent = strip
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 2)
		c.Parent = dash
	end
	rt.strip = strip
	strip.InputBegan:Connect(function(input)
		if isPress(input) then beginDrag(input, true) end
	end)

	userCollapsed = ClientSettings.getRaw("boardCollapsed") == true
	ClientSettings.onChanged(function(key, value)
		if key == "boardCollapsed" and value ~= userCollapsed then
			userCollapsed = value == true
			if rt then layoutPieces(true) end
		end
	end)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() layoutPieces(false) end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Tab then
			if processed or UserInputService:GetFocusedTextBox() then return end
			BoardDrawer.toggle()
			return
		end
		if processed or not isPress(input) or rt.dx ~= 0 or wantCollapsed(root) then return end
		local br = boardRect()
		local pos = pointerPos(input)
		if br and pos.X >= br.x and pos.X <= br.x + br.w and pos.Y >= br.y and pos.Y <= br.y + br.h then
			beginDrag(input, false) -- on the board background: no button took the press
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then moveDrag(input) end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then endDrag() end
	end)
	return rt
end

function BoardDrawer.update(state)
	if not rt or type(state) ~= "table" then return end
	local nowPlaying = state.phase == "playing"
	if nowPlaying ~= playing then
		playing = nowPlaying
		if rt.drag then
			rt.drag = nil
			rt.root:SetAttribute("BoardDragging", false)
		end
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
