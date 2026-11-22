--[[
	Client/MenuTicker.lua
	A slim strip on the main menu (Engine/MenuTicker.lua): today's best run from the Daily board with the name and flair,
	about how many runs were played today, and a "Daily board" button. Falls back to a flavor line when the board is not
	available. The server caches the numbers for a minute (remote GetMenuTicker), and this strip asks again only
	when the menu is shown and the last answer is older than that.

	attach(parent, layoutOrder) -> the Daily board button (so the hub can wire it to the leaderboard overlay)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuTicker = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MenuTicker"))

local Ticker = {}

local PARCHMENT = Color3.fromRGB(196, 168, 120) -- darker parchment, not a pasted cream bar
local GOLD = Color3.fromRGB(222, 182, 104)
local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(86, 58, 34)

function Ticker.attach(parent, layoutOrder)
	local frame = Instance.new("Frame")
	frame.Name = "MenuTicker"
	frame.Size = UDim2.fromOffset(460, 98) -- text on top, the best line, the Daily board button on its own row below
	frame.LayoutOrder = layoutOrder
	frame.BackgroundColor3 = PARCHMENT
	frame.ZIndex = 10
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.fromOffset(30, 40)
	icon.Position = UDim2.fromOffset(6, 2)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 20
	icon.TextColor3 = INK
	icon.TextTransparency = 0
	icon.TextStrokeTransparency = 1
	icon.Text = "🏆"
	icon.ZIndex = 11
	icon.Parent = frame

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, -46, 0, 40) -- full width above the button row: nothing can sit on its second line
	text.Position = UDim2.fromOffset(38, 2)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 15
	text.TextColor3 = INK
	text.TextTransparency = 0
	text.TextStrokeTransparency = 1
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = MenuTicker.FlavorLines[1]
	text.ZIndex = 11
	text.Parent = frame

	local best = Instance.new("TextLabel") -- Best Night and best hand so far (Engine/BestLine.lua), hidden until there is one
	best.Name = "BestLine"
	best.Size = UDim2.new(1, -150, 0, 28)
	best.AnchorPoint = Vector2.new(0, 1)
	best.Position = UDim2.new(0, 10, 1, -6)
	best.BackgroundTransparency = 1
	best.Font = Enum.Font.GothamMedium
	best.TextSize = 15
	best.TextColor3 = INK
	best.TextTransparency = 0
	best.TextStrokeTransparency = 1
	best.TextXAlignment = Enum.TextXAlignment.Left
	best.TextTruncate = Enum.TextTruncate.AtEnd
	best.Text = ""
	best.Visible = false
	best.ZIndex = 11
	best.Parent = frame
	Ticker.bestLabel = best

	local boardButton = Instance.new("TextButton")
	boardButton.Name = "DailyBoardButton"
	boardButton.Size = UDim2.fromOffset(100, 44) -- 44 px touch target
	boardButton.AnchorPoint = Vector2.new(1, 1)
	boardButton.Position = UDim2.new(1, -8, 1, -6)
	boardButton.BackgroundColor3 = WOOD
	boardButton.Font = Enum.Font.GothamBold
	boardButton.TextSize = 14
	boardButton.TextColor3 = CREAM
	boardButton.TextTransparency = 0
	boardButton.TextStrokeTransparency = 1
	boardButton.Text = "Daily board"
	boardButton.ZIndex = 12
	boardButton.Parent = frame
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = boardButton
	local bs = Instance.new("UIStroke")
	bs.Color = GOLD
	bs.Thickness = 1.5
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Parent = boardButton

	-- refresh whenever the menu strip becomes visible and the last answer is old
	local lastAsk = -1e9
	local asking = false
	local function ask()
		if asking or os.clock() - lastAsk < MenuTicker.CACHE_SECONDS then
			return
		end
		asking = true
		lastAsk = os.clock()
		task.spawn(function()
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			local fn = remotes and remotes:WaitForChild("GetMenuTicker", 10)
			local ok, data = pcall(function()
				return fn and fn:InvokeServer() or nil
			end)
			local day = math.floor(os.time() / 86400)
			local line, real = MenuTicker.text(ok and data or {}, day)
			text.Text = line
			icon.Text = real and "🏆" or "🕯️"
			asking = false
		end)
	end
	local day = math.floor(os.time() / 86400)
	text.Text = MenuTicker.text({}, day) -- the flavor line right away, the board a moment later
	frame:GetPropertyChangedSignal("Visible"):Connect(ask)
	frame.AncestryChanged:Connect(ask)
	task.defer(ask)
	frame.MouseEnter:Connect(ask)
	return boardButton
end

-- Best line from the server state (state.profileStats); display only.
function Ticker.update(state)
	local label = Ticker.bestLabel
	if not label then return end
	local line = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("BestLine")).text(state and state.profileStats)
	label.Text = line or ""
	label.Visible = line ~= nil
end

return Ticker
