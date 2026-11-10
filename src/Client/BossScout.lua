--[[
	Client/BossScout.lua
	BOSS COUNTERPLAY (Engine/BossCounters.lua), display plus one request:
	  * Round Select shows the rule on the Boss card itself (no Scout bar); only the Rule Ban button lives here;
	  * a small boss chip on the Counter (the Shop header area) with the same line;
	  * Rule Bans: a token count on the sidebar board and on the banner, and a hold-to-confirm "Ban Rule" button on the
	    banner when the boss round is up (spends a token, the server deals the round again without the rule);
	  * the shield tags on Counter and pack cards are drawn by Client/ShopCards (spec.shield), computed in Shop.lua.
	Reads state.scout (name, rules, line, icon, banned), state.ruleBans, state.phase and state.round. The only remote
	is UseRuleBan; the server validates everything. The hold time follows Settings > Hold to Confirm.
	update(root, state) is called from render in a pcall.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local HoldConfirm = require(Engine:WaitForChild("HoldConfirm"))
local ClientSettings = require(script.Parent.ClientSettings)

local BossScout = {}

local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(70, 48, 30)

local banner, chip, tokenChip
local holdConn, hold

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = CREAM
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextSize = 15
	l.ZIndex = 60
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function stopHold()
	if holdConn then
		holdConn:Disconnect()
		holdConn = nil
	end
	if hold then
		hold:reset()
	end
end

local function buildBanner(parent)
	-- No Scout bar any more: the Boss card shows the rule name and its line. This holder only carries the Rule Ban
	-- button, top right of Round Select beside the Tips chip, shown only when a ban can be spent.
	banner = Instance.new("Frame")
	banner.Name = "BossScoutBanner"
	banner.AnchorPoint = Vector2.new(1, 0)
	banner.Position = UDim2.new(1, -182, 0, 12)
	banner.Size = UDim2.fromOffset(220, 46)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.ZIndex = 58
	banner.Parent = parent

	local ban = Instance.new("TextButton")
	ban.Name = "BanButton"
	ban.Size = UDim2.fromScale(1, 1)
	ban.BackgroundColor3 = Color3.fromRGB(150, 60, 50)
	ban.AutoButtonColor = false
	ban.Font = Enum.Font.GothamBold
	ban.TextSize = 14
	ban.TextColor3 = CREAM
	ban.TextWrapped = true
	ban.Text = "Hold to ban the rule"
	ban.Visible = false
	ban.ZIndex = 61
	ban.Parent = banner
	corner(ban, 8)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GOLD
	fill.BackgroundTransparency = 0.5
	fill.BorderSizePixel = 0
	fill.ZIndex = 62
	fill.Parent = ban
	corner(fill, 8)

	-- hold to confirm (the same rule as Restart Run, Engine/HoldConfirm): a quick tap never spends the token
	ban.MouseButton1Down:Connect(function()
		stopHold()
		hold = HoldConfirm.new(ClientSettings.holdSeconds())
		hold:press(os.clock())
		holdConn = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			fill.Size = UDim2.new(hold:progress(now), 0, 1, 0)
			if hold:update(now) then
				stopHold()
				fill.Size = UDim2.fromScale(0, 1)
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				local remote = remotes and remotes:FindFirstChild("UseRuleBan")
				if remote then remote:FireServer() end
			end
		end)
	end)
	local function release()
		stopHold()
		fill.Size = UDim2.fromScale(0, 1)
	end
	ban.MouseButton1Up:Connect(release)
	ban.MouseLeave:Connect(release)
end

local function buildChip(parent)
	chip = Instance.new("TextLabel")
	chip.Name = "BossScoutChip"
	chip.AnchorPoint = Vector2.new(0, 0)
	chip.Position = UDim2.fromOffset(12, 8)
	chip.Size = UDim2.new(0.5, -145, 0, 28) -- left of the Counter plaque (250 px, centred), never under it
	chip.BackgroundColor3 = WOOD
	chip.BorderSizePixel = 0
	chip.Font = Enum.Font.GothamBold
	chip.TextSize = 14
	chip.TextColor3 = CREAM
	chip.TextTransparency = 0
	chip.TextStrokeTransparency = 1
	chip.TextTruncate = Enum.TextTruncate.AtEnd
	chip.Visible = false
	chip.ZIndex = 40
	chip.Parent = parent
	corner(chip, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = chip
end

local function buildTokenChip(parent)
	tokenChip = Instance.new("TextLabel")
	tokenChip.Name = "RuleBanTokens"
	tokenChip.AnchorPoint = Vector2.new(1, 0)
	tokenChip.Position = UDim2.new(1, -8, 0, 8)
	tokenChip.Size = UDim2.fromOffset(74, 26)
	tokenChip.BackgroundColor3 = WOOD
	tokenChip.BorderSizePixel = 0
	tokenChip.Font = Enum.Font.GothamBold
	tokenChip.TextSize = 15
	tokenChip.TextColor3 = CREAM
	tokenChip.TextTransparency = 0
	tokenChip.TextStrokeTransparency = 1
	tokenChip.Visible = false
	tokenChip.ZIndex = 12
	tokenChip.Parent = parent
	corner(tokenChip, 13)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tokenChip
	-- Painted Rule Ban token (menu_icons "rule_ban") on the left; the no-entry emoji stays if the id is missing.
	tokenChip.TextXAlignment = Enum.TextXAlignment.Right
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = tokenChip
	local icon = Instance.new("TextLabel")
	icon.Name = "TokenIcon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(6, 1)
	icon.Size = UDim2.fromOffset(24, 24)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 16
	icon.Text = "🚫"
	icon.TextColor3 = CREAM
	icon.TextTransparency = 0
	icon.TextStrokeTransparency = 1
	icon.ZIndex = 13
	icon.Parent = tokenChip
	pcall(require(script.Parent.ArtIcon).apply, icon, "menu_icons", "rule_ban", icon, { cornerRadius = 6 })
end

function BossScout.update(root, state)
	if type(state) ~= "table" then
		return
	end
	local scout = state.scout
	local roundSelect = root:FindFirstChild("RoundSelect", true)
	local shop = root:FindFirstChild("Shop", true)
	local sidebar = root:FindFirstChild("SidebarBoard", true)

	if roundSelect and not banner then buildBanner(roundSelect) end
	if shop and not chip then buildChip(shop) end
	if sidebar and not tokenChip then buildTokenChip(sidebar) end

	if banner then
		local show = scout ~= nil and state.phase == "roundSelect"
		if show then
			local config = state.config
			local lastRound = (config and config.roundsPerNight) or 3
			local canBan = (state.ruleBans or 0) > 0 and not scout.banned and (state.round or 1) >= lastRound
			banner.Visible = canBan
			banner.BanButton.Visible = canBan
			banner.BanButton.Text = canBan and ("Hold to ban the rule (" .. tostring(state.ruleBans) .. " left)") or "Hold to ban the rule"
		else
			banner.Visible = false
		end
	end
	if chip then
		local show = scout ~= nil and (state.phase == "shop")
		chip.Visible = show
		if show then
			chip.Text = "  " .. (scout.icon or "👑") .. " Next boss: " .. scout.name .. ". " .. (scout.line or "")
		end
	end
	if tokenChip then
		local show = state.ruleBans ~= nil
		tokenChip.Visible = show
		if show then
			tokenChip.Text = tostring(math.floor(state.ruleBans))
		end
	end
end

return BossScout
