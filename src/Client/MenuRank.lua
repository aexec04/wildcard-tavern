-- Tavern Rank bar for the main menu: "Rank 7" on a wood plaque, an XP bar and the next reward in a hover tooltip.
-- Display only (state.rank from Engine/TavernRank.view). Menu.lua calls attach(parent, layoutOrder) once;
-- the hub calls update(state) from render in a pcall.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local TavernRank = require(Engine:WaitForChild("TavernRank"))
local CardBacks = require(Engine:WaitForChild("CardBacks"))
local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
local Achievements = require(Engine:WaitForChild("Achievements"))

local MenuRank = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(86, 58, 34)
local INK = Color3.fromRGB(60, 40, 22)

local ui -- built pieces
local shown = { rank = nil, ratio = nil }

local LOOKUP = {
	cardBackName = function(id) local d = CardBacks.getById(id) return d and d.name end,
	setName = function(id) local d = CosmeticSets.getById(id) return d and d.name end,
	titleName = function(id) local d = Achievements.getById(id) return d and d.title end,
}

-- "Rank 7  120 / 220 XP" or "Rank 30  Max rank"
local SHORT_REWARD = { tips = "Tips", title = "Title", cardBack = "Card back", set = "Card Set" }

function MenuRank.textFor(view)
	if view.maxed then
		return string.format("Rank %d  Max rank", view.rank)
	end
	local nextText = ""
	if view.nextReward then
		local r = view.nextReward
		nextText = "   Next: " .. (r.kind == "tips" and ("+" .. r.amount .. " Tips") or SHORT_REWARD[r.kind] or "Reward")
	end
	return string.format("Rank %d   %d / %d XP%s", view.rank, view.into, view.need, nextText)
end

function MenuRank.tipFor(view)
	if view.maxed or not view.nextReward then
		return "You reached the top of the tavern."
	end
	return string.format("Rank %d reward\n%s", view.nextRank, TavernRank.rewardText(view.nextReward, LOOKUP))
end

function MenuRank.attach(parent, layoutOrder, addTooltip)
	local frame = Instance.new("Frame")
	frame.Name = "RankBar"
	frame.Size = UDim2.fromOffset(360, 40)
	frame.LayoutOrder = layoutOrder
	frame.BackgroundColor3 = WOOD
	frame.ZIndex = 10
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = frame

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(32, 32)
	badge.Position = UDim2.fromOffset(5, 4)
	badge.BackgroundColor3 = GOLD
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 18
	badge.TextColor3 = INK
	badge.Text = "1"
	badge.ZIndex = 11
	badge.Parent = frame
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 16)
	badgeCorner.Parent = badge

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -52, 0, 12)
	track.Position = UDim2.fromOffset(44, 22)
	track.BackgroundColor3 = Color3.fromRGB(40, 28, 18)
	track.ZIndex = 11
	track.Parent = frame
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.ZIndex = 12
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, -52, 0, 18)
	text.Position = UDim2.fromOffset(44, 3)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 15
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = CREAM
	text.TextTransparency = 0
	text.TextStrokeTransparency = 1
	text.Text = "Rank 1"
	text.ZIndex = 11
	text.Parent = frame

	ui = { frame = frame, badge = badge, fill = fill, text = text, view = nil }
	if addTooltip then
		addTooltip(frame, function()
			return ui.view and MenuRank.tipFor(ui.view) or "Play to earn XP."
		end)
	end
	return frame
end

function MenuRank.update(state)
	if not ui or type(state) ~= "table" or type(state.rank) ~= "table" then
		return
	end
	local view = state.rank
	ui.view = view
	ui.badge.Text = tostring(math.floor(view.rank))
	ui.text.Text = MenuRank.textFor(view)
	local ratio = view.maxed and 1 or math.clamp(view.need > 0 and view.into / view.need or 0, 0, 1)
	if shown.ratio ~= ratio or shown.rank ~= view.rank then
		shown.ratio, shown.rank = ratio, view.rank
		TweenService:Create(ui.fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(ratio, 1) }):Play()
	end
end

return MenuRank
