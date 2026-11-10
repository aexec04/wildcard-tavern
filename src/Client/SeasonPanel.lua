--[[
	Client/SeasonPanel.lua
	TAVERN SEASON (Engine/SeasonTrack.lua): the 30 day reward ladder, opened from the Season tile on the main menu.
	Art first: a painted horizontal track of 30 tier tiles (card back art, title art or a coin for Tips), a wood banner
	with the season name, days left as a number beside a clock, a progress bar to the next tier and a Claim All button.
	Reached tiles glow and can be tapped to claim; claimed tiles show a check; locked tiles are dimmed (never black).
	Display only: the server owns XP, the season window and the claims (remote ClaimSeason, a tier number or "all").
	Reads state.season (SeasonTrack.view). Refreshes on every StateUpdated while open.

	init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, addTooltip,
	              popIn, popOut, addButtonHoverScale, getLatestState, StateUpdatedRemote }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonPanel = {}

function SeasonPanel.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local ArtIcon = require(script.Parent.ArtIcon)
	local ClaimRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ClaimSeason")

	local INK = Color3.fromRGB(60, 40, 22)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local WOOD = Color3.fromRGB(86, 58, 34)
	local PARCH = Color3.fromRGB(222, 198, 150)
	local GREEN = Color3.fromRGB(86, 140, 80)
	local TILE_W, TILE_H = 104, 170
	local PREMIUM_H = 118 -- the premium row under each tier

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 15
		l.ZIndex = 43
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "SeasonBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.new(0.86, 0, 0, 520) -- sized to its content (track 314 + header 104 + footer and Close)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	-- wood banner: season name, days left (number + clock)
	local banner = Instance.new("Frame")
	banner.Size = UDim2.new(1, -30, 0, 46)
	banner.Position = UDim2.fromOffset(15, 10)
	banner.BackgroundColor3 = WOOD
	banner.BorderSizePixel = 0
	banner.ZIndex = 42
	banner.Parent = panel
	deps.roundCorner(banner, 8)
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = GOLD
	bannerStroke.Thickness = 2
	bannerStroke.Parent = banner
	-- painted season banner (ContentArt "seasons", SeasonTrack bannerKey) behind the text; wood stays as the fallback
	local bannerArt = Instance.new("Frame")
	bannerArt.Name = "SeasonBannerArt"
	bannerArt.Size = UDim2.fromScale(1, 1)
	bannerArt.BackgroundTransparency = 1
	bannerArt.ClipsDescendants = true
	bannerArt.ZIndex = 42
	bannerArt.Parent = banner
	deps.roundCorner(bannerArt, 8)
	local bannerScrim = Instance.new("Frame")
	bannerScrim.Name = "SeasonBannerScrim"
	bannerScrim.Size = UDim2.fromScale(1, 1)
	bannerScrim.BackgroundColor3 = Color3.fromRGB(20, 12, 6)
	bannerScrim.BackgroundTransparency = 1
	bannerScrim.BorderSizePixel = 0
	bannerScrim.ZIndex = 43
	bannerScrim.Visible = false
	bannerScrim.Parent = bannerArt
	local bannerKeyShown
	local function setBanner(key)
		if key == bannerKeyShown then return end
		bannerKeyShown = key
		for _, c in ipairs(bannerArt:GetChildren()) do
			if c:IsA("ImageLabel") then c:Destroy() end
		end
		bannerScrim.Visible = false
		if not key then return end
		local img = ArtIcon.apply(bannerArt, "seasons", key, nil, { zIndex = 42, cornerRadius = 8 })
		if img then
			img.ScaleType = Enum.ScaleType.Crop
			bannerScrim.BackgroundTransparency = 0.45
			bannerScrim.Visible = true
		end
	end
	local nameLabel = label(banner, {
		Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(14, 0), TextSize = 22, TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "Tavern Season",
	})
	local daysLabel = label(banner, {
		Size = UDim2.fromOffset(132, 46), Position = UDim2.new(1, -140, 0, 0), TextSize = 20, TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	})

	-- progress bar to the next tier
	local barBack = Instance.new("Frame")
	barBack.Size = UDim2.new(1, -440, 0, 24)
	barBack.Position = UDim2.fromOffset(15, 66)
	barBack.BackgroundColor3 = Color3.fromRGB(120, 96, 66)
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 42
	barBack.Parent = panel
	deps.roundCorner(barBack, 12)
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = GOLD
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 43
	barFill.Parent = barBack
	deps.roundCorner(barFill, 12)
	local barText = label(barBack, { Size = UDim2.fromScale(1, 1), ZIndex = 44, TextSize = 15, TextColor3 = INK, Text = "" })

	local claimAll = Instance.new("TextButton")
	claimAll.Size = UDim2.fromOffset(190, 34)
	claimAll.AnchorPoint = Vector2.new(1, 0)
	claimAll.Position = UDim2.new(1, -15, 0, 61)
	claimAll.Font = Enum.Font.GothamBold
	claimAll.TextSize = 16
	claimAll.TextColor3 = CREAM
	claimAll.BackgroundColor3 = GREEN
	claimAll.Text = "Claim All"
	claimAll.ZIndex = 43
	claimAll.Parent = panel
	deps.polishButton(claimAll, 8)
	deps.addButtonHoverScale(claimAll)

	-- the horizontal track
	local track = Instance.new("ScrollingFrame")
	track.Name = "SeasonTrack"
	track.Size = UDim2.new(1, -30, 0, TILE_H + PREMIUM_H + 26)
	track.Position = UDim2.fromOffset(15, 104)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.ScrollBarThickness = 10
	track.ScrollBarImageColor3 = GOLD
	track.ScrollBarImageTransparency = 0
	track.AutomaticCanvasSize = Enum.AutomaticSize.X
	track.CanvasSize = UDim2.new()
	track.ZIndex = 41
	track.Parent = panel
	local trackLayout = Instance.new("UIListLayout")
	trackLayout.FillDirection = Enum.FillDirection.Horizontal
	trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackLayout.Padding = UDim.new(0, 8)
	trackLayout.Parent = track

	local premiumButton = Instance.new("TextButton")
	premiumButton.Size = UDim2.fromOffset(200, 34)
	premiumButton.AnchorPoint = Vector2.new(1, 0)
	premiumButton.Position = UDim2.new(1, -215, 0, 61)
	premiumButton.Font = Enum.Font.GothamBold
	premiumButton.TextSize = 15
	premiumButton.TextColor3 = INK
	premiumButton.BackgroundColor3 = GOLD
	premiumButton.Text = "Premium"
	premiumButton.ZIndex = 43
	premiumButton.Visible = false
	premiumButton.Parent = panel
	deps.polishButton(premiumButton, 8)
	deps.addButtonHoverScale(premiumButton)
	local premiumItemId = nil

	local footer = label(panel, {
		Size = UDim2.new(1, -30, 0, 22), Position = UDim2.new(0, 15, 1, -78), Font = Enum.Font.GothamMedium, TextColor3 = CREAM, TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "Earn season XP the way you earn Tavern Rank XP. Unclaimed rewards end with the season.",
	})
	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(110, 34)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -10)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	closeButton.Text = "Close"
	closeButton.ZIndex = 43
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	local function clearTrack()
		for _, child in ipairs(track:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- art category and key of a reward, and its emoji fallback (shared resolver: no reward kind falls back to the X box)
	local RewardArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RewardArt"))
	local function rewardArt(reward)
		return RewardArt.resolve(reward)
	end

	local function premiumSection(t, row)
		local prem = row.premium
		if not prem then return end
		local box = Instance.new("Frame")
		box.Name = "Premium"
		box.Position = UDim2.fromOffset(4, TILE_H + 4)
		box.Size = UDim2.fromOffset(TILE_W - 8, PREMIUM_H - 6)
		box.BackgroundColor3 = prem.claimed and Color3.fromRGB(176, 190, 140) or Color3.fromRGB(235, 214, 160)
		box.BorderSizePixel = 0
		box.ZIndex = 43
		box.Parent = t
		deps.roundCorner(box, 8)
		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD
		stroke.Thickness = 2
		stroke.Parent = box
		label(box, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 2), TextSize = 14, TextColor3 = Color3.fromRGB(150, 100, 20), Text = "Premium" })
		local category, key, emoji = rewardArt(prem.reward)
		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(40, 40)
		well.Position = UDim2.fromOffset(28, 20)
		well.BackgroundColor3 = WOOD
		well.BorderSizePixel = 0
		well.ZIndex = 44
		well.Parent = box
		deps.roundCorner(well, 8)
		local glyph = label(well, { Size = UDim2.fromScale(1, 1), TextSize = 22, TextColor3 = CREAM, Text = emoji, ZIndex = 45 })
		if category then
			pcall(ArtIcon.apply, well, category, key, glyph, { cornerRadius = 8, zIndex = 46, dim = prem.locked })
		end
		if prem.locked then glyph.TextTransparency = 0.35 end -- dimmed, never black
		label(box, { Size = UDim2.new(1, -4, 0, 30), Position = UDim2.fromOffset(2, 62), TextSize = 14, TextWrapped = true, Font = Enum.Font.GothamMedium, Text = prem.text or "" })
		if prem.claimed then
			label(box, { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -26, 0, 0), TextSize = 18, TextColor3 = GREEN, Text = "✔", ZIndex = 48 })
		elseif prem.locked then
			label(box, { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -26, 0, 0), TextSize = 16, Text = "🔒", ZIndex = 48 })
		end
		local claimBox = Instance.new("TextButton")
		claimBox.Size = UDim2.fromScale(1, 1)
		claimBox.BackgroundTransparency = 1
		claimBox.Text = ""
		claimBox.ZIndex = 49
		claimBox.Parent = box
		claimBox.MouseButton1Click:Connect(function()
			if row.reached and not prem.locked and not prem.claimed then
				deps.playClickSfx()
				ClaimRemote:FireServer(row.tier, true)
			end
		end)
	end

	local function tile(row, seasonSeed)
		local t = Instance.new("TextButton")
		t.Name = "Tier_" .. row.tier
		t.LayoutOrder = row.tier
		t.Size = UDim2.fromOffset(TILE_W, TILE_H)
		t.AutoButtonColor = false
		t.Text = ""
		t.BackgroundColor3 = row.claimed and Color3.fromRGB(176, 190, 140) or PARCH
		t.BorderSizePixel = 0
		t.ZIndex = 42
		t.Parent = track
		deps.roundCorner(t, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = (row.reached and not row.claimed) and GOLD or INK
		stroke.Thickness = (row.reached and not row.claimed) and 3 or 1.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = t

		label(t, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 4), TextSize = 17, Text = tostring(row.tier) })
		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(76, 76)
		well.Position = UDim2.fromOffset(14, 32)
		well.BackgroundColor3 = WOOD
		well.BorderSizePixel = 0
		well.ZIndex = 43
		well.Parent = t
		deps.roundCorner(well, 10)
		local category, key, emoji = rewardArt(row.reward)
		local glyph = label(well, { Size = UDim2.fromScale(1, 1), TextSize = 34, TextColor3 = CREAM, Text = emoji, ZIndex = 44 })
		if category then
			pcall(ArtIcon.apply, well, category, key, glyph, { cornerRadius = 10, zIndex = 45, dim = not row.reached })
		end
		if not row.reached then
			glyph.TextTransparency = 0.35 -- dimmed, never black
		end
		label(t, {
			Size = UDim2.new(1, -6, 0, 40), Position = UDim2.fromOffset(3, 112), TextSize = 14, TextWrapped = true,
			Font = Enum.Font.GothamMedium, Text = row.text or "",
		})
		if row.claimed then
			label(t, { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -32, 0, 2), TextSize = 22, TextColor3 = GREEN, Text = "✔", ZIndex = 47 })
		elseif not row.reached then
			label(t, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, TILE_H - 20), TextSize = 14, Font = Enum.Font.Gotham, Text = row.need .. " XP" })
		end
		t.Size = UDim2.fromOffset(TILE_W, TILE_H + PREMIUM_H)
		premiumSection(t, row)
		t.MouseButton1Click:Connect(function()
			if row.reached and not row.claimed then
				deps.playClickSfx()
				ClaimRemote:FireServer(row.tier)
			end
		end)
		deps.addTooltip(t, (row.text or "") .. (row.claimed and " (claimed)" or row.reached and " (tap to claim)" or (" at " .. row.need .. " season XP")))
	end

	local function refresh()
		local state = deps.getLatestState and deps.getLatestState() or nil
		local view = state and state.season
		clearTrack()
		if not view then
			setBanner(nil)
			nameLabel.Text = "Tavern Season"
			daysLabel.Text = ""
			barText.Text = "No season is running right now."
			barFill.Size = UDim2.fromScale(0, 1)
			claimAll.Visible = false
			return
		end
		if view.upcoming then
			setBanner(view.bannerKey)
			nameLabel.Text = view.name
			daysLabel.Text = "Starts in " .. tostring(view.startsIn) .. "d"
			barText.Text = "Coming soon."
			barFill.Size = UDim2.fromScale(0, 1)
			claimAll.Visible = false
			return
		end
		setBanner(view.bannerKey)
		nameLabel.Text = view.name
		daysLabel.Text = "🕒 " .. tostring(view.daysLeft) .. "d left"
		claimAll.Visible = true
		premiumItemId = view.premium and view.premium.itemId or nil
		premiumButton.Visible = view.premium ~= nil
		if view.premium then
			local store = state.seasonStore
			local row2
			for _, item in ipairs(store and store.items or {}) do
				if item.id == premiumItemId then row2 = item end
			end
			if view.premium.owned then
				premiumButton.Text = "Premium owned"
				premiumButton.BackgroundColor3 = Color3.fromRGB(176, 190, 140)
			else
				local price = row2 and require(script.Parent.StorePanel).priceText(row2) or "Coming soon"
				premiumButton.Text = "Get Premium"
				premiumButton.BackgroundColor3 = GOLD
				deps.addTooltip(premiumButton, "Premium row: " .. table.concat(view.premium.perks or {}, ", ") .. ". " .. price .. ". Looks only, never changes your score.")
			end
		end
		claimAll.Text = view.claimable > 0 and ("Claim All (" .. view.claimable .. ")") or "Claim All"
		claimAll.AutoButtonColor = view.claimable > 0
		claimAll.BackgroundColor3 = view.claimable > 0 and GREEN or Color3.fromRGB(110, 100, 86)
		if view.maxed then
			barFill.Size = UDim2.fromScale(1, 1)
			barText.Text = "All 30 tiers reached!"
		else
			barFill.Size = UDim2.fromScale(math.clamp(view.into / math.max(1, view.xpPerTier), 0, 1), 1)
			barText.Text = string.format("Tier %d   %d / %d XP to tier %d", view.tier, view.into, view.xpPerTier, view.tier + 1)
		end
		for _, row in ipairs(view.tiers) do
			tile(row)
		end
		-- bring the first tile that still needs attention into view
		local focus = math.max(0, math.min(view.tier, 30) - 2)
		track.CanvasPosition = Vector2.new(focus * (TILE_W + 8), 0)
	end

	premiumButton.MouseButton1Click:Connect(function()
		local state = deps.getLatestState and deps.getLatestState() or nil
		if premiumItemId and state and state.season and state.season.premium and not state.season.premium.owned then
			deps.playClickSfx()
			ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StorePurchase"):FireServer(premiumItemId) -- the server validates the season and ownership
		end
	end)

	claimAll.MouseButton1Click:Connect(function()
		local state = deps.getLatestState and deps.getLatestState() or nil
		if state and state.season and (state.season.claimable or 0) > 0 then
			deps.playClickSfx()
			ClaimRemote:FireServer("all")
		end
	end)

	require(script.Parent.PanelTabs).attach(backdrop, "season", deps.playClickSfx) -- shared tab strip + Back
	OverlayManager.register("season", function()
		deps.popOut(backdrop, panel)
	end)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("season")
		refresh()
		deps.popIn(backdrop, panel)
	end
	OverlayManager.registerOpener("season", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	closeButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)
	_ = footer
end

return SeasonPanel
