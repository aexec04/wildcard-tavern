--[[
	Client/FirstTimeHints.lua
	First time hints (Engine/Hints.lua): one small painted bubble at a time, an icon and at most 12 words, with an arrow
	that points at its target. It never blocks input (only the bubble itself takes a click, to dismiss it), disappears on
	click or after Hints.SHOW_SECONDS, never shows during the forced tutorial, and each hint is reported to the server
	(remote HintSeen) the moment it is shown so it never appears twice. Settings > Replay Hints clears the set.

	init(screenGui) once from the hub; update(state) from render() inside a pcall.
	Targets are resolved by name under the ScreenGui (TARGET_NAMES). A target that is not found simply gets no arrow and
	the bubble sits at the bottom centre, so a renamed element can never break a hint.
]]

local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Hints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Hints"))
local ClientSettings = require(script.Parent.ClientSettings)

local FirstTimeHints = {}

local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local HIGHLIGHT = "#FFD27A"

-- hint target key -> names of GuiObjects to look for (first one found wins)
local TARGET_NAMES = {
	score = { "SidebarBoard" },
	patrons = { "SidebarBoard" },
	tips = { "SidebarBoard" },
	boss = { "BossFightHost" },
	stakes = { "RunSetupBackdrop" },
	quests = { "QuestsBackdrop" },
	season = { "SeasonBackdrop" },
}

local gui
local bubble
local shownId = nil
local localSeen = {} -- hints shown this session, so nothing repeats before the server state echoes back
local token = 0
local seenRemote

local function findTarget(key)
	for _, name in ipairs(TARGET_NAMES[key] or {}) do
		local obj = gui:FindFirstChild(name, true)
		if obj and obj:IsA("GuiObject") and obj.Visible then
			return obj
		end
	end
	return nil
end

-- "[Chips] times [Mult]" -> rich text with the marked words highlighted
local function richText(text)
	return (text:gsub("%[(.-)%]", '<font color="' .. HIGHLIGHT .. '"><b>%1</b></font>'))
end

local function hide()
	token = token + 1
	if bubble then
		bubble.Visible = false
	end
	shownId = nil
end

local function build()
	bubble = Instance.new("TextButton")
	bubble.Name = "FirstTimeHint"
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Size = UDim2.fromOffset(340, 64)
	bubble.BackgroundColor3 = Color3.fromRGB(238, 222, 186) -- Concept T parchment, dark ink text
	bubble.BorderSizePixel = 0
	bubble.AutoButtonColor = false
	bubble.Text = ""
	bubble.Visible = false
	bubble.ZIndex = Layers.effect + 80
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bubble

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(44, 44)
	icon.Position = UDim2.fromOffset(10, 10)
	icon.TextSize = 30
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = Color3.fromRGB(46, 32, 20)
	icon.TextTransparency = 0
	icon.TextStrokeTransparency = 1
	icon.ZIndex = Layers.effect + 81
	icon.Parent = bubble

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -66, 1, -12)
	text.Position = UDim2.fromOffset(58, 6)
	text.TextSize = 16
	text.Font = Enum.Font.GothamMedium
	text.TextColor3 = Color3.fromRGB(46, 32, 20)
	text.TextTransparency = 0
	text.TextStrokeTransparency = 1
	text.TextWrapped = true
	text.RichText = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.ZIndex = Layers.effect + 81
	text.Parent = bubble

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Size = UDim2.fromOffset(30, 22)
	arrow.Position = UDim2.new(0.5, 0, 1, -4)
	arrow.TextSize = 22
	arrow.Font = Enum.Font.GothamBold
	arrow.TextColor3 = Color3.fromRGB(150, 100, 30)
	arrow.TextTransparency = 0
	arrow.TextStrokeTransparency = 1
	arrow.Text = "▼"
	arrow.Visible = false
	arrow.ZIndex = Layers.effect + 81
	arrow.Parent = bubble

	bubble.MouseButton1Click:Connect(hide)
	pcall(function() -- a small X on the corner, the same as every tip card
		require(script.Parent.CloseX).attach(bubble, hide, { inset = -10, top = -16, z = 40 })
	end)
end

local function show(hint)
	if not bubble then
		build()
	end
	shownId = hint.id
	localSeen[hint.id] = true
	token = token + 1
	local myToken = token
	if seenRemote then
		seenRemote:FireServer(hint.id) -- shown once, ever: the server stores it before the player can even dismiss it
	end
	bubble.Icon.Text = hint.icon
	bubble.Text.Text = richText(hint.text)

	-- place: above the target when there is one (arrow points down at it), else bottom centre
	local target = findTarget(hint.target)
	local view = gui.AbsoluteSize
	if target then
		local pos, size = target.AbsolutePosition, target.AbsoluteSize
		local x = math.clamp(pos.X + size.X / 2, 190, math.max(190, view.X - 190))
		local y = math.max(90, pos.Y - 34)
		bubble.Position = UDim2.fromOffset(x, y)
		bubble.Arrow.Visible = true
	else
		bubble.Position = UDim2.new(0.5, 0, 1, -110)
		bubble.Arrow.Visible = false
	end
	bubble.Visible = true
	pcall(function() require(script.Parent.Cue).play("chip", 0.8) end)
	if ClientSettings.get("reduceShake") ~= true then
		bubble.BackgroundTransparency = 1
		TweenService:Create(bubble, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
	else
		bubble.BackgroundTransparency = 0
	end
	task.delay(Hints.SHOW_SECONDS, function()
		if token == myToken then
			hide()
		end
	end)
end

function FirstTimeHints.init(screenGui)
	gui = screenGui
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	seenRemote = remotes and remotes:FindFirstChild("HintSeen")
end

-- Called from render with the latest state.
function FirstTimeHints.update(state)
	if not gui or type(state) ~= "table" then
		return
	end
	if ClientSettings.get("roundHints") == false then
		if shownId then hide() end -- the Hints toggle is off: no tip of any kind
		return
	end
	if shownId then
		return -- one bubble at a time
	end
	-- the server's seen set plus what this session already showed
	local seen = {}
	for id in pairs(state.hintsSeen or {}) do seen[id] = true end
	for id in pairs(localSeen) do seen[id] = true end
	local function open(name)
		local f = gui:FindFirstChild(name)
		return f ~= nil and f:IsA("GuiObject") and f.Visible == true
	end
	local ctx = { runSetupOpen = open("RunSetupBackdrop"), questsOpen = open("QuestsBackdrop"), seasonOpen = open("SeasonBackdrop") }
	local hint = Hints.dueFor(state, seen, ctx)
	if hint then
		show(hint)
	end
end

-- Settings > Replay Hints: forget this session's memory (the server clears the saved set).
function FirstTimeHints.replay()
	localSeen = {}
	hide()
end

pcall(function()
	ClientSettings.onChanged(function(key, value) if key == "roundHints" and value == false and shownId then hide() end end)
end)

return FirstTimeHints
