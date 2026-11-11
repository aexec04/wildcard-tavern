--[[
	Client/RoundSelect.lua
	ROUND SELECT FEATURE: the screen shown whenever state.phase ==
	"roundSelect" -- at the very start of a run, and every time right after
	leaving the shop (see Server/init.server.lua). Shows the current
	Night's 3 rounds side by side as panels (mirroring the reference
	game's Small/Big/Boss Blind select screen): target score for each,
	this Night's Boss identity revealed on the Boss panel from Round 1
	onward (see RunState.startRound/state.nightBossModifier), and on
	whichever round you're actually ON right now -- Select (play it) or
	Skip (take that round's revealed Tag instead -- see Tags.lua/
	state.currentRoundSkipTag) buttons.

	Only the CURRENT round's Tag is ever shown -- a round's Tag is picked
	fresh the moment it actually starts (see RunState.startRound), not
	pre-rolled for the whole Night the way the Boss modifier is, so a
	round you haven't reached yet genuinely doesn't have one to preview.
	Its panel says so honestly instead of guessing.

	This is a ModuleScript (not a LocalScript), so it has no access to
	init.client.lua's locals -- everything it needs comes in via `deps`.
	Built once; render() calls rebuildRoundSelect(state) to refresh it
	whenever phase == "roundSelect" (same pattern as Shop.lua's
	rebuildShop).

	deps fields:
		root             -- Frame, roundSelectFrame's parent (the game's root UI frame)
		SIDEBAR_WIDTH     -- number, for the sidebar-aware horizontal layout
		polishPanel       -- function(instance, radius)
		polishButton      -- function(instance, radius)
		roundCorner       -- function(instance, radius)
		playClickSfx      -- function(volume?)
		tweenTo           -- function(instance, props, duration, easingStyle?, easingDirection?)
		addTooltip        -- function(button, text, align?) -- text can be a 0-arg function
		BossRounds        -- the Shared/Engine/BossRounds module
		RunStateEngine    -- the Shared/Engine/RunState module (for targetScoreFor)
		SelectRoundRemote -- RemoteEvent () -- confirm "play this round"
		SkipRoundRemote   -- RemoteEvent () -- skip this round for its Tag
		showRoundReward   -- function(amount) -- "+$X Tips" popup, reused for
		                     the Tip Jar Tag (and On the House Tag's Tips
		                     fallback)
		showUnlockPopup   -- function(name, description) -- reused for the
		                     On the House Tag's free-Patron grant
		showWarning       -- function(text) -- reused for the Sale Day
		                     Tag's confirmation (no dedicated "+X Tips"/
		                     "new item" moment fits a discount)
		getLatestState    -- function() -> latest state table or nil (live getter)

	Returns:
		{
			roundSelectFrame = Frame,
			rebuildRoundSelect = function(state, previousPhase),
			-- previousPhase: the caller's OWN previous state.phase (init.client.lua
			-- already tracks this every render as `lastPhase`) -- NOT something
			-- this module can infer for itself, since rebuildRoundSelect only
			-- ever gets called while phase == "roundSelect", so it never
			-- observes the "playing"/"shop" phases in between two visits to
			-- this screen. Passing the caller's real previous phase in is what
			-- lets the confirmed-skip check below tell "the round just
			-- advanced because you skipped it" apart from "the round just
			-- advanced because you played it, shopped, and came back" -- both
			-- change the night/round key, but only the former does it without
			-- ever leaving "roundSelect".
		}
]]

local ROUNDS_PER_NIGHT = 3 -- matches RunState.DefaultConfig.roundsPerNight, same client-side assumption Journey.lua already makes

