--[[
	Client/EndlessChips.lua
	Crowd Rules in Endless Mode (Engine/EndlessRules.lua), display only:
	  * small round chips along the bottom of the sidebar board, one per active rule, with hover text
	    (rule name and what it does);
	  * a banner "New Crowd Rule: <name>" that slides in once per Night when a rule joins.
	The server sends state.crowdRules (list of { id, name, icon, text }) and state.crowdRuleNew (the rule that
	joined this Night, with .night). Nothing here changes the run.

	deps: root (the gameplay root), addTooltip(button, text, align)
	module: init(deps) once, update(state) from render()
]]

local TweenService = game:GetService("TweenService")

local ClientSettings = require(script.Parent.ClientSettings)
local ArtIcon = require(script.Parent.ArtIcon)

local EndlessChips = {}

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(86, 58, 34)
local CHIP = 36

local ui
local builtKey = ""
local bannerNight = 0

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

function EndlessChips.init(deps)
	local holder = Instance.new("Frame")
	holder.Name = "CrowdRuleChips"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -10)
	holder.Size = UDim2.new(1, -24, 0, CHIP * 2 + 6)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.ZIndex = 20
	holder.Active = false
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CHIP, CHIP)
	grid.CellPadding = UDim2.fromOffset(4, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
	grid.Parent = holder

	local banner = Instance.new("TextLabel")
	banner.Name = "CrowdRuleBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -90)
	banner.Size = UDim2.fromOffset(520, 64)
	banner.BackgroundColor3 = WOOD
	banner.BorderSizePixel = 0
	banner.Font = Enum.Font.GothamBold
	banner.TextSize = 20
	banner.TextColor3 = CREAM
	banner.TextWrapped = true
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 1
	banner.Text = ""
	banner.Visible = false
	banner.ZIndex = 120
	banner.Active = false
	banner.Parent = deps.root
	corner(banner, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = banner

	ui = { holder = holder, banner = banner, addTooltip = deps.addTooltip, root = deps.root, token = 0 }
end

local function parentHolder()
	if ui.holder.Parent then
		return
	end
	local board = ui.root:FindFirstChild("SidebarBoard", true)
	if board then
		ui.holder.Parent = board
	end
end

local function rebuild(rules)
	for _, child in ipairs(ui.holder:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, rule in ipairs(rules) do
		local chip = Instance.new("TextButton")
		chip.Name = "Chip_" .. rule.id
		chip.LayoutOrder = i
		chip.AutoButtonColor = false
		chip.BackgroundColor3 = WOOD
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 20
		chip.Text = rule.icon or "!"
		chip.TextColor3 = CREAM
		chip.TextTransparency = 0
		chip.TextStrokeTransparency = 1
		chip.ZIndex = 21
		chip.Parent = ui.holder
		corner(chip, CHIP // 2)
		local ring = Instance.new("UIStroke")
		ring.Color = GOLD
		ring.Thickness = 1.5
		ring.Parent = chip
		-- painted chip art when an id is recorded (endless_rules), emoji otherwise
		pcall(ArtIcon.apply, chip, "endless_rules", rule.id, chip, { cornerRadius = CHIP // 2 })
		ui.addTooltip(chip, rule.name .. ": " .. rule.text, "left")
	end
end

local function showBanner(rule)
	local banner = ui.banner
	ui.token = ui.token + 1
	local token = ui.token
	banner.Text = "New Crowd Rule: " .. rule.name .. "\n" .. rule.text
	banner.TextTransparency = 0
	banner.BackgroundTransparency = 0
	banner.Visible = true
	local reduced = ClientSettings.get("reduceShake") == true
	if reduced then
		banner.Position = UDim2.new(0.5, 0, 0, 24)
	else
		banner.Position = UDim2.new(0.5, 0, 0, -90)
		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, 24),
		}):Play()
	end
	task.delay(reduced and 2.5 or 3.2, function()
		if token ~= ui.token then
			return
		end
		banner.Visible = false
	end)
end

function EndlessChips.update(state)
	if not ui or type(state) ~= "table" then
		return
	end
	local rules = state.crowdRules
	if type(rules) ~= "table" or #rules == 0 then
		ui.holder.Visible = false
		builtKey = ""
		return
	end
	parentHolder()
	local ids = {}
	for i, r in ipairs(rules) do
		ids[i] = r.id
	end
	local key = table.concat(ids, ",")
	if key ~= builtKey then
		builtKey = key
		rebuild(rules)
	end
	ui.holder.Visible = ui.holder.Parent ~= nil

	local fresh = state.crowdRuleNew
	if fresh and fresh.night and fresh.night ~= bannerNight then
		bannerNight = fresh.night
		showBanner(fresh)
	end
end

return EndlessChips
