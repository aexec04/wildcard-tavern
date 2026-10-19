--[[
	Client/Themes.lua
	The Themes (cosmetics) overlay -- buy/equip table+card color palettes.
	Purely visual, no gameplay effect, and buyable/equippable any time (not
	gated to the shop phase like Patrons are).

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Unlike HowToPlay.lua this one DOES need
	to hand things back: render() checks themesBackdrop.Visible to decide
	whether to refresh the list on every state update (so the panel stays
	accurate if it's open across a purchase), and calls refreshThemesList()
	when it is.

	deps fields:
		screenGui         -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel        -- function(instance, radius)
		polishButton       -- function(instance, radius)
		roundCorner        -- function(instance, radius)
		addSoftShadow      -- function(instance, radius)
		playClickSfx       -- function(volume?)
		playSfx            -- function(soundId, volume?, maxLength?)
		SOUND_IDS          -- table, for SOUND_IDS.buyPatron
		Themes             -- the Shared/Engine/Themes module
		GamePasses         -- the Shared/Engine/GamePasses module -- real-money
		                       Robux passes; GamePasses.passForTheme(themeId)
		                       tells us which Themes are gated behind one
		MarketplaceService -- the MarketplaceService, for PromptGamePassPurchase
		player             -- Players.LocalPlayer -- who PromptGamePassPurchase prompts
		BuyThemeRemote     -- RemoteEvent
		EquipThemeRemote   -- RemoteEvent
		showWarning        -- function(text)
		themesButton       -- TextButton, the in-game "🎨" corner button
		getLatestState     -- function() -> latest state table or nil (live
		                       getter, since latestState is reassigned each
		                       render() call, not mutated)
		popIn              -- function(backdrop, content, opts?)
		popOut             -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)

	Returns:
		{
			themesBackdrop = Frame,
			refreshThemesList = function(),
		}

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut; the Close button gets addButtonHoverScale.
	Per-row Buy/Equip/Get Pass buttons are left alone this pass -- they're
	rebuilt from scratch by refreshThemesList() on every purchase/equip, so
	giving them hover would need the same signature-gating Shop.lua's offer
	rows use, and this list is small/low-traffic enough not to be worth it.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local playSfx = deps.playSfx
	local SOUND_IDS = deps.SOUND_IDS
	local Themes = deps.Themes
	local GamePasses = deps.GamePasses
	local MarketplaceService = deps.MarketplaceService
	local player = deps.player
	local BuyThemeRemote = deps.BuyThemeRemote
	local EquipThemeRemote = deps.EquipThemeRemote
	local showWarning = deps.showWarning
	local themesButton = deps.themesButton
	local getLatestState = deps.getLatestState
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	-- BUGFIX (overlapping overlays): see Client/OverlayManager.lua's own
	-- header comment for the full story.
	local OverlayManager = require(script.Parent.OverlayManager)

	-- Purely visual -- spend Tips on table/card color palettes. No gameplay
	-- effect. Buyable/equippable any time, not just during the shop phase.

	local themesBackdrop = Instance.new("Frame")
	themesBackdrop.Name = "ThemesBackdrop"
	themesBackdrop.Size = UDim2.fromScale(1, 1)
	themesBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	themesBackdrop.BackgroundTransparency = 0.4
	themesBackdrop.Visible = false
	themesBackdrop.ZIndex = 20
	themesBackdrop.Parent = screenGui

	local themesPanel = Instance.new("Frame")
	themesPanel.Size = UDim2.fromScale(0.55, 0.6)
	themesPanel.Position = UDim2.fromScale(0.225, 0.2)
	themesPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	themesPanel.ZIndex = 21
	themesPanel.Parent = themesBackdrop
	polishPanel(themesPanel, 16)
	addSoftShadow(themesPanel, 18)

	local themesTitle = Instance.new("TextLabel")
	themesTitle.Size = UDim2.new(1, 0, 0, 40)
	themesTitle.BackgroundTransparency = 1
	themesTitle.Font = Enum.Font.GothamBold
	themesTitle.TextSize = 22
	themesTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	themesTitle.Text = "Themes -- cosmetic only, no gameplay effect"
	themesTitle.ZIndex = 21
	themesTitle.Parent = themesPanel

	-- BUGFIX (found while adding the 2 new premium Themes below): this was
	-- a plain Frame with a fixed height -- fine back when 6 rows (300px +
	-- padding) comfortably fit inside it, but 8 rows (400px + padding) runs
	-- past the panel's bottom edge, the exact same "content taller than its
	-- fixed-size container" bug just fixed in Menu.lua's button holder.
	-- Rather than re-guess another fixed size that just breaks again the
	-- next time a Theme gets added, this is now a real ScrollingFrame --
	-- AutomaticCanvasSize handles any future row count without needing
	-- another fix here.
	local themesListFrame = Instance.new("ScrollingFrame")
	themesListFrame.Size = UDim2.new(1, -20, 1, -100)
	themesListFrame.Position = UDim2.new(0, 10, 0, 45)
	themesListFrame.BackgroundTransparency = 1
	themesListFrame.BorderSizePixel = 0
	themesListFrame.ZIndex = 21
	themesListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	themesListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	themesListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	themesListFrame.ScrollBarThickness = 6
	themesListFrame.ScrollBarImageColor3 = Color3.fromRGB(200, 180, 160)
	themesListFrame.Parent = themesPanel

	local themesListLayout = Instance.new("UIListLayout")
	themesListLayout.Padding = UDim.new(0, 8)
	themesListLayout.Parent = themesListFrame

	local themesCloseButton = Instance.new("TextButton")
	themesCloseButton.Size = UDim2.new(0, 140, 0, 40)
	themesCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	themesCloseButton.Font = Enum.Font.GothamBold
	themesCloseButton.TextSize = 16
	themesCloseButton.Text = "Close"
	themesCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	themesCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	themesCloseButton.ZIndex = 21
	themesCloseButton.Parent = themesPanel
	polishButton(themesCloseButton, 10)
	addButtonHoverScale(themesCloseButton)

	themesCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(themesBackdrop, themesPanel)
	end)

	local function refreshThemesList()
		-- DEBUG (temporary, v3): unique marker so it's unambiguous whether
		-- Studio is actually running THIS version of the script or a stale
		-- cached one from before this edit synced in.
		print("[DEBUG Themes v3] refreshThemesList called. #Themes.Definitions =", Themes and #Themes.Definitions, "themesListFrame =", themesListFrame, "AbsoluteSize =", themesListFrame.AbsoluteSize)
		for _, child in ipairs(themesListFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local latestState = getLatestState()
		local ownedSet = {}
		local equippedId = Themes.DefaultThemeId
		if latestState then
			for _, id in ipairs(latestState.ownedThemeIds or {}) do
				ownedSet[id] = true
			end
			equippedId = latestState.equippedTheme or equippedId
		end

		local builtCount = 0
		for themeIndex, theme in ipairs(Themes.Definitions) do
			-- DEBUG (temporary, v3): wrap each row's build in pcall so one
			-- bad theme can't silently kill the whole loop (and the rest of
			-- the rows with it) without a trace -- if this prints an error,
			-- we've found it; if it doesn't, every row built successfully
			-- and the bug is purely visual/layout, not a crash.
			local ok, err = pcall(function()
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 50)
				-- DEBUG (temporary): bright red + forced high ZIndex + no
				-- clipping, to rule out "rows exist but are invisible/
				-- occluded/clipped" vs. "rows never actually get created".
				row.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
				row.BackgroundTransparency = 0
				row.Visible = true
				row.ZIndex = 50
				row.ClipsDescendants = false
				row.Parent = themesListFrame
				polishPanel(row, 10)

				local swatch = Instance.new("Frame")
				swatch.Size = UDim2.new(0, 30, 0, 30)
				swatch.Position = UDim2.new(0, 10, 0.5, -15)
				swatch.BackgroundColor3 = theme.colors.accent
				swatch.Parent = row
				roundCorner(swatch, 6)

				local gatingPass = GamePasses and GamePasses.passForTheme(theme.id)

				local label = Instance.new("TextLabel")
				label.Size = UDim2.new(1, -220, 1, 0)
				label.Position = UDim2.new(0, 50, 0, 0)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.Gotham
				label.TextSize = 15
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextColor3 = Color3.fromRGB(250, 240, 220)
				label.Text = gatingPass and string.format("%s -- %s (Game Pass)", theme.name, theme.description)
					or string.format("%s -- %s", theme.name, theme.description)
				label.Parent = row

				local actionButton = Instance.new("TextButton")
				actionButton.Size = UDim2.new(0, 130, 0, 36)
				actionButton.Position = UDim2.new(1, -140, 0.5, -18)
				actionButton.Font = Enum.Font.GothamBold
				actionButton.TextSize = 14
				actionButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
				actionButton.TextColor3 = Color3.fromRGB(250, 240, 220)
				actionButton.Parent = row
				polishButton(actionButton, 8)

				if theme.id == equippedId then
					actionButton.Text = "Equipped"
					actionButton.AutoButtonColor = false
					actionButton.BackgroundColor3 = Color3.fromRGB(70, 90, 55)
				elseif ownedSet[theme.id] then
					actionButton.Text = "Equip"
					actionButton.MouseButton1Click:Connect(function()
						playClickSfx()
						EquipThemeRemote:FireServer(theme.id)
					end)
				elseif gatingPass then
					-- Real-money Game Pass, not a Tips purchase -- prompts
					-- Roblox's own purchase UI directly (no server round-trip
					-- needed for the prompt itself; MarketplaceService.
					-- PromptGamePassPurchaseFinished on the server handles
					-- granting the Theme once a purchase actually completes,
					-- see Server/init.server.lua). gamePassId == 0 means
					-- whoever's testing this hasn't created the real Pass on
					-- the Creator Dashboard yet (see GamePasses.lua) -- show
					-- that plainly instead of prompting a purchase for
					-- Game Pass 0, which would just error.
					if gatingPass.gamePassId and gatingPass.gamePassId > 0 then
						actionButton.Text = "Get Pass"
						actionButton.MouseButton1Click:Connect(function()
							playClickSfx()
							MarketplaceService:PromptGamePassPurchase(player, gatingPass.gamePassId)
						end)
					else
						actionButton.Text = "Coming Soon"
						actionButton.AutoButtonColor = false
						actionButton.BackgroundColor3 = Color3.fromRGB(55, 45, 35)
					end
				else
					actionButton.Text = string.format("Buy (%d)", theme.price)
					actionButton.MouseButton1Click:Connect(function()
						local latest = getLatestState()
						if not latest or latest.tips < theme.price then
							showWarning("Not enough tips for that.")
							playClickSfx()
							return
						end
						playSfx(SOUND_IDS.buyPatron)
						BuyThemeRemote:FireServer(theme.id)
					end)
				end
			end)
			if ok then
				builtCount = builtCount + 1
			else
				print("[DEBUG Themes v3] ERROR building row", themeIndex, "theme.id =", theme and theme.id, "-->", err)
			end
		end

		-- DEBUG (temporary, v3): SYNCHRONOUS print, right after the loop,
		-- no task.defer -- removes "did the deferred callback even run" as
		-- a variable entirely.
		print("[DEBUG Themes v3] loop finished. builtCount =", builtCount, "/", #Themes.Definitions)
		local children = themesListFrame:GetChildren()
		local frameCount = 0
		for _, child in ipairs(children) do
			if child:IsA("Frame") then
				frameCount = frameCount + 1
			end
		end
		print("[DEBUG Themes v3] Frame children under themesListFrame =", frameCount, "/ total children =", #children)
		local firstRow = themesListFrame:FindFirstChildWhichIsA("Frame")
		if firstRow then
			print("[DEBUG Themes v3] firstRow Visible =", firstRow.Visible,
				"BackgroundTransparency =", firstRow.BackgroundTransparency,
				"AbsoluteSize =", firstRow.AbsoluteSize,
				"AbsolutePosition =", firstRow.AbsolutePosition,
				"ZIndex =", firstRow.ZIndex)
		else
			print("[DEBUG Themes v3] firstRow = NONE FOUND")
		end
		print("[DEBUG Themes v3] themesListFrame CanvasSize =", themesListFrame.CanvasSize,
			"Visible =", themesListFrame.Visible,
			"ClipsDescendants =", themesListFrame.ClipsDescendants)
	end

	OverlayManager.register("themes", function()
		popOut(themesBackdrop, themesPanel)
	end)

	themesButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("themes")
		refreshThemesList()
		popIn(themesBackdrop, themesPanel)
	end)

	return {
		themesBackdrop = themesBackdrop,
		refreshThemesList = refreshThemesList,
	}
end