return function(deps)
	local root = deps.root
	local SIDEBAR_WIDTH = deps.SIDEBAR_WIDTH
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local CardFit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CardFit"))
	local playClickSfx = deps.playClickSfx
	local tweenTo = deps.tweenTo
	local addTooltip = deps.addTooltip
	local BossRounds = deps.BossRounds
	local ContentArtRS = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
	local RoomArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RoomArt"))
	local TweenService = game:GetService("TweenService")

	-- Room-specific config: static name, accent color, and room art key per card.
	local BRONZE = Color3.fromRGB(205, 118, 52)
	local SILVER = Color3.fromRGB(225, 232, 245)
	local GOLD_ACCENT = Color3.fromRGB(255, 196, 40)
	local ROOM_CONFIGS = {
		{ roomId = "corner_table", roomName = "The Corner Table", accent = BRONZE     },
		{ roomId = "main_hall",    roomName = "The Main Hall",    accent = SILVER     },
		{ roomId = "back_room",    roomName = "The Back Room",    accent = GOLD_ACCENT },
	}

	-- Boss panel: set the scene image to show the boss portrait at full width.
	-- Falls back to the back_room scene art if the boss has no portrait yet,
	-- and to a plain dark panel if neither is available. The portrait fills the
	-- entire top image area -- no inset picture-in-picture.
	local function setBossArt(entry, bossId)
		if entry.bossArtId == bossId then return end
		entry.bossArtId = bossId
		if entry.round ~= ROUNDS_PER_NIGHT then return end
		if bossId then
			local artId = ContentArtRS.getImageId("boss_rounds", bossId)
			if artId then
				entry.sceneImage.Image = artId
				return
			end
		end
		-- Fallback: back_room scene art, then plain dark panel.
		local fallbackId = RoomArt["back_room"]
		entry.sceneImage.Image = (type(fallbackId) == "string" and fallbackId ~= "" and fallbackId ~= "rbxassetid://0") and fallbackId or ""
	end

	local RunStateEngine = deps.RunStateEngine
	local SelectRoundRemote = deps.SelectRoundRemote
	local SkipRoundRemote = deps.SkipRoundRemote
	local showRoundReward = deps.showRoundReward
	local showUnlockPopup = deps.showUnlockPopup
	local showWarning = deps.showWarning
	local getLatestState = deps.getLatestState
	local JourneyMap = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("JourneyMap"))
	local theme = JourneyMap.EndlessTheme
	local ENDLESS_ACCENT = Color3.fromRGB(theme.accent[1], theme.accent[2], theme.accent[3])
	local ENDLESS_BG = Color3.fromRGB(theme.background[1], theme.background[2], theme.background[3])
	local ENDLESS_SUB = Color3.fromRGB(theme.subtitle[1], theme.subtitle[2], theme.subtitle[3])

	-- Same "solid opaque panel that just covers everything" trick shopFrame
	-- uses (see Shop.lua) instead of hiding the game table underneath --
	-- render() only toggles .Visible, nothing about the table itself needs
	-- to change.
	local roundSelectFrame = Instance.new("Frame")
	roundSelectFrame.Name = "RoundSelect"
	-- Full width: the left stats panel only matters during a round, so Round Select covers it
	-- (Client/SidebarSlide.lua slides the panel away here and back in when a round starts).
	roundSelectFrame.Size = UDim2.new(1, -40, 1, 0)
	roundSelectFrame.Position = UDim2.new(0, 20, 0, 0)
	roundSelectFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	roundSelectFrame.Visible = false
	roundSelectFrame.ZIndex = 6 -- matches shopFrame -- see Shop.lua for why (beats the corner icon buttons)
	roundSelectFrame.Parent = root
	polishPanel(roundSelectFrame, 16, "wood")

	-- INPUT SINK: while Round Select is up, nothing underneath (hand cards,
	-- Deck widget, Play/Discard) may respond. Full-screen, invisible, Active
	-- so it swallows clicks. ZIndex 4 sits above the gameplay UI (1-3) and
	-- below the corner buttons (5+) so Settings/Volume stay usable.
	do
		local sink = Instance.new("Frame")
		sink.Name = "RoundSelectInputSink"
		sink.Size = UDim2.fromScale(1, 1)
		sink.BackgroundTransparency = 1
		sink.BorderSizePixel = 0
		sink.Active = true
		sink.ZIndex = 4
		sink.Visible = false
		sink.Parent = root
		local function sync()
			sink.Visible = roundSelectFrame.Visible
			root:SetAttribute("BannerAtBottom", roundSelectFrame.Visible) -- warnings sit just under the subtitle
			-- Real modal: the corner icon row (and its hover tooltips) is hidden while Round Select is up,
			-- so nothing behind the window can be reached. It returns when the window closes.
			local gui = root:FindFirstAncestorWhichIsA("LayerCollector") or root
			local row = gui:FindFirstChild("CornerIconRow", true)
			if row and row:IsA("GuiObject") then row.Visible = not roundSelectFrame.Visible end
			local tip = gui:FindFirstChild("Tooltip", true)
			if tip and tip:IsA("GuiObject") and roundSelectFrame.Visible then tip.Visible = false end
		end
		roundSelectFrame:GetPropertyChangedSignal("Visible"):Connect(sync)
		sync()
	end

	-- Full-panel table background behind everything. The frame's flat fill
	-- stays underneath as the fallback if the image is missing or fails to load.
	-- Edge darkening is a Color-only UIGradient on the image itself (it
	-- multiplies the picture: dark at the left/right edges, untouched in the
	-- centre where the cards sit). Transparency is never touched.
	do
		local bgId = ContentArtRS.getImageId("backgrounds", "round_select_bg")
		if bgId then
			local bgImage = Instance.new("ImageLabel")
			bgImage.Name = "TableBackground"
			bgImage.Size = UDim2.new(1, 0, 1, 0)
			bgImage.BackgroundTransparency = 1
			bgImage.BorderSizePixel = 0
			bgImage.Image = bgId
			bgImage.ScaleType = Enum.ScaleType.Crop
			bgImage.ZIndex = 6
			bgImage.Parent = roundSelectFrame
			roundCorner(bgImage, 16)
			local vignette = Instance.new("UIGradient")
			vignette.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 60, 60)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(215, 215, 215)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(215, 215, 215)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 60, 60)),
			})
			vignette.Parent = bgImage
			-- Fall back to the flat panel colour if the asset fails to load.
			task.spawn(function()
				local ok = pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ bgImage }, function(_, status)
						if status == Enum.AssetFetchStatus.Failure then
							bgImage.Visible = false
						end
					end)
				end)
				if not ok then
					bgImage.Visible = false
				end
			end)
		end
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -360, 0, 44)
	titleLabel.Position = UDim2.new(0, 180, 0, 14)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 34
	titleLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	titleLabel.Text = "This Night"
	titleLabel.ZIndex = 7
	titleLabel.Parent = roundSelectFrame

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.new(1, -360, 0, 26)
	subtitleLabel.Position = UDim2.new(0, 180, 0, 58)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextSize = 18
	subtitleLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	subtitleLabel.Text = "Play the round you're on, or skip it for a Tag instead."
	subtitleLabel.ZIndex = 7
	subtitleLabel.Parent = roundSelectFrame

	-- Slim Tips chip, top right (the sidebar's Tips box is hidden while this screen is up).
	local tipsChip = Instance.new("TextLabel")
	tipsChip.Name = "TipsChip"
	tipsChip.AnchorPoint = Vector2.new(1, 0)
	tipsChip.Size = UDim2.new(0, 150, 0, 34)
	tipsChip.Position = UDim2.new(1, -20, 0, 18)
	tipsChip.BackgroundColor3 = Color3.fromRGB(26, 17, 10)
	tipsChip.BackgroundTransparency = 0.2
	tipsChip.BorderSizePixel = 0
	tipsChip.Font = Enum.Font.GothamBold
	tipsChip.TextSize = 17
	tipsChip.TextColor3 = Color3.fromRGB(235, 200, 120)
	tipsChip.Text = "Tips: 0"
	tipsChip.ZIndex = 7
	tipsChip.Parent = roundSelectFrame
	roundCorner(tipsChip, 8)

	-- panelRow: vertically centered so fixed-height cards don't cling to the top.
	local panelRow = Instance.new("Frame")
	panelRow.Size = UDim2.new(1, -40, 1, -120) -- 104 header + 16 bottom margin
	panelRow.Position = UDim2.new(0, 20, 0, 104)
	panelRow.BackgroundTransparency = 1
	panelRow.ZIndex = 7
	panelRow.Parent = roundSelectFrame

	local panelRowLayout = Instance.new("UIListLayout")
	panelRowLayout.FillDirection = Enum.FillDirection.Horizontal
	panelRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	panelRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelRowLayout.Padding = UDim.new(0, 24)
	panelRowLayout.Parent = panelRow

	-- BUGFIX (independent review): a rapid double-click on Skip -- or a
	-- laggy client clicking again out of impatience -- used to be able to
	-- fire SkipRoundRemote twice before the first skip's state push came
	-- back. The server has no reason to reject the second fire (it's a
	-- perfectly valid skip of whatever round you're now on), so this could
	-- silently blow through 2+ rounds in one interaction. render() only
	-- ever calls rebuildRoundSelect off an ACTUAL server state push (see
	-- init.client.lua's StateUpdatedRemote handler), so "lock on click,
	-- unlock at the top of the next rebuild" is a correct, simple debounce
	-- -- by the time a new state arrives, the previous action has
	-- definitely either gone through or been rejected.
	local actionPending = false

	-- Three cards built once, refreshed by rebuildRoundSelect.
	-- Each card is a fixed 220x560px panel with:
	--   top 280px  = scene image (boss portrait for round 3, room art for 1-2)
	--   below that = room name, boss/tag info, target plaque, action buttons
	-- Cards do not stretch to fill the screen height.
	local CARD_W = 340 -- about 0.55 of the 620 card height; the three equal cards use the free width
	local roundPanels = {}
	local cardScales = {}
	-- Hover life and idle motion (cosmetic only), see RoundSelectFX.lua.
	local fx = require(script.Parent.RoundSelectFX).new({
		roundSelectFrame = roundSelectFrame,
		playClickSfx = playClickSfx,
		roundCorner = roundCorner,
		isActionPending = function() return actionPending end,
	})
	local NO_BUTTON_DROP = 96 -- Select (44) + gap (6) + Skip (40) + margins, see the button positions below
	for round = 1, ROUNDS_PER_NIGHT do
		local cfg = ROOM_CONFIGS[round]
		local isBossPanel = (round == ROUNDS_PER_NIGHT)
		local accent = cfg.accent

		local panel = Instance.new("Frame")
		panel.Name = "RoundPanel" .. round
		panel.Size = UDim2.new(0, CARD_W, 0, 620)
		panel.LayoutOrder = round
		local cardScale = Instance.new("UIScale")
		cardScale.Name = "FitScale"
		cardScale.Parent = panel
		table.insert(cardScales, cardScale)
		panel.BackgroundColor3 = Color3.fromRGB(55, 42, 30)
		panel.ZIndex = 7
		panel.Parent = panelRow

		polishPanel(panel, 14)
		-- Full-bleed scene art: no flat card fill underneath it.
		panel.BackgroundTransparency = 1

		-- Override the UIStroke polishPanel added: use the room's accent color.
		-- Boss panel gets a thicker stroke and a slow pulsing glow (2.5s cycle).
		local panelStroke = panel:FindFirstChildOfClass("UIStroke")
		if panelStroke then
			panelStroke.Color = accent
			panelStroke.Thickness = isBossPanel and 4 or 3
			panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			-- The Boss card's pulsing glow is driven by RoundSelectFX (paused while hidden).
		end

		-- Cleared rounds: gold tint over the art and a gold check medal (shown by rebuildRoundSelect).
		local goldTint = Instance.new("Frame")
		goldTint.Name = "ClearedTint"
		goldTint.Size = UDim2.fromScale(1, 1)
		goldTint.BackgroundColor3 = Color3.fromRGB(230, 184, 70)
		goldTint.BackgroundTransparency = 0.78
		goldTint.BorderSizePixel = 0
		goldTint.Active = false
		goldTint.Visible = false
		goldTint.ZIndex = 10
		goldTint.Parent = panel
		Instance.new("UICorner", goldTint).CornerRadius = UDim.new(0, 14)
		local medal = Instance.new("TextLabel")
		medal.Name = "ClearedMedal"
		medal.Size = UDim2.new(0, 40, 0, 40)
		medal.Position = UDim2.new(1, -50, 0, 10)
		medal.BackgroundColor3 = Color3.fromRGB(230, 184, 70)
		medal.Text = "✓"
		medal.Font = Enum.Font.GothamBold
		medal.TextSize = 24
		medal.TextColor3 = Color3.fromRGB(70, 44, 10)
		medal.Visible = false
		medal.ZIndex = 13
		medal.Parent = panel
		Instance.new("UICorner", medal).CornerRadius = UDim.new(1, 0)
		local medalStroke = Instance.new("UIStroke")
		medalStroke.Color = Color3.fromRGB(255, 240, 180)
		medalStroke.Thickness = 2
		medalStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		medalStroke.Parent = medal

		-- Scene image: top 280px, full card width, rounded corners.
		-- For the boss panel this is the boss portrait (set by setBossArt);
		-- for the other two panels it shows the room's scene art.
		local sceneImage = Instance.new("ImageLabel")
		sceneImage.Name = "SceneImage"
		sceneImage.Size = UDim2.new(1, 0, 1, 0)
		sceneImage.Position = UDim2.new(0, 0, 0, 0)
		sceneImage.BackgroundColor3 = Color3.fromRGB(28, 20, 14)
		sceneImage.BackgroundTransparency = 0
		sceneImage.BorderSizePixel = 0
		sceneImage.Image = ""
		sceneImage.ScaleType = Enum.ScaleType.Crop
		sceneImage.ZIndex = 8
		sceneImage.ClipsDescendants = true
		sceneImage.Parent = panel
		if not isBossPanel then
			local roomArtId = RoomArt[cfg.roomId]
			if type(roomArtId) == "string" and roomArtId ~= "" and roomArtId ~= "rbxassetid://0" then
				sceneImage.Image = roomArtId
			end
		end
		roundCorner(sceneImage, 14)

		-- Scrim over the bottom 45% of the card: clear at the top, nearly opaque
		-- at the bottom, so the art fades into the text area. Stepped strips
		-- (Frame transparency only, no UIGradient.Transparency). Never dimmed.
		local scrim = Instance.new("Frame")
		scrim.Name = "Scrim"
		scrim.AnchorPoint = Vector2.new(0, 1)
		scrim.Position = UDim2.new(0, 0, 1, 0)
		scrim.Size = UDim2.new(1, 0, 0.45, 0)
		scrim.BackgroundTransparency = 1
		scrim.BorderSizePixel = 0
		scrim.ClipsDescendants = true
		scrim.ZIndex = 9
		scrim.Parent = panel
		roundCorner(scrim, 14)
		local SCRIM_STEPS = 14
		for i = 1, SCRIM_STEPS do
			local strip = Instance.new("Frame")
			strip.Name = "Strip" .. i
			strip.Size = UDim2.new(1, 0, 1 / SCRIM_STEPS, 1)
			strip.Position = UDim2.new(0, 0, (i - 1) / SCRIM_STEPS, 0)
			strip.BackgroundColor3 = Color3.new(0, 0, 0)
			strip.BackgroundTransparency = 1 - 0.92 * (i / SCRIM_STEPS) ^ 0.8
			strip.BorderSizePixel = 0
			strip.ZIndex = 9
			strip.Parent = scrim
		end

		-- Status chip overlaid on the top-left of the scene image.
		-- Shows "You are here" (green) for the current round,
		-- "Lock Up next" (gray) for future rounds, "Cleared" with a check for completed rounds.
		-- Parented to sceneImage so it's clipped to the image area.
		local statusChip = Instance.new("TextLabel")
		statusChip.Name = "StatusChip"
		statusChip.Size = UDim2.new(0, 130, 0, 22)
		statusChip.Position = UDim2.new(0, 8, 0, 8)
		statusChip.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
		statusChip.BackgroundTransparency = 0
		statusChip.Font = Enum.Font.GothamBold
		statusChip.TextSize = 14
		statusChip.TextColor3 = Color3.fromRGB(200, 200, 215)
		statusChip.Text = ""
		statusChip.ZIndex = 12
		statusChip.Visible = false
		statusChip.Parent = sceneImage
		roundCorner(statusChip, 6)

		-- Text over a painted portrait always sits on a solid dark parchment plate (4.5:1 or better), never bare on the art.
		local function plateOn(lbl)
			lbl.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
			lbl.BackgroundTransparency = 0.06
			lbl.BorderSizePixel = 0
			lbl.TextStrokeTransparency = 1
			roundCorner(lbl, 8)
			local edge = Instance.new("UIStroke")
			edge.Color = Color3.fromRGB(150, 118, 66)
			edge.Thickness = 1.5
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Name = "PlateEdge"
			edge.Parent = lbl
		end
		-- Room name: larger accent-colored header just below the scene image.
		local roomLabel = Instance.new("TextLabel")
		roomLabel.Name = "RoomLabel"
		roomLabel.Size = UDim2.new(1, -16, 0, 28)
		roomLabel.AnchorPoint = Vector2.new(0, 1)
		roomLabel.Position = UDim2.new(0, 8, 1, isBossPanel and -232 or -180)
		roomLabel.BackgroundTransparency = 1
		roomLabel.Font = Enum.Font.GothamBold
		roomLabel.TextSize = 17
		roomLabel.TextColor3 = Color3.fromRGB(250, 235, 200)
		roomLabel.TextXAlignment = Enum.TextXAlignment.Center
		roomLabel.Text = cfg.roomName
		roomLabel.ZIndex = 11
		roomLabel.TextStrokeTransparency = 0.3
		roomLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		roomLabel.Parent = panel
		plateOn(roomLabel)

		-- Boss name: large gold text, boss panel only (y=324).
		local bossNameLabel = Instance.new("TextLabel")
		bossNameLabel.Name = "BossNameLabel"
		bossNameLabel.Size = UDim2.new(1, -16, 0, 26)
		bossNameLabel.AnchorPoint = Vector2.new(0, 1)
		bossNameLabel.Position = UDim2.new(0, 8, 1, -204)
		bossNameLabel.BackgroundTransparency = 1
		bossNameLabel.Font = Enum.Font.GothamBold
		bossNameLabel.TextSize = 18
		bossNameLabel.TextColor3 = Color3.fromRGB(250, 235, 200)
		bossNameLabel.TextXAlignment = Enum.TextXAlignment.Center
		bossNameLabel.Text = ""
		bossNameLabel.ZIndex = 11
		bossNameLabel.Visible = isBossPanel
		bossNameLabel.TextStrokeTransparency = 0.3
		bossNameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		bossNameLabel.Parent = panel
		plateOn(bossNameLabel)

		-- Boss rule text: readable 16px, up to 2 lines, boss panel only (y=358).
		local bossLabel = Instance.new("TextLabel")
		bossLabel.Name = "BossLabel"
		bossLabel.Size = UDim2.new(1, -20, 0, 0) -- height follows the text (AutomaticSize) plus 12 px padding
		bossLabel.AutomaticSize = Enum.AutomaticSize.Y
		do
			local pad = Instance.new("UIPadding")
			pad.PaddingTop = UDim.new(0, 6)
			pad.PaddingBottom = UDim.new(0, 6)
			pad.PaddingLeft = UDim.new(0, 8)
			pad.PaddingRight = UDim.new(0, 8)
			pad.Parent = bossLabel
		end
		bossLabel.AnchorPoint = Vector2.new(0, 1)
		bossLabel.Position = UDim2.new(0, 10, 1, -150)
		bossLabel.BackgroundTransparency = 1
		bossLabel.Font = Enum.Font.Gotham
		bossLabel.TextSize = 16
		bossLabel.TextColor3 = Color3.fromRGB(230, 180, 170)
		bossLabel.TextWrapped = true
		bossLabel.TextXAlignment = Enum.TextXAlignment.Center
		bossLabel.TextYAlignment = Enum.TextYAlignment.Top
		bossLabel.Text = ""
		bossLabel.ZIndex = 11
		bossLabel.Visible = isBossPanel
		bossLabel.TextStrokeTransparency = 0.35
		bossLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		bossLabel.Parent = panel
		plateOn(bossLabel)

		-- Tag chip: non-boss panels only (y=324), shown for the current round.
		local tagLabel = Instance.new("TextLabel")
		tagLabel.Name = "TagLabel"
		tagLabel.Size = UDim2.new(1, -20, 0, 28)
		tagLabel.AnchorPoint = Vector2.new(0, 1)
		tagLabel.Position = UDim2.new(0, 10, 1, -150)
		tagLabel.BackgroundColor3 = Color3.fromRGB(48, 52, 32)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = Enum.Font.Gotham
		tagLabel.TextSize = 16
		tagLabel.TextColor3 = Color3.fromRGB(200, 220, 170)
		tagLabel.TextXAlignment = Enum.TextXAlignment.Center
		tagLabel.Text = ""
		tagLabel.ZIndex = 11
		tagLabel.Visible = not isBossPanel
		tagLabel.TextStrokeTransparency = 0.35
		tagLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		tagLabel.Parent = panel
		plateOn(tagLabel)
		tagLabel.BackgroundColor3 = Color3.fromRGB(38, 44, 26)
		tagLabel.BackgroundTransparency = 1

		-- Target plaque: y=418 for boss (after rule text), y=356 for non-boss (after tag).
		local targetLabel = Instance.new("TextLabel")
		targetLabel.Name = "TargetLabel"
		targetLabel.Size = UDim2.new(1, -20, 0, 36)
		targetLabel.AnchorPoint = Vector2.new(0, 1)
		targetLabel.Position = UDim2.new(0, 10, 1, -(10 + 40 + 6 + 44 + 8))
		targetLabel.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
		targetLabel.Font = Enum.Font.GothamBold
		targetLabel.TextSize = 18
		targetLabel.TextColor3 = Color3.fromRGB(120, 170, 255)
		targetLabel.TextXAlignment = Enum.TextXAlignment.Center
		targetLabel.Text = ""
		targetLabel.ZIndex = 11
		targetLabel.Parent = panel
		polishPanel(targetLabel, 8)
		do
			local ts = targetLabel:FindFirstChildOfClass("UIStroke")
			if ts then ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
		end

		-- Select / Skip buttons sit directly under the content area.
		-- y=462/512 for boss panel; y=400/450 for non-boss.
		local selectButton = Instance.new("TextButton")
		selectButton.Name = "SelectButton"
		selectButton.Size = UDim2.new(1, -20, 0, 44)
		selectButton.AnchorPoint = Vector2.new(0, 1)
		selectButton.Position = UDim2.new(0, 10, 1, -(10 + 40 + 6))
		selectButton.Font = Enum.Font.GothamBold
		selectButton.TextSize = 16
		selectButton.Text = "Select"
		selectButton.BackgroundColor3 = Color3.fromRGB(70, 130, 70)
		selectButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		selectButton.ZIndex = 11
		selectButton.Visible = false
		selectButton.Parent = panel
		polishButton(selectButton, 10)

		local skipButton = Instance.new("TextButton")
		skipButton.Name = "SkipButton"
		skipButton.Size = UDim2.new(1, -20, 0, 40)
		skipButton.AnchorPoint = Vector2.new(0, 1)
		skipButton.Position = UDim2.new(0, 10, 1, -10)
		skipButton.Font = Enum.Font.GothamBold
		skipButton.TextSize = 16
		skipButton.Text = "Skip"
		skipButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		skipButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		skipButton.ZIndex = 11
		skipButton.Visible = false
		skipButton.Parent = panel
		polishButton(skipButton, 10)
		-- Clean button faces: the deferred inner rim read as a dark arc under the label, and any stray thin bar
		-- (a bracket, rim or leftover strip) is removed so only the label, stroke and gradient remain.
		for _, b in ipairs({ selectButton, skipButton }) do
			task.defer(function()
				task.defer(function()
					local rim = b:FindFirstChild("InnerRim")
					if rim then rim:Destroy() end
					for _, child in ipairs(b:GetChildren()) do
						if child:IsA("Frame") and child.Name ~= "ShineClip" and child.Name ~= "HoverScale" then
							child:Destroy()
						end
					end
				end)
			end)
		end

		selectButton.MouseButton1Click:Connect(function()
			if actionPending then
				return
			end
			actionPending = true
			playClickSfx()
			require(script.Parent.Cue).play("shuffle")
			require(script.Parent.TutorialBus).fire("select_round")
			SelectRoundRemote:FireServer() -- sent right away; the travel cover below only delays the reveal
			pcall(function()
				local st = getLatestState()
				local expectBoss = st and st.bossModifier ~= nil and (st.round or 1) >= ROUNDS_PER_NIGHT
				require(script.Parent.TravelTransition).show({
					state = st,
					readyFn = function()
						local s = getLatestState()
						if not (s and s.phase == "playing") then
							return false
						end
						-- the avatar thumbnail (CharacterStage) and, for a boss round, the boss portrait (BossFight)
						local stage = require(script.Parent.CharacterStage).get()
						if stage ~= nil and not stage.isReady(expectBoss) then
							return false
						end
						if expectBoss then
							local fight = require(script.Parent.BossFight).get()
							if fight ~= nil and not fight.portraitReady() then
								return false
							end
						end
						return true
					end,
				})
			end)
		end)

		-- Read skip-tag reward text fresh at click time (see old BUGFIX comment).
		skipButton.MouseButton1Click:Connect(function()
			if actionPending then
				return
			end
			local latestState = getLatestState()
			if not (latestState and latestState.canSkipRound) then
				return
			end
			actionPending = true
			playClickSfx()
			SkipRoundRemote:FireServer()
		end)

		local entryRef = {
			round = round,
			accent = accent,
			goldTint = goldTint,
			medal = medal,
			isBossRound = isBossPanel,
			cardScale = cardScale,
			panel = panel,
			sceneImage = sceneImage,
			statusChip = statusChip,
			targetLabel = targetLabel,
			bossNameLabel = bossNameLabel,
			bossLabel = bossLabel,
			tagLabel = tagLabel,
			selectButton = selectButton,
			skipButton = skipButton,
			-- Bottom-anchored text that moves down (with a shorter card) on cards that have no buttons.
			shiftables = { roomLabel, bossNameLabel, bossLabel, tagLabel, targetLabel },
			shiftBase = {
				roomLabel.Position.Y.Offset, bossNameLabel.Position.Y.Offset, bossLabel.Position.Y.Offset,
				tagLabel.Position.Y.Offset, targetLabel.Position.Y.Offset,
			},
		}
		table.insert(roundPanels, entryRef)
		fx.addCard(entryRef)
	end

	-- JOURNEY FEATURE / ROUND SELECT FEATURE: describes a Tag's effect the
	-- SAME way for both the panel's own tagLabel text and its tooltip, so
	-- the two can never say different things.
	-- Fit the 620px cards to the viewport: height = min(620, 80% of the
	-- viewport, row height). Scale is clamped 0.6..1 (1280x720 -> ~0.93).
	-- The bottom-anchored content scales with the card, so nothing is cut off.
	local CARD_H = 620
	local MAX_FIT = 1.25 -- the full-width screen lets the cards grow on big viewports
	local function fitCards()
		local cam = workspace.CurrentCamera
		local vpY = cam and cam.ViewportSize.Y or 720
		local rowH = panelRow.AbsoluteSize.Y
		local rowW = panelRow.AbsoluteSize.X
		local scale = CardFit.scale(vpY, rowW, rowH, CARD_H, CARD_W, MAX_FIT)
		fx.setFit(scale)
		-- The layout spaces by the scaled card size, so Padding is the on-screen gap (never below 28px).
		panelRowLayout.Padding = UDim.new(0, CardFit.padding(scale, CARD_W))
		-- Measure after layout; if the real gap is still short, add the shortfall.
		task.defer(function()
			local a, b = panelRow:FindFirstChild("RoundPanel1"), panelRow:FindFirstChild("RoundPanel2")
			if a and b and a.AbsoluteSize.X > 0 then
				local gap = b.AbsolutePosition.X - (a.AbsolutePosition.X + a.AbsoluteSize.X)
				local short = CardFit.shortfall(gap)
				if short > 0 then panelRowLayout.Padding = UDim.new(0, panelRowLayout.Padding.Offset + short) end
			end
		end)
	end
	fitCards()
	panelRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCards)
	local fitCam = workspace.CurrentCamera
	if fitCam then fitCam:GetPropertyChangedSignal("ViewportSize"):Connect(fitCards) end

	local function describeTag(tag)
		return string.format("%s\n%s", tag.name, tag.description)
	end

	-- lastStageKeyForConfirm/lastTagForConfirm/lastTipsForConfirm: same "only
	-- trust a CONFIRMED state change, never the click itself" pattern
	-- Journey.lua's old Skip button used -- a skip fired from here can
	-- equally be rejected server-side (stale canSkipRound between click and
	-- processing), so the confirmation popup only fires once the round has
	-- actually, provably advanced while this screen stayed up the whole
	-- time (see rebuildRoundSelect's `previousPhase` param above for how
	-- "stayed up the whole time" is actually verified).
	--
	-- lastTipsForConfirm exists so the Tip Jar Tag (and On the House's Tips
	-- fallback) can show the RIGHT amount without RoundSelect needing the
	-- server to separately ship its skip result: between two consecutive
	-- roundSelect-phase renders, the ONLY thing that can change state.tips
	-- is the Tag we just applied (no shop, no round win -- both require
	-- leaving this screen first), so the diff IS the amount.
	local lastStageKeyForConfirm = nil
	local lastTagForConfirm = nil
	local lastTipsForConfirm = nil

	local function confirmTagResult(tag, amount)
		if not tag then
			return
		end
		if tag.id == "tip_jar" then
			if showRoundReward and amount and amount > 0 then
				showRoundReward(amount)
			end
		elseif tag.id == "on_the_house" then
			-- On the House normally grants a Patron -- that's already
			-- covered by init.client.lua's own "Unlocked!" popup (FEATURE
			-- 12, the ownedPatrons diff), which fires off the SAME render()
			-- pass this confirmation does, so showing another popup here
			-- would double up. Only the Tips FALLBACK (table full / every
			-- Patron already owned) needs its own popup here -- and that's
			-- exactly the case where `amount` is nonzero, since a Patron
			-- grant never touches state.tips.
			if showRoundReward and amount and amount > 0 then
				showRoundReward(amount)
			end
		elseif tag.id == "sale_day" and showWarning then
			showWarning("Sale Day Tag: your next shop visit is discounted!")
		end
	end

	-- WORLD MAP: the fork screen. Parented to roundSelectFrame so it shows and hides with this screen.
	local roadChoice = require(script.Parent.RoadChoice)({
		root = roundSelectFrame, polishPanel = polishPanel, roundCorner = roundCorner, playClickSfx = playClickSfx,
	})

	-- WORLD MAP side stops (shop, shrine, rest), chips at the top left of this screen.
	local sideStops = require(script.Parent.SideStopPanel)({
		root = roundSelectFrame, roundCorner = roundCorner, playClickSfx = playClickSfx,
	})
	-- Map minigames (dice, card flip, lockpick, trivia); scored on the server.
	local minigamePanel = require(script.Parent.MinigamePanel)({
		root = roundSelectFrame, roundCorner = roundCorner, playClickSfx = playClickSfx,
	})

	local function rebuildRoundSelect(state, previousPhase)
		-- See actionPending's BUGFIX comment above: any fresh state push
		-- means whatever click caused it has definitely been resolved
		-- (accepted or rejected) by now, so clicking is safe again.
		actionPending = false
		pcall(roadChoice.update, state)
		pcall(sideStops.update, state)
		pcall(minigamePanel.update, state)

		-- BUGFIX (Ahmed: "when you complete a night, it should tell you
		-- that you're at Night 2 or Night 3 etc"): this screen is the one
		-- place a player can't avoid seeing right after clearing a Night
		-- (it's a full-screen opaque cover, shown right after the shop that
		-- follows a Boss round win) -- so making its own title say WHICH
		-- Night, live off `state.night`, is a more reliable "tell you"
		-- than a transient toast would be (a toast here would render
		-- invisible anyway -- this frame's ZIndex sits above the toast
		-- banner's). round == 1 means this is the very first time you're
		-- seeing this particular Night, so that's the one moment worth a
		-- slightly more celebratory subtitle.
		-- GENRE PARITY: an "Ante counter" (1/8, then Endless Mode) --
		-- shows "/nightCap" while under it, "(Endless)" once past for good
		-- (state.night only ever increases, so once you're past nightCap
		-- you never see the "/8" form again this run).
		local nightCap = state.nightCap or 8
		local inEndless = state.night > nightCap
		if inEndless then
			titleLabel.Text = string.format("♾ Endless Night %d ♾", state.night)
		else
			titleLabel.Text = string.format("Night %d/%d", state.night, nightCap)
		end
		tipsChip.Text = string.format("Tips: %d", math.floor(tonumber(state.tips) or 0))
		subtitleLabel.Text = state.round == 1
			and "A new Night begins! Play the round you're on, or skip it for a Tag instead."
			or "Play the round you're on, or skip it for a Tag instead."
		-- Endless Mode has its own header style (shared with the Journey map).
		titleLabel.TextColor3 = inEndless and ENDLESS_ACCENT or Color3.fromRGB(250, 240, 220)
		subtitleLabel.TextColor3 = inEndless and ENDLESS_SUB or Color3.fromRGB(220, 205, 185)
		roundSelectFrame.BackgroundColor3 = inEndless and ENDLESS_BG or Color3.fromRGB(40, 30, 22)
		if inEndless then
			for _, milestone in ipairs(JourneyMap.EndlessMilestones) do
				if milestone.night >= state.night then
					subtitleLabel.Text = string.format("Next milestone: Night %d, %s. %s", milestone.night, milestone.name,
						JourneyMap.rewardLabel(milestone.reward))
					break
				end
			end
		end

		local currentRound = state.round

		for _, entry in ipairs(roundPanels) do
			local isBossRound = entry.isBossRound
			local isPast = entry.round < currentRound
			local isCurrent = entry.round == currentRound
			local isFuture = entry.round > currentRound
			-- BUGFIX: pass THIS run's nightCap (server-sent, see
			-- serializeState) through so a Boss Blind preview here always
			-- matches what RunState.startRound will actually compute
			-- server-side, instead of assuming the global default.
			local target = RunStateEngine.targetScoreFor(state.night, entry.round, ROUNDS_PER_NIGHT, state.nightCap)

			entry.targetLabel.Text = string.format("Target: %d", math.floor(target))
			entry.targetLabel.TextTransparency = 0
			entry.targetLabel.TextStrokeTransparency = 1

			-- Dim ONLY the scene image (Cleared / Up next). The scrim and
			-- all text stay fully readable regardless of round state.
			entry.sceneImage.ImageColor3 = (isPast or isFuture) and Color3.fromRGB(160, 160, 160) or Color3.new(1, 1, 1)

			-- Status chip: "You are here" for current, "Up next" for future,
			-- "Cleared" check chip for completed rounds.
			if isCurrent then
				entry.statusChip.Visible = true
				entry.statusChip.Text = "  You are here  "
				entry.statusChip.BackgroundColor3 = Color3.fromRGB(50, 110, 60)
				entry.statusChip.TextColor3 = Color3.fromRGB(200, 255, 210)
			elseif isFuture then
				entry.statusChip.Visible = true
				entry.statusChip.Text = "  Up next  "
				entry.statusChip.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
				entry.statusChip.TextColor3 = Color3.fromRGB(180, 180, 200)
			else
				entry.statusChip.Visible = true
				entry.statusChip.Text = "  Cleared  "
				entry.statusChip.BackgroundColor3 = Color3.fromRGB(45, 120, 70)
				entry.statusChip.TextColor3 = Color3.fromRGB(215, 255, 225)
			end

			local shownBoss = isBossRound and (state.nightBossModifier or state.bossModifier) or nil
			setBossArt(entry, shownBoss and shownBoss.id or nil)

			if isBossRound then
				entry.bossLabel.Visible = true
				entry.tagLabel.Visible = false
				if state.nightBossModifier then
					entry.bossNameLabel.Visible = true
					entry.bossNameLabel.Text = state.nightBossModifier.name
					entry.bossLabel.Text = state.nightBossModifier.description
				elseif state.bossModifier then
					-- Defensive fallback: we're somehow already ON the Boss
					-- round (bossModifier set) but nightBossModifier wasn't
					-- sent -- use the one we definitely have.
					entry.bossNameLabel.Visible = true
					entry.bossNameLabel.Text = state.bossModifier.name
					entry.bossLabel.Text = state.bossModifier.description
				else
					entry.bossNameLabel.Visible = false
					entry.bossLabel.Text = "Boss Rounds are off this run."
				end
				entry.bossNameLabel.TextTransparency = 0
				entry.bossNameLabel.TextStrokeTransparency = 1
				entry.bossLabel.TextTransparency = 0
				entry.bossLabel.TextStrokeTransparency = 1
			else
				entry.bossLabel.Visible = false
				entry.bossNameLabel.Visible = false
				entry.tagLabel.Visible = true
				if isCurrent and state.currentRoundSkipTag then
					local tag = state.currentRoundSkipTag
					entry.tagLabel.Text = tag.name
					entry.tagLabel.BackgroundTransparency = 0.06
				elseif isPast then
					entry.tagLabel.Text = ""
					entry.tagLabel.BackgroundTransparency = 1
				else
					entry.tagLabel.Text = "Tag on arrival"
					entry.tagLabel.BackgroundTransparency = 0.12
				end
				entry.tagLabel.TextTransparency = 0
				entry.tagLabel.TextStrokeTransparency = 1
				entry.tagLabel.PlateEdge.Enabled = entry.tagLabel.Text ~= ""
			end

			fx.setKind(entry, isCurrent and "current" or (isPast and "past" or "future"))

			-- Only the round you're actually on gets buttons.
			entry.selectButton.Visible = isCurrent
			entry.skipButton.Visible = isCurrent and state.canSkipRound == true

			-- Cleared / Up next cards have no buttons: drop the text block by NO_BUTTON_DROP
			-- and make the card that much shorter so it ends just under the Target plaque
			-- (the active card keeps the full 620px for Select and Skip).
			-- All three cards share ONE size (user feedback); state shows through stroke, tint and medal.
			local drop = isCurrent and 0 or NO_BUTTON_DROP -- no buttons: text block settles to the bottom, no dead black space
			local stroke = entry.panel:FindFirstChildOfClass("UIStroke")
			if stroke then
				if isCurrent then
					stroke.Color = Color3.fromRGB(255, 244, 200)
					stroke.Thickness = 6
				elseif isPast then
					stroke.Color = Color3.fromRGB(230, 184, 70)
					stroke.Thickness = 4
				else
					stroke.Color = entry.accent
					stroke.Thickness = entry.isBossRound and 4 or 3
				end
			end
			entry.goldTint.Visible = isPast
			entry.medal.Visible = isPast
			entry.panel.Size = UDim2.new(0, CARD_W, 0, 620 - drop)
			for i, obj in ipairs(entry.shiftables) do
				local p = obj.Position
				obj.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, entry.shiftBase[i] + drop)
			end
		end

		-- Confirmed-skip detection (see lastStageKeyForConfirm's comment
		-- above): the round/night key changed AND the screen you were on
		-- immediately before this render was already "roundSelect" -- the
		-- only way that happens through the shipped UI is a successful
		-- RunState.skipRound (a Select click moves phase to "playing" first,
		-- then "shop", so previousPhase would be "shop" by the time this
		-- screen re-shows after a normal play-through, not "roundSelect").
		--
		-- BUGFIX (independent review): the server doesn't phase-gate
		-- RestartRun/StartRun, so a client firing one of those directly
		-- while sitting on THIS screen could land back on a fresh run's
		-- round 1 with previousPhase still "roundSelect" and a stale
		-- lastTagForConfirm from the old run -- which would otherwise read
		-- as a "confirmed skip" and pop a nonsense reward. Round/night only
		-- ever move FORWARD during normal play/skip, so landing back on
		-- "1-1" from anywhere else can only mean a restart -- never treat
		-- that as a confirmed skip.
		local stageKey = state.night .. "-" .. state.round
		local looksLikeARestart = (stageKey == "1-1" and lastStageKeyForConfirm ~= "1-1")
		if not looksLikeARestart and lastStageKeyForConfirm and stageKey ~= lastStageKeyForConfirm
			and previousPhase == "roundSelect"
			and lastTagForConfirm then
			confirmTagResult(lastTagForConfirm, state.tips - (lastTipsForConfirm or state.tips))
		end
		lastStageKeyForConfirm = stageKey
		lastTagForConfirm = state.currentRoundSkipTag
		lastTipsForConfirm = state.tips
	end

	if addTooltip then
		for _, entry in ipairs(roundPanels) do
			addTooltip(entry.skipButton, function()
				local latestState = getLatestState()
				if latestState and latestState.currentRoundSkipTag then
					return describeTag(latestState.currentRoundSkipTag)
				end
				return "Skip this round for a Tag instead of playing it."
			end)
		end
	end

	return {
		roundSelectFrame = roundSelectFrame,
		rebuildRoundSelect = rebuildRoundSelect,
	}
end
