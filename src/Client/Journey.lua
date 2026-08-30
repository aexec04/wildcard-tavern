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

	-- POLISH PASS 2: flat single-color Frames read as paper cutouts next to
	-- the concept art's softer, shaded illustration style. Roblox Frames
	-- have no real lighting, so the standard fake is a UIGradient running
	-- lighter-to-darker across the shape -- SHADING_ROTATION = 90 points it
	-- top (lighter, "catching the light") to bottom (darker, "in shadow"),
	-- same direction on every landmark so the whole map reads as one
	-- consistent light source instead of each piece doing its own thing.
	local SHADING_ROTATION = 90

	local function lighten(color, amount)
		return Color3.new(
			math.min(1, color.R + amount),
			math.min(1, color.G + amount),
			math.min(1, color.B + amount)
		)
	end

	local function darken(color, amount)
		return Color3.new(
			math.max(0, color.R - amount),
			math.max(0, color.G - amount),
			math.max(0, color.B - amount)
		)
	end

	-- Sets `frame`'s flat color AND (re)builds its "Shading" UIGradient from
	-- that same color, so the two can never drift apart. Safe to call both
	-- at build time (creates the gradient) and from refreshJourneyImpl on
	-- every done/current recolor (finds and updates the existing one) --
	-- one function, one source of truth, instead of the gradient silently
	-- keeping stale colors after a recolor like a naively-added UIGradient
	-- would.
	local function applyLandmarkColor(frame, color)
		frame.BackgroundColor3 = color
		local gradient = frame:FindFirstChild("Shading")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "Shading"
			gradient.Rotation = SHADING_ROTATION
			gradient.Parent = frame
		end
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighten(color, 0.18)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, darken(color, 0.14)),
		})
	end

	-- The flat-bottomed "Base" piece under a dome is deliberately NOT given
	-- its own gradient (a tiny sliver doesn't have room to show one) --
	-- instead it's just held a flat shade darker than whatever the dome's
	-- current color is, standing in for it being the shape's grounded,
	-- shadowed underside. Recomputed alongside the dome on every recolor.
	local function applyBaseShadeColor(frame, color)
		frame.BackgroundColor3 = darken(color, 0.2)
	end

	-- POLISH PASS: a "standing" silhouette anchored to the bottom of
	-- `container` -- a flat-bottomed base with a rounded/domed top,
	-- instead of a single uniformly-rounded pill. Reads much closer to an
	-- actual bench/gate silhouette (and to the Landmark Path concept art
	-- this redesign was picked from) than a plain rounded rect does.
	-- `dome`'s own BackgroundColor3 is what refreshJourneyImpl actually
	-- sets on done/current transitions (via applyLandmarkColor, POLISH
	-- PASS 2 above) -- `base` is a plain child Frame shaded to match at
	-- build time, kept in sync by the existing "propagate color to Frame
	-- children" step in refreshJourneyImpl (same trick the old table legs
	-- relied on).
	local function buildArchLandmark(container, name, width, height, bottomInset, color, domeRadius)
		local dome = Instance.new("Frame")
		dome.Name = name
		dome.Size = UDim2.new(0, width, 0, height)
		dome.AnchorPoint = Vector2.new(0.5, 1)
		dome.Position = UDim2.new(0.5, 0, 1, -bottomInset)
		dome.BorderSizePixel = 0
		dome.ZIndex = 22
		dome.Parent = container
		roundCorner(dome, domeRadius)
		applyLandmarkColor(dome, color)

		local base = Instance.new("Frame")
		base.Name = "Base"
		base.Size = UDim2.new(1, 0, 0, math.min(height, domeRadius))
		base.AnchorPoint = Vector2.new(0.5, 1)
		base.Position = UDim2.new(0.5, 0, 1, 0)
		base.BorderSizePixel = 0
		base.ZIndex = 22
		base.Parent = dome
		applyBaseShadeColor(base, color)

		return dome
	end

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

	-- BUGFIX: on a small game viewport (a small Studio test window, or just
	-- a laptop screen) `0.55` of the viewport's height could shrink small
	-- enough that journeyMapScroll below (panelHeight - 230, see its own
	-- comment) came out barely bigger than NODE_SIZE (88px) -- sometimes
	-- even smaller. ClipsDescendants then silently chopped the whole
	-- landmark row down to nothing, leaving only the panel chrome
	-- (title/subtitle/info bar/Close) visible -- exactly the "looks cut
	-- out" symptom this map was redesigned to fix, and the redesign alone
	-- didn't touch this sizing math so it was still possible to hit. A
	-- UISizeConstraint guarantees the panel is NEVER shorter than 480px
	-- regardless of viewport size, so journeyMapScroll always has at least
	-- 480-230=250px to work with -- comfortably more than the 88px a node
	-- needs -- no matter how small the window is. Anchored+centered
	-- instead of top-left-positioned so that floor can't push the panel
	-- off the bottom edge of a small screen.
	local journeyPanel = Instance.new("Frame")
	journeyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	journeyPanel.Size = UDim2.fromScale(0.7, 0.55)
	journeyPanel.Position = UDim2.fromScale(0.5, 0.5)
	journeyPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	journeyPanel.ZIndex = 21
	journeyPanel.Parent = journeyBackdrop
	polishPanel(journeyPanel, 16)
	addSoftShadow(journeyPanel, 18)

	local journeyPanelMinSize = Instance.new("UISizeConstraint")
	journeyPanelMinSize.MinSize = Vector2.new(560, 480)
	journeyPanelMinSize.Parent = journeyPanel

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
	-- BUGFIX (real root cause of the missing landmarks, found via the
	-- [JourneyDiag] prints): CanvasSize was left on AutomaticCanvasSize.X,
	-- chained through journeyStagesHolder's own AutomaticSize.X below.
	-- Diagnosing a live game showed that chain never actually resolving --
	-- CanvasSize stayed permanently {0,0} and the very first node ended up
	-- laid out at a nonsense screen position, clipped out of view by
	-- journeyMapScroll's ClipsDescendants. Rather than depend on that
	-- automatic-size chain settling at all, CanvasSize/journeyStagesHolder's
	-- width are now both set explicitly further down (see "manually size
	-- the map strip" below), from the same xCursor total this loop already
	-- computes -- deterministic on the very first frame, no engine
	-- settling required.
	journeyMapScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- set for real once xCursor is final, below
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
	-- Width set for real once xCursor is final, below -- see the CanvasSize
	-- comment above for why this isn't AutomaticSize.X anymore.
	journeyStagesHolder.Size = UDim2.new(0, 0, 1, 0)
	journeyStagesHolder.BackgroundTransparency = 1
	journeyStagesHolder.ZIndex = 22
	journeyStagesHolder.Parent = journeyMapScroll

	-- BUGFIX (the REAL cause of the missing landmarks -- found via the
	-- [JourneyDiag] prints, which caught node1 sitting ~1242px to the
	-- right of where it should be, almost exactly content-width + one
	-- padding gap): journeyPathLine used to be a direct child of
	-- journeyStagesHolder, the SAME frame the UIListLayout below lives on.
	-- UIListLayout lays out every GuiObject sibling it has, with no way to
	-- opt one out -- it doesn't know "purely decorative" from "a real
	-- node". journeyPathLine has no LayoutOrder (defaults to 0, i.e.
	-- first) and a Size of "100% of the holder's width", so the layout
	-- treated it as the very first list item and gave it a slot roughly as
	-- wide as the ENTIRE map -- shoving every actual node after it
	-- (starting with node 1) off to the right by that same width, clipped
	-- out of view. Fix: give the actual list items (nodes + night
	-- spacers) their OWN inner row Frame with the UIListLayout on IT
	-- instead -- journeyPathLine stays a plain, non-laid-out sibling in
	-- the outer holder, still sized 1,0 so it spans the same full content
	-- width once that's set below.
	--
	-- POLISH PASS: this is now just an invisible strip that HOLDS a row of
	-- small dash Frames (built further down, once the real content width
	-- is known) instead of being one solid bar itself -- matches the
	-- dashed "road" line from the concept art instead of a plain line.
	local journeyPathLine = Instance.new("Frame")
	journeyPathLine.Size = UDim2.new(1, 0, 0, 4)
	journeyPathLine.Position = UDim2.new(0, 0, 0.5, NODE_SIZE / 2 - 6)
	journeyPathLine.BackgroundTransparency = 1
	journeyPathLine.ZIndex = 21
	journeyPathLine.Parent = journeyStagesHolder

	-- The actual row of nodes/spacers lives in here, NOT directly in
	-- journeyStagesHolder -- see the BUGFIX comment above.
	local journeyStagesRow = Instance.new("Frame")
	journeyStagesRow.Size = UDim2.fromScale(1, 1)
	journeyStagesRow.BackgroundTransparency = 1
	journeyStagesRow.ZIndex = 22
	journeyStagesRow.Parent = journeyStagesHolder

	local journeyStagesLayout = Instance.new("UIListLayout")
	journeyStagesLayout.FillDirection = Enum.FillDirection.Horizontal
	journeyStagesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	journeyStagesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	journeyStagesLayout.Padding = UDim.new(0, 30)
	journeyStagesLayout.Parent = journeyStagesRow
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
			spacer.Parent = journeyStagesRow -- the row, not the holder -- see the BUGFIX comment above
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
			container.Parent = journeyStagesRow -- the row, not the holder -- see the BUGFIX comment above

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
			local lanternGlow, lanternHalo, tableShape, gateShape

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

				-- POLISH PASS: a soft glow halo behind the lit orb -- a
				-- bigger, mostly-transparent circle sharing the glow's own
				-- center, faking the warm radial-glow look from the concept
				-- art (Roblox Frames can't do true radial gradients).
				-- Recolored alongside the glow itself on done/current
				-- transitions, see refreshJourneyImpl.
				lanternHalo = Instance.new("Frame")
				lanternHalo.Name = "LanternHalo"
				lanternHalo.Size = UDim2.new(0, 30, 0, 30)
				lanternHalo.AnchorPoint = Vector2.new(0.5, 1)
				lanternHalo.Position = UDim2.new(0.5, 0, 1, -27)
				lanternHalo.BackgroundColor3 = LANDMARK_COLORS.lanternGlow
				lanternHalo.BackgroundTransparency = 0.65
				lanternHalo.BorderSizePixel = 0
				lanternHalo.ZIndex = 22
				lanternHalo.Parent = container
				roundCorner(lanternHalo, 15)

				lanternGlow = Instance.new("Frame")
				lanternGlow.Name = "LanternGlow"
				lanternGlow.Size = UDim2.new(0, 16, 0, 16)
				lanternGlow.AnchorPoint = Vector2.new(0.5, 1)
				lanternGlow.Position = UDim2.new(0.5, 0, 1, -34)
				lanternGlow.BorderSizePixel = 0
				lanternGlow.ZIndex = 23
				lanternGlow.Parent = container
				roundCorner(lanternGlow, 8)
				applyLandmarkColor(lanternGlow, LANDMARK_COLORS.lanternGlow)
			elseif round < ROUNDS_PER_NIGHT then
				-- Big Round -- a bench (never a Boss Round; only the very
				-- last round of a Night ever is, see the `else` branch).
				entryKind = "table"
				tableShape = buildArchLandmark(container, "Table", 44, 30, 8, LANDMARK_COLORS.table, 13)
			else
				-- Last round of the Night -- normally the Boss Round (an
				-- ornate gate), but Boss Rounds can be turned off for a
				-- Difficulty Tier (see bossRoundsEnabledFor), in which case
				-- it plays exactly like a Big Round. Both shapes are built
				-- up front; refreshJourneyImpl toggles which one is Visible
				-- based on the CURRENT run's live setting, since that can
				-- only be known once a run has actually started.
				entryKind = "dual"

				tableShape = buildArchLandmark(container, "Table", 44, 30, 8, LANDMARK_COLORS.table, 13)
				tableShape.Visible = false

				gateShape = buildArchLandmark(container, "Gate", 44, 54, 6, LANDMARK_COLORS.gate, 22)

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
				lanternHalo = lanternHalo,
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

	-- Manually size the map strip now that xCursor holds the real total
	-- width (last node's left edge + NODE_SIZE, trailing padding trimmed
	-- off since there's no node after it to pad toward). Both
	-- journeyStagesHolder's own width AND journeyMapScroll's CanvasSize
	-- need this -- see the BUGFIX comments where each was created.
	local journeyContentWidth = math.max(0, xCursor - JOURNEY_NODE_PADDING)
	journeyStagesHolder.Size = UDim2.new(0, journeyContentWidth, 1, 0)
	journeyMapScroll.CanvasSize = UDim2.new(0, journeyContentWidth, 0, 0)

	-- POLISH PASS: the dashed road line itself -- built here rather than
	-- up where journeyPathLine was created because it needs the real,
	-- final journeyContentWidth to know how many dashes to lay down.
	do
		local DASH_WIDTH, DASH_GAP = 10, 8
		local dashSpan = DASH_WIDTH + DASH_GAP
		local dashCount = math.max(1, math.floor(journeyContentWidth / dashSpan))
		for i = 0, dashCount do
			local dash = Instance.new("Frame")
			dash.Size = UDim2.new(0, DASH_WIDTH, 1, 0)
			dash.Position = UDim2.new(0, i * dashSpan, 0, 0)
			dash.BackgroundColor3 = Color3.fromRGB(96, 78, 56)
			dash.BorderSizePixel = 0
			dash.ZIndex = 21
			dash.Parent = journeyPathLine
			roundCorner(dash, 2)
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
				-- POLISH PASS 2: goes through applyLandmarkColor now instead
				-- of a bare BackgroundColor3 assignment, so the shape's
				-- "Shading" UIGradient (see the POLISH PASS 2 comment up by
				-- buildArchLandmark) gets recomputed from the NEW color too
				-- -- otherwise a done/current recolor would leave the
				-- gradient showing shades of whatever color the shape was
				-- built with, drifting out of sync with its own flat base
				-- color.
				applyLandmarkColor(colorTarget, newColor)
				-- POLISH PASS: buildArchLandmark's "Base" piece (the flat
				-- bottom under the dome, for both the bench and the gate)
				-- is a separate child Frame that doesn't inherit its dome's
				-- color automatically -- keep it in sync (via the same
				-- darker-shade rule it was built with) so a done/current
				-- landmark doesn't end up with a mismatched base.
				for _, child in ipairs(colorTarget:GetChildren()) do
					if child:IsA("Frame") and child.Name == "Base" then
						applyBaseShadeColor(child, newColor)
					end
				end
				-- The lantern's glow halo is a separate sibling Frame, not
				-- a child of lanternGlow, so it needs its own explicit sync
				-- -- stays a flat translucent tint on purpose (see its
				-- build-time comment), not shaded.
				if entry.lanternHalo then
					entry.lanternHalo.BackgroundColor3 = newColor
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
