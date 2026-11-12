--[[
	Client/PreviewMode.lua
	Card Set Preview is look-only (Engine/PreviewGuard has the rules; the server rejects every run remote while the player's attribute
	PreviewMode is true). While it runs:
	  * the hub's render() passes every state through filter(): a playing round shows a fixed sample hand and sample numbers
	    (Night 1 Round 1, 0 / 300), the real state is kept and drawn again, exactly as it was, on finish();
	  * transparent shields sit over the hand, the action plates (dimmed 40 percent, "Preview only" on hover) and the left board, so no card,
	    plate or Patron seat takes a click or lifts on hover. Shields are children of the root with their rect copied from the target (never
	    inside a layout parent);
	  * the server is told through the PreviewMode remote and told again on finish.

	begin(root)     start (idempotent)        finish()   end and redraw the real state
	filter(state)   -> the state to draw      isActive()
	setRenderer(fn) the hub's render function
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Guard = require(Engine:WaitForChild("PreviewGuard"))

local PreviewMode = {}

local active = false
local realState = nil
local renderer = nil
local shields = {} -- { { target, shield, dim, tip } }
local conn = nil

local TARGETS = { "HandFrame", "Actions", "Sidebar" } -- names of root children; the first match of each is shielded

local function fireServer(on)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("PreviewMode")
	if remote then remote:FireServer(on == true) end
end

local function makeShield(root, target, isActions)
	local shield = Instance.new("TextButton")
	shield.Name = "PreviewShield_" .. target.Name
	shield.Text = ""
	shield.AutoButtonColor = false
	shield.BackgroundTransparency = 1
	shield.BorderSizePixel = 0
	shield.Active = true
	shield.ZIndex = 50
	shield.Parent = root
	local rec = { target = target, shield = shield }
	if isActions then
		local dim = Instance.new("Frame")
		dim.Name = "PreviewDim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 1 - Guard.DIM
		dim.BorderSizePixel = 0
		dim.Active = false
		dim.ZIndex = 50
		dim.Parent = shield
		local tip = Instance.new("TextLabel")
		tip.Name = "PreviewTip"
		tip.Size = UDim2.fromOffset(150, 28)
		tip.AnchorPoint = Vector2.new(0.5, 1)
		tip.Position = UDim2.new(0.5, 0, 0, -6)
		tip.BackgroundColor3 = Color3.fromRGB(40, 26, 14)
		tip.BackgroundTransparency = 0.1
		tip.BorderSizePixel = 0
		tip.Font = Enum.Font.GothamBold
		tip.TextSize = 15
		tip.TextColor3 = Color3.fromRGB(250, 240, 220)
		tip.TextTransparency = 0
		tip.TextStrokeTransparency = 1
		tip.Text = Guard.PLATE_TIP
		tip.Visible = false
		tip.Active = false
		tip.ZIndex = 52
		tip.Parent = shield
		shield.MouseEnter:Connect(function() tip.Visible = true end)
		shield.MouseLeave:Connect(function() tip.Visible = false end)
		rec.dim, rec.tip = dim, tip
	end
	return rec
end

local function sync(root)
	local origin = root.AbsolutePosition
	for _, rec in ipairs(shields) do
		local t, s = rec.target, rec.shield
		if t.Parent then
			s.Visible = t.Visible
			s.Position = UDim2.fromOffset(t.AbsolutePosition.X - origin.X, t.AbsolutePosition.Y - origin.Y)
			s.Size = UDim2.fromOffset(t.AbsoluteSize.X, t.AbsoluteSize.Y)
		else
			s.Visible = false
		end
	end
end

function PreviewMode.isActive() return active end

function PreviewMode.setRenderer(fn) renderer = fn end

function PreviewMode.filter(state)
	realState = state -- always remembered, so finish() can draw the real run again
	if not active then return state end
	return Guard.sampleState(state)
end

function PreviewMode.begin(root)
	if active then return end
	active = true
	fireServer(true)
	for _, name in ipairs(TARGETS) do
		local target = root:FindFirstChild(name)
		if target then shields[#shields + 1] = makeShield(root, target, name == "Actions") end
	end
	conn = RunService.RenderStepped:Connect(function() sync(root) end)
	sync(root)
	if renderer and realState then pcall(renderer, realState) end -- draw the sample at once
end

function PreviewMode.finish()
	if not active then return end
	active = false
	if conn then conn:Disconnect() conn = nil end
	for _, rec in ipairs(shields) do rec.shield:Destroy() end
	shields = {}
	fireServer(false)
	local real = realState
	if renderer and real then pcall(renderer, real) end -- the real run, exactly as it was
end

return PreviewMode
