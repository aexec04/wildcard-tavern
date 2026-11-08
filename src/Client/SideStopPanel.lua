--[[
	Client/SideStopPanel.lua
	Side stops of the world map (shop, shrine, rest), shown on Round Select when the server state lists
	`sideStops` for the current Night's stop (Engine/SideStops.lua holds the rules; the server validates every
	action). A row of chips (icon + name) sits at the top left; a chip opens a small parchment window:
	  shop    two patron offers with price and a Buy button, Leave
	  shrine  "Make an offering (N Tips)" for a free House Pass for the next Night, Leave
	  rest    "Bank a second One More Round" or "+1 Hand next Night", Leave
	Built once by RoundSelect.lua: require(SideStopPanel)({ root, roundCorner, playClickSfx }) ->
	{ update = function(state) }. Text is 15px or larger.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local PARCHMENT = Color3.fromRGB(222, 198, 150)

return function(deps)
	local root, roundCorner = deps.root, deps.roundCorner
	local playClickSfx = deps.playClickSfx or function() end

	local function fire(stopId, action, arg)
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		local r = folder and folder:FindFirstChild("SideStop")
		if r then
			r:FireServer(stopId, action, arg)
		end
	end

	local function text(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = 16
		l.TextColor3 = INK
		l.TextWrapped = true
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		for k, v in pairs(props) do l[k] = v end
		l.Parent = parent
		return l
	end

	local function button(parent, props)
		local b = Instance.new("TextButton")
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.TextColor3 = CREAM
		b.BackgroundColor3 = Color3.fromRGB(86, 140, 70)
		b.TextWrapped = true
		for k, v in pairs(props) do b[k] = v end
		b.Parent = parent
		roundCorner(b, 8)
		return b
	end

	local chipRow = Instance.new("Frame")
	chipRow.Name = "SideStopChips"
	chipRow.BackgroundTransparency = 1
	chipRow.Position = UDim2.fromOffset(14, 10)
	chipRow.Size = UDim2.new(0.4, 0, 0, 40)
	chipRow.ZIndex = 8
	chipRow.Visible = false
	chipRow.Parent = root
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipRow

	local window = Instance.new("Frame")
	window.Name = "SideStopWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(460, 330)
	window.BackgroundColor3 = PARCHMENT
	window.ZIndex = 30
	window.Visible = false
	window.Parent = root
	roundCorner(window, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(110, 80, 45)
	stroke.Thickness = 3
	stroke.Parent = window
	local fit = Instance.new("UIScale")
	fit.Parent = window
	local title = text(window, { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 10), TextSize = 22, ZIndex = 31 })
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 50)
	body.Size = UDim2.new(1, -24, 1, -110)
	body.ZIndex = 31
	body.Parent = window
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 8)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body
	local leave = button(window, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(180, 38),
		Text = "Leave", BackgroundColor3 = Color3.fromRGB(110, 76, 44), ZIndex = 31,
	})
	local note = text(window, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -56), Size = UDim2.new(1, -24, 0, 22),
		Text = "", TextSize = 15, TextColor3 = Color3.fromRGB(120, 84, 24), ZIndex = 31,
	})

	local openId = nil
	local latest = nil

	local function clearBody()
		for _, c in ipairs(body:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end
	end

	local function render()
		clearBody()
		local entry
		for _, e in ipairs(latest and latest.sideStops or {}) do
			if e.id == openId then entry = e end
		end
		if not entry then
			window.Visible = false
			openId = nil
			return
		end
		window.Visible = true
		title.Text = entry.icon .. " " .. entry.name
		local tips = latest.tips or 0
		note.Text = string.format("You have %d Tips", math.floor(tips))
		if entry.side == "shop" then
			for i, offer in ipairs(entry.offers or {}) do
				local row = Instance.new("Frame")
				row.LayoutOrder = i
				row.Size = UDim2.new(1, 0, 0, 74)
				row.BackgroundColor3 = Color3.fromRGB(235, 216, 172)
				row.ZIndex = 32
				row.Parent = body
				roundCorner(row, 8)
				text(row, { Size = UDim2.new(1, -120, 0, 24), Position = UDim2.fromOffset(10, 4), Text = (offer.icon or "") .. " " .. offer.name, TextSize = 17, ZIndex = 33, TextXAlignment = Enum.TextXAlignment.Left })
				text(row, { Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(10, 28), Text = offer.description or "", TextSize = 15, Font = Enum.Font.GothamMedium, ZIndex = 33, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
				local canBuy = tips >= offer.price
				local buy = button(row, {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(96, 40),
					Text = "Buy " .. offer.price, ZIndex = 33,
					BackgroundColor3 = canBuy and Color3.fromRGB(86, 140, 70) or Color3.fromRGB(130, 100, 80),
				})
				buy.MouseButton1Click:Connect(function()
					if canBuy then
						playClickSfx()
						fire(entry.id, "buy", offer.id)
					end
				end)
			end
			if #(entry.offers or {}) == 0 then
				text(body, { Size = UDim2.new(1, 0, 0, 40), Text = "Sold out. Come back another run.", ZIndex = 32, LayoutOrder = 1 })
			end
		elseif entry.side == "shrine" then
			text(body, { Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 1, ZIndex = 32, Font = Enum.Font.GothamMedium,
				Text = "Leave an offering and the shrine lends you a free House Pass for the next Night." })
			local give = button(body, {
				LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 44), ZIndex = 32,
				Text = string.format("Make an offering (%d Tips)", entry.cost or 3),
				BackgroundColor3 = tips >= (entry.cost or 3) and Color3.fromRGB(86, 140, 70) or Color3.fromRGB(130, 100, 80),
			})
			give.MouseButton1Click:Connect(function()
				if tips >= (entry.cost or 3) then
					playClickSfx()
					fire(entry.id, "shrine")
				end
			end)
		else -- rest
			text(body, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, ZIndex = 32, Font = Enum.Font.GothamMedium, Text = "Take a breath. Pick one:" })
			local hand = button(body, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 44), ZIndex = 32, Text = "+1 Hand in every round of the next Night" })
			hand.MouseButton1Click:Connect(function()
				playClickSfx()
				fire(entry.id, "rest", "hand")
			end)
			local banked = (latest.sideBonus and latest.sideBonus.extraContinues or 0) >= 1
			local cont = button(body, {
				LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 44), ZIndex = 32, Text = "Bank a second One More Round",
				BackgroundColor3 = banked and Color3.fromRGB(130, 100, 80) or Color3.fromRGB(86, 140, 70),
			})
			cont.MouseButton1Click:Connect(function()
				if not banked then
					playClickSfx()
					fire(entry.id, "rest", "continue")
				end
			end)
		end
	end

	leave.MouseButton1Click:Connect(function()
		playClickSfx()
		local id = openId
		openId = nil
		window.Visible = false
		if id then
			fire(id, "leave")
		end
	end)

	local chips = {}
	local M = {}

	function M.update(state)
		latest = state
		local list = type(state) == "table" and state.phase == "roundSelect" and state.sideStops or nil
		for _, c in ipairs(chips) do c:Destroy() end
		chips = {}
		if type(list) ~= "table" or #list == 0 then
			chipRow.Visible = false
			window.Visible = false
			openId = nil
			return
		end
		chipRow.Visible = true
		for i, entry in ipairs(list) do
			local chip = button(chipRow, {
				LayoutOrder = i, Size = UDim2.fromOffset(210, 38), Text = entry.icon .. " " .. entry.name, ZIndex = 8,
				BackgroundColor3 = GOLD, TextColor3 = INK,
			})
			chip.MouseButton1Click:Connect(function()
				playClickSfx()
				if entry.side == "minigame" then
					-- the game opens in Client/MinigamePanel.lua once the server answers
					local folder = ReplicatedStorage:FindFirstChild("Remotes")
					local r = folder and folder:FindFirstChild("Minigame")
					if r then
						r:FireServer(entry.id, "start")
					end
					return
				end
				openId = entry.id
				if entry.side == "shop" and not entry.offers then
					fire(entry.id, "open")
				end
				render()
			end)
			table.insert(chips, chip)
		end
		render()
	end

	return M
end
