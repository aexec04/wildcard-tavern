--[[
	Client/NewRibbon.lua
	A small "New" ribbon on a tile whose item the player unlocked but has not looked at yet (Engine/NewItems).
	attach(tile, kind, id, state, zIndex) adds it when state.newItems lists the key. The ribbon is a child of the tile (survives
	Clone, never blocks clicks). Hovering or clicking the tile clears it for good: it is hidden at once and the key is sent to the
	server (MarkSeenNew), which checks it against what the profile owns and saves it. No tween, so Calm mode needs nothing extra.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("NewItems"))

local M = {}

local sent = {} -- keys already reported this session

local function report(key)
	if sent[key] then return end
	sent[key] = true
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("MarkSeenNew")
	if remote then remote:FireServer({ key }) end
end

function M.isPending(state, kind, id)
	local key = Items.key(kind, id)
	if sent[key] or type(state) ~= "table" or type(state.newItems) ~= "table" then return false end
	return table.find(state.newItems, key) ~= nil
end

function M.attach(tile, kind, id, state, zIndex)
	if not M.isPending(state, kind, id) then return nil end
	local key = Items.key(kind, id)
	local ribbon = Instance.new("TextLabel")
	ribbon.Name = "NewRibbon"
	ribbon.AnchorPoint = Vector2.new(1, 0)
	ribbon.Position = UDim2.new(1, -4, 0, 4)
	ribbon.Size = UDim2.fromOffset(46, 22)
	ribbon.BackgroundColor3 = Color3.fromRGB(176, 52, 40)
	ribbon.BorderSizePixel = 0
	ribbon.Font = Enum.Font.Merriweather
	ribbon.Text = "New"
	ribbon.TextSize = 15
	ribbon.TextColor3 = Color3.fromRGB(250, 235, 200)
	ribbon.TextTransparency = 0
	ribbon.TextStrokeTransparency = 1
	ribbon.Rotation = 8
	ribbon.ZIndex = zIndex or 60
	ribbon.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = ribbon
	local gold = Instance.new("UIStroke")
	gold.Color = Color3.fromRGB(214, 168, 74)
	gold.Thickness = 1.5
	gold.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gold.Parent = ribbon
	ribbon.Parent = tile
	if tile:IsA("GuiButton") then
		local function viewed()
			if ribbon.Parent then ribbon:Destroy() end
			report(key)
		end
		tile.MouseEnter:Connect(viewed)
		tile.MouseButton1Click:Connect(viewed)
	end
	return ribbon
end

return M
