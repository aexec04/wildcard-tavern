--[[
	Client/Journey.lua
	The "Road Ahead" overlay -- a 2D, Mario-map-style horizontal path where
	the player's own Roblox avatar (real headshot thumbnail) stands on the
	current stage and hops/walks to the next one when a round is won.
	Reachable from the in-game "🗺" corner button and from the main menu's
	"Road Ahead" button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. render() needs to check
	journeyBackdrop.Visible and call refreshJourney() to keep the "you are
	here" marker accurate while the overlay is open across a round change,
	so both come back out of the require() call, same pattern as Shop.lua
	and Themes.lua.

	deps fields:
		screenGui        -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel       -- function(instance, radius)
		polishButton      -- function(instance, radius)
		roundCorner       -- function(instance, radius)
		addSoftShadow     -- function(instance, radius)
		playClickSfx      -- function(volume?)
		tweenTo           -- function(instance, props, duration, easingStyle?, easingDirection?)
		DifficultyTiers   -- the Shared/Engine/DifficultyTiers module
		BossRounds        -- the Shared/Engine/BossRounds module
		RunStateEngine    -- the Shared/Engine/RunState module (for targetScoreFor)
		Players           -- the Players service
		player            -- Players.LocalPlayer
		journeyButton     -- TextButton, the in-game "🗺" corner button
		menuJourneyButton -- TextButton, "Road Ahead" on the main menu
		getLatestState    -- function() -> latest state table or nil (live getter)
		getCurrentTheme   -- function() -> the currently-equipped theme table (live
		                      getter, since currentTheme is reassigned on every
		                      theme change, not mutated)
		addTooltip        -- function(button, text, align?) -- text can be a
		                      0-arg function for dynamic content

	JOURNEY FEATURE (Boss reveal): the map shows which specific Boss Round
	modifier is coming this Night (once the server has picked it -- see
	RunState.startRound's nightBossModifier) instead of just a generic
	crown icon. Skipping a round now lives on its own dedicated screen
	(ROUND SELECT FEATURE, see Client/RoundSelect.lua) -- this map is
	purely a preview of the road ahead, with no actionable buttons of its
	own.

	Returns:
		{
			journeyBackdrop = Frame,
			refreshJourney = function(),
		}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local tweenTo = deps.tweenTo
	local DifficultyTiers = deps.DifficultyTiers
	local BossRounds = deps.BossRounds
	local RunStateEngine = deps.RunStateEngine
	local Players = deps.Players
	local player = deps.player
	local journeyButton = deps.journeyButton
	local menuJourneyButton = deps.menuJourneyButton
	local getLatestState = deps.getLatestState
	local getCurrentTheme = deps.getCurrentTheme
	local addTooltip = deps.addTooltip

	-- LAYOUT FEATURE 9: Ahmed wanted his own creative spin here instead of
	-- copying Balatro's plain list -- a 2D, Mario-map-style path where your
	-- own Roblox avatar (real headshot thumbnail) stands on your current
	-- stage and hops/walks to the next one when you win a round.

	local PREVIEW_NIGHTS = 3 -- how many Nights ahead to show on the map
	local ROUNDS_PER_NIGHT = 3
	-- LANDMARK PATH (redesign, replacing the old plain-circle nodes): each
	-- stage is now a small landmark -- a lantern post for the Small Round,
	-- a table for the Big Round, an ornate gate for the Boss Round --
	-- standing on a ground line, instead of a uniform colored circle.
	-- NODE_SIZE bumped 64 -> 88 to give the tallest of these (the gate +
	-- its crown badge) headroom without poking into the avatar marker
	-- walking above the row (journeyAvatarMarker's Position formula below
	-- is written in terms of NODE_SIZE, so it grows with it automatically).
	local NODE_SIZE = 88
	local NIGHT_GAP_EXTRA = 60 -- extra width of the spacer between night clusters

	-- Shared between node construction (each landmark's natural/default
	-- color) and refreshJourneyImpl (the done/current overrides), so both
	-- stay in sync off one source of truth instead of hex literals
	-- scattered across two functions.
	local LANDMARK_COLORS = {
		lanternGlow = Color3.fromRGB(240, 182, 76),
		table = Color3.fromRGB(90, 69, 48),
		gate = Color3.fromRGB(177, 84, 79),
		done = Color3.fromRGB(126, 161, 116),
		current = Color3.fromRGB(240, 182, 76),
	}

	-- Shared by refreshJourneyImpl/describeStage/refreshInfoBar (JOURNEY
	-- FEATURE) -- pulled out to one place instead of 3 copies of the same
	-- "look up this difficulty tier, fall back to default" dance.
	local function bossRoundsEnabledFor(latestState)
		local journeyDifficulty = DifficultyTiers.getById((latestState and latestState.difficultyId) or DifficultyTiers.DefaultId)
			or DifficultyTiers.getById(DifficultyTiers.DefaultId)
		return journeyDifficulty.bossRoundsEnabled ~= false
	end

	local journeyBackdrop = Instance.new("Frame")
	journeyBackdrop.Name = "JourneyBackdrop"
	journeyBackdrop.Size = UDim2.fromScale(1, 1)
	journeyBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	journeyBackdrop.BackgroundTransparency = 0.4
	journeyBackdrop.Visible = false
	journeyBackdrop.ZIndex = 20
	journeyBackdrop.Parent = screenGui

	local journeyPanel = Instance.new("Frame")
	journeyPanel.Size = UDim2.fromScale(0.7, 0.55)
	journeyPanel.Position = UDim2.fromScale(0.15, 0.22)
	journeyPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	journeyPanel.ZIndex = 21
	journeyPanel.Parent = journeyBackdrop
	polishPanel(journeyPanel, 16)
	addSoftShadow(journeyPanel, 18)

	local journeyTitle = Instance.new("TextLabel")
	journeyTitle.Size = UDim2.new(1, 0, 0, 40)
	journeyTitle.BackgroundTransparency = 1
	journeyTitle.Font = Enum.Font.GothamBold
	journeyTitle.TextSize = 22
	journeyTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	journeyTitle.Text = "The Road Ahead"
	journeyTitle.ZIndex = 21
	journeyTitle.Parent = journeyPanel

	local journeySubtitle = Instance.new("TextLabel")
	journeySubtitle.Size = UDim2.new(1, -30, 0, 24)
	journeySubtitle.Position = UDim2.new(0, 15, 0, 38)
	journeySubtitle.BackgroundTransparency = 1
	journeySubtitle.Font = Enum.Font.Gotham
	journeySubtitle.TextSize = 14
	journeySubtitle.TextColor3 = Color3.fromRGB(220, 205, 185)
	journeySubtitle.TextXAlignment = Enum.TextXAlignment.Left
	journeySubtitle.Text = "Your table walks the road one Round at a time. 👑 = Boss Round."
	journeySubtitle.ZIndex = 21
	journeySubtitle.Parent = journeyPanel

	-- Horizontal, scrollable map strip. Both the stage nodes AND the avatar
	-- marker live directly in here (as siblings, not nested inside each
	-- other) so they share one coordinate space -- the marker's X position can
	-- just be read off a node's AbsolutePosition and it'll line up correctly,
	-- including while scrolled.
	local journeyMapScroll = Instance.new("ScrollingFrame")
	-- Bottom margin leaves room for the JOURNEY FEATURE info bar below the
	-- map (see journeyInfoBar further down).
	journeyMapScroll.Size = UDim2.new(1, -20, 1, -230)
	journeyMapScroll.Position = UDim2.new(0, 10, 0, 68)
	journeyMapScroll.BackgroundTransparency = 1
	journeyMapScroll.BorderSizePixel = 0
	journeyMapScroll.ScrollBarThickness = 8
	journeyMapScroll.ScrollingDirection = Enum.ScrollingDirection.X
	journeyMapScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- grown automatically below
	journeyMapScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	journeyMapScroll.ZIndex = 21
	-- ClipsDescendants intentionally left at its ScrollingFrame default (true):
	-- this is a horizontally-scrolling strip, and the whole point of clipping
	-- is that only the currently-scrolled-into-view slice of the (much wider)
	-- node row shows. Turning it off -- tried briefly while chasing the avatar
	-- visibility bug -- let the ENTIRE node row + path line render unclipped,
	-- spilling out past the panel. The real avatar bug turned out to be the
	-- currentTheme crash below, not clipping, so this stays at the default.
	journeyMapScroll.Parent = journeyPanel

	-- A thin path line behind the nodes, purely decorative -- gives the "walk
	-- along a road" read even before the avatar marker is on top of it.
	local journeyStagesHolder = Instance.new("Frame")
	journeyStagesHolder.Size = UDim2.new(0, 0, 1, 0)
	journeyStagesHolder.AutomaticSize = Enum.AutomaticSize.X
	journeyStagesHolder.BackgroundTransparency = 1
	journeyStagesHolder.ZIndex = 22
	journeyStagesHolder.Parent = journeyMapScroll

	-- LANDMARK PATH: a ground line the landmarks stand ON, not a line that
	-- cuts through their middle -- moved from mid-height (0.5 scale) down
	-- to just under where every landmark's own bottom edge sits (each
	-- landmark is anchored to the bottom of its NODE_SIZE-tall node, see
	-- the node-building loop below). Parented INSIDE journeyStagesHolder
	-- (not journeyMapScroll) and sized to 100% of it, so it automatically
	-- spans exactly the row of nodes -- no matter how wide that row ends
	-- up being -- instead of a hardcoded guess.
	local journeyPathLine = Instance.new("Frame")
	journeyPathLine.Size = UDim2.new(1, 0, 0, 4)
	journeyPathLine.Position = UDim2.new(0, 0, 0.5, NODE_SIZE / 2 - 6)
	journeyPathLine.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	journeyPathLine.BorderSizePixel = 0
	journeyPathLine.ZIndex = 21
	journeyPathLine.Parent = journeyStagesHolder
	roundCorner(journeyPathLine, 2)

	local journeyStagesLayout = Instance.new("UIListLayout")
	journeyStagesLayout.FillDirection = Enum.FillDirection.Horizontal
	journeyStagesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	journeyStagesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	journeyStagesLayout.Padding = UDim.new(0, 30)
	journeyStagesLayout.Parent = journeyStagesHolder
	local JOURNEY_NODE_PADDING = 30 -- must match journeyStagesLayout.Padding above

	-- The player's actual avatar, standing on the map -- fetched once
	-- (yielding call, so it's off in a task.spawn) and applied whenever ready.
	local journeyAvatarMarker = Instance.new("ImageLabel")
	journeyAvatarMarker.Name = "AvatarMarker"
	journeyAvatarMarker.Size = UDim2.new(0, 46, 0, 46)
	journeyAvatarMarker.AnchorPoint = Vector2.new(0.5, 1)
	journeyAvatarMarker.Position = UDim2.new(0, 0, 0.5, -NODE_SIZE / 2 - 8)
	journeyAvatarMarker.BackgroundColor3 = Color3.fromRGB(250, 240, 220)
	journeyAvatarMarker.Image = ""
	journeyAvatarMarker.ZIndex = 24
	journeyAvatarMarker.Parent = journeyMapScroll
	roundCorner(journeyAvatarMarker, 23)

	-- Fallback glyph: always visible until (if ever) the real avatar thumbnail
	-- loads. Covers the case where GetUserThumbnailAsync is slow, fails, or
	-- returns a placeholder (a known quirk of solo Play-testing in Studio) --
	-- the marker should never just be an empty/invisible square.
	local journeyAvatarFallback = Instance.new("TextLabel")
	journeyAvatarFallback.Size = UDim2.fromScale(1, 1)
	journeyAvatarFallback.BackgroundTransparency = 1
	journeyAvatarFallback.Font = Enum.Font.GothamBold
	journeyAvatarFallback.TextSize = 24
	journeyAvatarFallback.Text = "🧑"
	journeyAvatarFallback.ZIndex = 25
	journeyAvatarFallback.Parent = journeyAvatarMarker

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and content and content ~= "" then
			journeyAvatarMarker.Image = content
			journeyAvatarFallback.Visible = false
		end
	end)

	-- (No continuous idle-bob animation -- it would fight with the walk/hop
	-- tween below for control of the same Position property. The hop-on-walk
	-- animation is enough life for now; a proper idle bob would need its own
	-- separate UI element layered under a static-position parent to avoid
	-- that conflict, which isn't worth the complexity yet.)

	local journeyStageNodes = {} -- flat array, index 1..(PREVIEW_NIGHTS*ROUNDS_PER_NIGHT), in map order
	local layoutOrderCounter = 0
	-- xCursor tracks each node's left edge as we build the row, mirroring
	-- exactly what journeyStagesLayout (a UIListLayout) will compute. We use
	-- this instead of reading node.Position back after the fact -- reading a
	-- UIListLayout-controlled Position depends on the layout engine having
	-- already run a pass over this (currently invisible) overlay, which isn't
	-- guaranteed the first time the map is opened. A precomputed value is
	-- always correct, immediately.
	local xCursor = 0

	for night = 1, PREVIEW_NIGHTS do
		if night > 1 then
			local spacer = Instance.new("Frame")
			spacer.Size = UDim2.new(0, NIGHT_GAP_EXTRA, 1, 0)
			spacer.BackgroundTransparency = 1
			layoutOrderCounter = layoutOrderCounter + 1
			spacer.LayoutOrder = layoutOrderCounter
			spacer.Parent = journeyStagesHolder
			xCursor = xCursor + NIGHT_GAP_EXTRA + JOURNEY_NODE_PADDING
		end

		for round = 1, ROUNDS_PER_NIGHT do
			layoutOrderCounter = layoutOrderCounter + 1

			-- `container` plays the same layout role the old plain-circle
			-- `node` Frame did (same size, same LayoutOrder, same thing
			-- addTooltip hovers/measures) -- it's just transparent now, with
			-- the actual landmark art built as children anchored to its
			-- bottom edge, standing on journeyPathLine.
			local container = Instance.new("Frame")
			container.Size = UDim2.new(0, NODE_SIZE, 0, NODE_SIZE)
			container.BackgroundTransparency = 1
			container.LayoutOrder = layoutOrderCounter
			container.ZIndex = 22
			container.Parent = journeyStagesHolder

			local shadow = Instance.new("Frame")
			shadow.Name = "Shadow"
			shadow.Size = UDim2.new(0, 40, 0, 8)
			shadow.AnchorPoint = Vector2.new(0.5, 0)
			shadow.Position = UDim2.new(0.5, 0, 1, -4)
			shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			shadow.BackgroundTransparency = 0.6
			shadow.BorderSizePixel = 0
			shadow.ZIndex = 22
			shadow.Parent = container
			roundCorner(shadow, 4)

			-- A soft ring behind the landmark, shown only for the CURRENT
			-- stage (see refreshJourneyImpl) -- built once here rather than
			-- Instance.new()'d on every refresh.
			local ring = Instance.new("Frame")
			ring.Name = "CurrentRing"
			ring.Size = UDim2.new(0, 64, 0, 64)
			ring.AnchorPoint = Vector2.new(0.5, 1)
			ring.Position = UDim2.new(0.5, 0, 1, -6)
			ring.BackgroundTransparency = 1
			ring.BorderSizePixel = 0
			ring.ZIndex = 21
			ring.Visible = false
			ring.Parent = container
			roundCorner(ring, 32)
			local ringStroke = Instance.new("UIStroke")
			ringStroke.Color = LANDMARK_COLORS.current
			ringStroke.Thickness = 2
			ringStroke.Transparency = 0.25
			ringStroke.Parent = ring

			local entryKind
			local lanternGlow, tableShape, gateShape

			if round == 1 then
				-- Small Round -- a lantern post, warmest/simplest landmark.
				entryKind = "lantern"

				local lanternPost = Instance.new("Frame")
				lanternPost.Name = "LanternPost"
				lanternPost.Size = UDim2.new(0, 4, 0, 30)
				lanternPost.AnchorPoint = Vector2.new(0.5, 1)
				lanternPost.Position = UDim2.new(0.5, 0, 1, -8)
				lanternPost.BackgroundColor3 = Color3.fromRGB(107, 90, 62)
				lanternPost.BorderSizePixel = 0
				lanternPost.ZIndex = 22
				lanternPost.Parent = container

				lanternGlow = Instance.new("Frame")
				lanternGlow.Name = "LanternGlow"
				lanternGlow.Size = UDim2.new(0, 16, 0, 16)
				lanternGlow.AnchorPoint = Vector2.new(0.5, 1)
				lanternGlow.Position = UDim2.new(0.5, 0, 1, -34)
				lanternGlow.BackgroundColor3 = LANDMARK_COLORS.lanternGlow
				lanternGlow.BorderSizePixel = 0
				lanternGlow.ZIndex = 23
				lanternGlow.Parent = container
				roundCorner(lanternGlow, 8)
			elseif round < ROUNDS_PER_NIGHT then
				-- Big Round -- a table (never a Boss Round; only the very
				-- last round of a Night ever is, see the `else` branch).
				entryKind = "table"

				tableShape = Instance.new("Frame")
				tableShape.Name = "Table"
				tableShape.Size = UDim2.new(0, 44, 0, 18)
				tableShape.AnchorPoint = Vector2.new(0.5, 1)
				tableShape.Position = UDim2.new(0.5, 0, 1, -8)
				tableShape.BackgroundColor3 = LANDMARK_COLORS.table
				tableShape.BorderSizePixel = 0
				tableShape.ZIndex = 22
				tableShape.Parent = container
				roundCorner(tableShape, 6)

				local legLeft = Instance.new("Frame")
				legLeft.Size = UDim2.new(0, 4, 0, 10)
				legLeft.Position = UDim2.new(0, 4, 1, 0)
				legLeft.BackgroundColor3 = LANDMARK_COLORS.table
				legLeft.BorderSizePixel = 0
				legLeft.ZIndex = 22
				legLeft.Parent = tableShape
				local legRight = legLeft:Clone()
				legRight.Position = UDim2.new(1, -8, 1, 0)
				legRight.Parent = tableShape
			else
				-- Last round of the Night -- normally the Boss Round (an
				-- ornate gate), but Boss Rounds can be turned off for a
				-- Difficulty Tier (see bossRoundsEnabledFor), in which case
				-- it plays exactly like a Big Round. Both shapes are built
				-- up front; refreshJourneyImpl toggles which one is Visible
				-- based on the CURRENT run's live setting, since that can
				-- only be known once a run has actually started.
				entryKind = "dual"

				tableShape = Instance.new("Frame")
				tableShape.Name = "Table"
				tableShape.Size = UDim2.new(0, 44, 0, 18)
				tableShape.AnchorPoint = Vector2.new(0.5, 1)
				tableShape.Position = UDim2.new(0.5, 0, 1, -8)
				tableShape.BackgroundColor3 = LANDMARK_COLORS.table
				tableShape.BorderSizePixel = 0
				tableShape.ZIndex = 22
				tableShape.Visible = false
				tableShape.Parent = container
				roundCorner(tableShape, 6)

				gateShape = Instance.new("Frame")
				gateShape.Name = "Gate"
				gateShape.Size = UDim2.new(0, 44, 0, 54)
				gateShape.AnchorPoint = Vector2.new(0.5, 1)
				gateShape.Position = UDim2.new(0.5, 0, 1, -6)
				gateShape.BackgroundColor3 = LANDMARK_COLORS.gate
				gateShape.BorderSizePixel = 0
				gateShape.ZIndex = 22
				gateShape.Parent = container
				roundCorner(gateShape, 20)

				local gateCrown = Instance.new("TextLabel")
				gateCrown.Size = UDim2.new(0, 24, 0, 24)
				gateCrown.AnchorPoint = Vector2.new(0.5, 1)
				gateCrown.Position = UDim2.new(0.5, 0, 0, -4)
				gateCrown.BackgroundTransparency = 1
				gateCrown.Font = Enum.Font.GothamBold
				gateCrown.TextSize = 18
				gateCrown.Text = "👑"
				gateCrown.ZIndex = 23
				gateCrown.Parent = gateShape
			end

			if night == 1 and round == 1 then
				-- Underneath everything else, so it doesn't shift layout order.
				local nightLabel = Instance.new("TextLabel")
				nightLabel.Size = UDim2.new(0, 90, 0, 20)
				nightLabel.Position = UDim2.new(0.5, -45, 0, -30)
				nightLabel.BackgroundTransparency = 1
				nightLabel.Font = Enum.Font.GothamBold
				nightLabel.TextSize = 13
				nightLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
				nightLabel.Text = "Night 1"
				nightLabel.ZIndex = 22
				nightLabel.Parent = container
			end

			-- The tag beneath each landmark ("R1", "R1 ✓", boss crown, ...) --
			-- what used to be centered TEXT inside a circle is now a small
			-- caption below the art. The old inline target-score number is
			-- gone; describeStage's hover tooltip (below) already shows it,
			-- so it's not lost, just moved off the crowded map itself.
			local tagLabel = Instance.new("TextLabel")
			tagLabel.Size = UDim2.new(0, NODE_SIZE, 0, 16)
			tagLabel.AnchorPoint = Vector2.new(0.5, 0)
			tagLabel.Position = UDim2.new(0.5, 0, 1, 4)
			tagLabel.BackgroundTransparency = 1
			tagLabel.Font = Enum.Font.GothamBold
			tagLabel.TextSize = 12
			tagLabel.TextColor3 = Color3.fromRGB(230, 215, 195)
			tagLabel.Text = string.format("R%d", round)
			tagLabel.ZIndex = 23
			tagLabel.Parent = container

			table.insert(journeyStageNodes, {
				node = container,
				tagLabel = tagLabel,
				ring = ring,
				kind = entryKind,
				lanternGlow = lanternGlow,
				tableShape = tableShape,
				gateShape = gateShape,
				night = night,
				round = round,
				centerX = xCursor + NODE_SIZE / 2,
			})
			xCursor = xCursor + NODE_SIZE + JOURNEY_NODE_PADDING

			-- Night labels for nights 2/3 -- placed after node 1 of that night
			-- exists, same idea as Night 1's label above.
			if round == 1 and night > 1 then
				local nightLabel = Instance.new("TextLabel")
				nightLabel.Size = UDim2.new(0, 90, 0, 20)
				nightLabel.Position = UDim2.new(0.5, -45, 0, -30)
				nightLabel.BackgroundTransparency = 1
				nightLabel.Font = Enum.Font.GothamBold
				nightLabel.TextSize = 13
				nightLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
				nightLabel.Text = string.format("Night %d", night)
				nightLabel.ZIndex = 22
				nightLabel.Parent = container
			end
		end
	end

	-- JOURNEY FEATURE: per-node hover tooltip -- the full Boss name +
	-- description once known (this Night's Boss only -- future Nights
	-- haven't been rolled yet, see RunState.startRound), or the target
	-- score for a plain round. `text` is a 0-arg function (addTooltip
	-- supports this) so it always reflects the CURRENT server state at the
	-- moment you actually hover, not whatever was true when the map was
	-- built.
	local function describeStage(entry)
		local latestState = getLatestState()
		local currentNight = (latestState and latestState.night) or 1
		local bossRoundsEnabled = bossRoundsEnabledFor(latestState)
		local isBoss = bossRoundsEnabled and BossRounds.isBossRound(entry.round, ROUNDS_PER_NIGHT)
		local target = RunStateEngine.targetScoreFor(entry.night, entry.round, ROUNDS_PER_NIGHT)

		if not isBoss then
			return string.format("Round %d, Night %d\nTarget Score: %d", entry.round, entry.night, target)
		end

		if not bossRoundsEnabled then
			return "Boss Rounds are off this run."
		end

		if entry.night == currentNight and latestState and latestState.nightBossModifier then
			local modifier = latestState.nightBossModifier
			return string.format("👑 %s\n%s\nTarget Score: %d", modifier.name, modifier.description, target)
		end

		return string.format("👑 Boss Round, Night %d\nRevealed once you reach this Night.\nTarget Score: %d", entry.night, target)
	end

	if addTooltip then
		for _, entry in ipairs(journeyStageNodes) do
			addTooltip(entry.node, function()
				return describeStage(entry)
			end)
		end
	end

	-- JOURNEY FEATURE: info bar showing this Night's Boss, once known.
	-- Sits between the map and the Close button. (Used to also host a Skip
	-- button -- skipping now lives on its own dedicated screen, see
	-- ROUND SELECT FEATURE / Client/RoundSelect.lua -- so this bar is purely
	-- informational now.)
	local journeyInfoBar = Instance.new("Frame")
	journeyInfoBar.Size = UDim2.new(1, -30, 0, 92)
	journeyInfoBar.Position = UDim2.new(0, 15, 1, -152)
	journeyInfoBar.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	journeyInfoBar.ZIndex = 21
	journeyInfoBar.Parent = journeyPanel
	roundCorner(journeyInfoBar, 10)

	local journeyBossInfoLabel = Instance.new("TextLabel")
	journeyBossInfoLabel.Size = UDim2.new(1, -24, 1, -16)
	journeyBossInfoLabel.Position = UDim2.new(0, 12, 0, 8)
	journeyBossInfoLabel.BackgroundTransparency = 1
	journeyBossInfoLabel.Font = Enum.Font.Gotham
	journeyBossInfoLabel.TextSize = 13
	journeyBossInfoLabel.TextColor3 = Color3.fromRGB(230, 215, 195)
	journeyBossInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
	journeyBossInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
	journeyBossInfoLabel.TextWrapped = true
	journeyBossInfoLabel.Text = ""
	journeyBossInfoLabel.ZIndex = 22
	journeyBossInfoLabel.Parent = journeyInfoBar

	local function refreshInfoBar()
		local latestState = getLatestState()
		local bossRoundsEnabled = bossRoundsEnabledFor(latestState)

		if not bossRoundsEnabled then
			journeyBossInfoLabel.Text = "Boss Rounds are off this run -- every round plays the same."
		elseif latestState and latestState.nightBossModifier then
			local modifier = latestState.nightBossModifier
			journeyBossInfoLabel.Text = string.format(
				"👑 This Night's Boss (Round %d): %s\n%s",
				ROUNDS_PER_NIGHT, modifier.name, modifier.description
			)
		else
			journeyBossInfoLabel.Text = "This Night's Boss hasn't been revealed yet."
		end
	end

	local journeyCloseButton = Instance.new("TextButton")
	journeyCloseButton.Size = UDim2.new(0, 140, 0, 40)
	journeyCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	journeyCloseButton.Font = Enum.Font.GothamBold
	journeyCloseButton.TextSize = 16
	journeyCloseButton.Text = "Close"
	journeyCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	journeyCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	journeyCloseButton.ZIndex = 21
	journeyCloseButton.Parent = journeyPanel
	polishButton(journeyCloseButton, 12)

	journeyCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		journeyBackdrop.Visible = false
	end)

	-- lastJourneyStageKey: which stage the avatar was last shown on, so we only
	-- play the walk animation when it actually CHANGES (not every time the
	-- overlay happens to refresh while you're on the same stage).
	local lastJourneyStageKey = nil

	local function refreshJourneyImpl(animateWalk)
		local latestState = getLatestState()
		local currentTheme = getCurrentTheme()
		local currentNight = (latestState and latestState.night) or 1
		local currentRound = (latestState and latestState.round) or 1

		local bossRoundsEnabled = bossRoundsEnabledFor(latestState)

		local targetNode = nil
		for _, entry in ipairs(journeyStageNodes) do
			local isPast = (entry.night < currentNight) or (entry.night == currentNight and entry.round < currentRound)
			local isCurrent = (entry.night == currentNight and entry.round == currentRound)
			local isBoss = bossRoundsEnabled and BossRounds.isBossRound(entry.round, ROUNDS_PER_NIGHT)

			-- LANDMARK PATH: the dual-shape "R3" entry only knows whether
			-- it's actually a Boss Round once a run (and its Difficulty
			-- Tier) is live -- toggle which built shape is showing here,
			-- every refresh, rather than guessing at build time.
			if entry.kind == "dual" then
				entry.tableShape.Visible = not isBoss
				entry.gateShape.Visible = isBoss
			end

			-- Which Instance actually carries this entry's landmark color:
			-- the lantern's glow, the table (legs share its color via
			-- Clone, see the build loop), or whichever of table/gate is
			-- currently showing.
			local colorTarget = entry.lanternGlow
				or (entry.kind == "dual" and (isBoss and entry.gateShape or entry.tableShape))
				or entry.tableShape
			local naturalColor = (entry.kind == "lantern" and LANDMARK_COLORS.lanternGlow)
				or (isBoss and LANDMARK_COLORS.gate or LANDMARK_COLORS.table)

			if colorTarget then
				local newColor = isPast and LANDMARK_COLORS.done
					or (isCurrent and (currentTheme.colors.cardSelected or LANDMARK_COLORS.current) or naturalColor)
				colorTarget.BackgroundColor3 = newColor
				-- The table's two legs are separate child Frames (see the
				-- build loop's legLeft/legRight) so they don't inherit the
				-- tabletop's color automatically -- keep them in sync so a
				-- done/current table doesn't end up with mismatched legs.
				if colorTarget.Name == "Table" then
					for _, child in ipairs(colorTarget:GetChildren()) do
						if child:IsA("Frame") then
							child.BackgroundColor3 = newColor
						end
					end
				end
			end

			entry.ring.Visible = isCurrent
			entry.tagLabel.Text = isPast and string.format("R%d ✓", entry.round) or (isCurrent and "You are here" or string.format("R%d%s", entry.round, isBoss and " 👑" or ""))

			if isCurrent then
				targetNode = entry
			end
		end

		if targetNode then
			local stageKey = targetNode.night .. "-" .. targetNode.round
			local targetX = targetNode.centerX
			local newPosition = UDim2.new(0, targetX, journeyAvatarMarker.Position.Y.Scale, journeyAvatarMarker.Position.Y.Offset)

			if animateWalk and lastJourneyStageKey and lastJourneyStageKey ~= stageKey then
				-- A little hop while walking over: up, across, down.
				local hopUp = journeyAvatarMarker.Position - UDim2.new(0, 0, 0, 20)
				tweenTo(journeyAvatarMarker, { Position = UDim2.new(0, journeyAvatarMarker.Position.X.Offset, hopUp.Y.Scale, hopUp.Y.Offset) }, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				task.delay(0.15, function()
					tweenTo(journeyAvatarMarker, { Position = UDim2.new(0, targetX, hopUp.Y.Scale, hopUp.Y.Offset) }, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				end)
				task.delay(0.5, function()
					tweenTo(journeyAvatarMarker, newPosition, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end)
			else
				journeyAvatarMarker.Position = newPosition
			end

			lastJourneyStageKey = stageKey
		end

		refreshInfoBar()
	end

	local function refreshJourney()
		refreshJourneyImpl(true)
	end

	local function openJourney()
		playClickSfx()
		refreshJourneyImpl(false) -- snap to the right stage on open, no walk animation
		journeyBackdrop.Visible = true
		-- Scroll so the current stage is in view.
		if journeyAvatarMarker.Position.X.Offset > 0 then
			journeyMapScroll.CanvasPosition = Vector2.new(math.max(0, journeyAvatarMarker.Position.X.Offset - 200), 0)
		end
	end

	journeyButton.MouseButton1Click:Connect(openJourney)
	menuJourneyButton.MouseButton1Click:Connect(openJourney)

	return {
		journeyBackdrop = journeyBackdrop,
		refreshJourney = refreshJourney,
	}
end
