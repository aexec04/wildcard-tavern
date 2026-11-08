--[[
	Client/RoadLock.lua
	Shared client helpers for locked roads (Engine/Keys.lua):
	  RoadLock.isLocked(state, stopId)        true when the server says this pending road needs a Key
	  RoadLock.keys(state)                    the player's Key count from the state push
	  RoadLock.pick(stopId, state, parent)    take a road: an open one fires ChooseRoad; a locked one first asks
	                                          "Unlock with a Key?" and only then fires UnlockRoad followed by ChooseRoad
	The server re-checks everything (phase, pending fork, locked, Key available, and ChooseRoad refuses a road that
	is still locked), so this is only the confirm UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CREAM = Color3.fromRGB(250, 235, 200)
local INK = Color3.fromRGB(60, 40, 22)
local GOLD = Color3.fromRGB(222, 182, 104)
local PARCHMENT = Color3.fromRGB(222, 198, 150)

local RoadLock = {}

function RoadLock.isLocked(state, stopId)
	return type(state) == "table" and type(state.roadStatus) == "table" and state.roadStatus[stopId] == "locked"
end

function RoadLock.keys(state)
	return type(state) == "table" and math.floor(tonumber(state.keys) or 0) or 0
end

local function remote(name)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	return folder and folder:FindFirstChild(name)
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function button(parent, text, x, color, textColor)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(x, 0, 1, -14)
	b.Size = UDim2.new(0.42, 0, 0, 40)
	b.BackgroundColor3 = color
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 17
	b.TextColor3 = textColor
	b.TextTransparency = 0
	b.TextStrokeTransparency = 1
	b.ZIndex = 61
	b.Parent = parent
	corner(b, 8)
	return b
end

local confirmGui = nil

-- Small parchment dialog over `parent` (a full-size frame, e.g. the map frame or the Round Select root).
local function ask(parent, stopName, keys, onYes)
	if confirmGui then
		confirmGui:Destroy()
		confirmGui = nil
	end
	local shade = Instance.new("TextButton") -- full-size click sink so nothing behind is pressed
	shade.Name = "UnlockRoadConfirm"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.5
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.ZIndex = 60
	shade.Parent = parent
	confirmGui = shade
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(380, 190)
	box.BackgroundColor3 = PARCHMENT
	box.BorderSizePixel = 0
	box.ZIndex = 61
	box.Parent = shade
	corner(box, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(110, 80, 45)
	stroke.Thickness = 3
	stroke.Parent = box
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 10)
	title.Size = UDim2.new(1, -24, 0, 30)
	title.Text = "🔒 Unlock with a Key?"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = INK
	title.TextTransparency = 0
	title.TextStrokeTransparency = 1
	title.ZIndex = 61
	title.Parent = box
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 46)
	body.Size = UDim2.new(1, -32, 0, 76)
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Font = Enum.Font.GothamMedium
	body.TextSize = 16
	body.TextColor3 = INK
	body.TextTransparency = 0
	body.TextStrokeTransparency = 1
	body.ZIndex = 61
	body.Parent = box
	local can = keys > 0
	body.Text = can
		and string.format("%s needs a Key. One Key opens this road for good. You have %d.", stopName, keys)
		or string.format("%s needs a Key. You have none: win a run or clear a biome for the first time to earn one.", stopName)
	local yes = button(box, can and "Use a Key" or "No Keys", 0.27, can and Color3.fromRGB(86, 140, 70) or Color3.fromRGB(130, 118, 98), CREAM)
	local no = button(box, "Not now", 0.73, Color3.fromRGB(110, 76, 44), CREAM)
	local function close()
		if confirmGui == shade then confirmGui = nil end
		shade:Destroy()
	end
	no.MouseButton1Click:Connect(close)
	shade.MouseButton1Click:Connect(close)
	yes.MouseButton1Click:Connect(function()
		if not can then return end
		close()
		onYes()
	end)
end

-- Take a road. onOpen() runs for a road that needs no Key (fires ChooseRoad itself in the caller).
function RoadLock.pick(stopId, state, parent, stopName, onOpen)
	if not RoadLock.isLocked(state, stopId) then
		onOpen()
		return
	end
	ask(parent, stopName or "This road", RoadLock.keys(state), function()
		local unlock, choose = remote("UnlockRoad"), remote("ChooseRoad")
		if unlock then
			unlock:FireServer(stopId)
		end
		if choose then
			choose:FireServer(stopId) -- RemoteEvents arrive in order: the server opens the road, then walks it
		end
	end)
end

RoadLock.GOLD = GOLD

return RoadLock
