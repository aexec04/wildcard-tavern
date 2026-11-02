--[[
	Client/Sidebar.lua
	LAYOUT FEATURE 1: the always-visible left-side column showing round/blind
	info, tips, hands/discards remaining, the Patron-slot row, and the live
	score preview. Replaces the old full-width top status bar, which had
	started colliding with the top-right corner icon buttons as more got
	added (a real bug -- the "Hands" label was getting cut off). Balatro
	keeps this info in a dedicated left-side column instead of a top bar, so
	this moves the same data there and leaves the whole top edge free for
	the corner icon buttons with no shared space to collide over.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. SIDEBAR_WIDTH is consumed as a dep by
	Client/MessageBanner.lua and Client/Shop.lua, so this module must be
	required BEFORE either of those. Every label here is live-updated
	elsewhere: nightRoundLabel/blindInfoLabel/scoreLabel/tipsLabel/
	handsDiscardsLabel/patronsCountLabel/the patronSlots array are all set
	inside render() (still inline in init.client.lua), and
	scorePreviewLabel/scorePreviewBox are driven by refreshScorePreview()
	(also still inline). All of those come back out of the require() call
	so the rest of the script can keep updating them.

	deps fields:
		root        -- Frame, the sidebar's parent
		polishPanel  -- function(instance, radius)
		roundCorner  -- function(instance, radius)
		Patrons      -- the Patrons engine module (needs #Patrons.Definitions)

	Returns:
		{
			SIDEBAR_WIDTH = 240,
			sidebar = Frame,
			nightRoundLabel = TextLabel,
			blindInfoLabel = TextLabel,
			scoreLabel = TextLabel,
			tipsLabel = TextLabel,
			tipsBox = Frame,
			handsDiscardsLabel = TextLabel,
			handsDiscardsBox = Frame,
			patronsCountLabel = TextLabel,
			patronSlots = { [i] = { frame = Frame, label = TextLabel } },
			MAX_SIDEBAR_PATRON_SLOTS = 14,
			scorePreviewBox = Frame,
			scorePreviewLabel = TextLabel,
			setRunModeBadge = function(isDaily, dailyDateKey, isWeekly, weeklyDateKey, isSeeded, seedCode),
		}

	PHASE 16: setDailyBadge was renamed to setRunModeBadge and generalized
	to cover all 3 seeded-run modes (Daily/Weekly/Seed Code) sharing the
	one badge box -- only one of the 3 is ever true for a given run, same
	"at most one seedMode" guarantee Server/init.server.lua's
	startNewSession keeps, so one shared box (swapping color/text/icon)
	is simpler than 3 separate boxes that would always show at most one
	visible anyway.

	POLISH PASS: tipsBox/handsDiscardsBox (previously kept private to this
	module) now come back out too -- render() in init.client.lua pulses
	them (VisualHelpers.lua's pulseFrame) whenever Tips/Hands/Discards
	actually change, so gaining or spending something here gets a visible
	flash instead of the number just silently changing.
]]

return function(deps)
	local root = deps.root
	local polishPanel = deps.polishPanel
	local roundCorner = deps.roundCorner
	local Patrons = deps.Patrons

	local SIDEBAR_WIDTH = 240

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0)
	sidebar.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	sidebar.BorderSizePixel = 0
	sidebar.ZIndex = 2
	-- REFERENCE-MATCH PASS, round 2 (Nov 1 2026): the reference's left
	-- column is a near-solid dark-wood strip (the room barely shows
	-- through), with a soft shadowed edge on its right side. Its plaques
	-- are deep brown with a BRONZE outer border, a fine gold inner line,
	-- and gold corner brackets -- not the bright double gold lines and
	-- diamonds of round 1.
	sidebar.BackgroundTransparency = 0.06
	sidebar.Parent = root

	do
		-- Color-only gradient (never Transparency): lighter wood at the
		-- top, darker toward the bottom. Multiplies the theme's panelBg,
		-- so Themes still recolor the column.
		local woodShade = Instance.new("UIGradient")
		woodShade.Rotation = 90
		woodShade.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(205, 195, 185)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 110, 100)),
		})
		woodShade.Parent = sidebar

		-- Right-edge separation: a bronze hairline plus a dark shadow strip
		-- fading out into the room.
		local edgeLine = Instance.new("Frame")
		edgeLine.Name = "EdgeLine"
		edgeLine.AnchorPoint = Vector2.new(1, 0)
		edgeLine.Position = UDim2.fromScale(1, 0)
		edgeLine.Size = UDim2.new(0, 2, 1, 0)
		edgeLine.BackgroundColor3 = Color3.fromRGB(120, 88, 45)
		edgeLine.BorderSizePixel = 0
		edgeLine.ZIndex = 2
		edgeLine.Parent = root
		edgeLine.Position = UDim2.new(0, SIDEBAR_WIDTH, 0, 0)

		local edgeShadow = Instance.new("Frame")
		edgeShadow.Name = "EdgeShadow"
		edgeShadow.Position = UDim2.new(0, SIDEBAR_WIDTH, 0, 0)
		edgeShadow.Size = UDim2.new(0, 18, 1, 0)
		edgeShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		edgeShadow.BorderSizePixel = 0
		edgeShadow.ZIndex = 1
		edgeShadow.Parent = root
		-- Fading a dedicated shadow strip with Transparency is the
		-- intended effect here (unlike the old addGloss bug, this frame
		-- exists only to be a see-through fade).
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new(0.45, 1)
		fade.Parent = edgeShadow
	end

	local GOLD = Color3.fromRGB(222, 182, 104)
	local BRONZE = Color3.fromRGB(128, 92, 46)
	local BOX_COLOR = Color3.fromRGB(26, 17, 10)
	local CREAM = Color3.fromRGB(246, 232, 205)

	local function ornamentBox(box)
		local rim = box:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Color = BRONZE
			rim.Thickness = 3
			rim.Transparency = 0
		end

		-- Subtle top-lit plaque shading (Color only -- only tints the box's
		-- own fill, never its child labels).
		local plaqueShade = Instance.new("UIGradient")
		plaqueShade.Rotation = 90
		plaqueShade.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(165, 160, 155))
		plaqueShade.Parent = box

		local inner = Instance.new("Frame")
		inner.Name = "InnerRim"
		inner.Position = UDim2.fromOffset(4, 4)
		inner.Size = UDim2.new(1, -8, 1, -8)
		inner.BackgroundTransparency = 1
		inner.ZIndex = 2
		inner.Parent = box
		local innerCorner = Instance.new("UICorner")
		innerCorner.CornerRadius = UDim.new(0, 3)
		innerCorner.Parent = inner
		local innerStroke = Instance.new("UIStroke")
		innerStroke.Color = GOLD
		innerStroke.Thickness = 1
		innerStroke.Transparency = 0.35
		innerStroke.Parent = inner

		-- Gold L-shaped corner brackets sitting over the bronze border,
		-- each with a small stud at the tip -- the reference's corner
		-- ornaments.
		local ARM, THICK = 12, 3
		for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
			local ax, ay = c[1], c[2]
			local xOff = ax == 0 and -2 or 2
			local yOff = ay == 0 and -2 or 2

			local horizontal = Instance.new("Frame")
			horizontal.Name = "BracketH"
			horizontal.AnchorPoint = Vector2.new(ax, ay)
			horizontal.Position = UDim2.new(ax, xOff, ay, yOff)
			horizontal.Size = UDim2.fromOffset(ARM, THICK)
			horizontal.BackgroundColor3 = GOLD
			horizontal.BorderSizePixel = 0
			horizontal.ZIndex = 3
			horizontal.Parent = box

			local vertical = Instance.new("Frame")
			vertical.Name = "BracketV"
			vertical.AnchorPoint = Vector2.new(ax, ay)
			vertical.Position = UDim2.new(ax, xOff, ay, yOff)
			vertical.Size = UDim2.fromOffset(THICK, ARM)
			vertical.BackgroundColor3 = GOLD
			vertical.BorderSizePixel = 0
			vertical.ZIndex = 3
			vertical.Parent = box

			local stud = Instance.new("Frame")
			stud.Name = "CornerStud"
			stud.AnchorPoint = Vector2.new(0.5, 0.5)
			stud.Position = UDim2.new(ax, ax == 0 and 5 or -5, ay, ay == 0 and 5 or -5)
			stud.Size = UDim2.fromOffset(4, 4)
			stud.Rotation = 45
			stud.BackgroundColor3 = GOLD
			stud.BorderSizePixel = 0
			stud.ZIndex = 3
			stud.Parent = box
		end
	end

	-- ART ASSET (Oct 25 2026): "Ornate Golden Wood UI Panel", isolated
	-- from Ahmed's original full-UI mockup. Sits BEHIND the sidebar
	-- (ZIndex 1 vs sidebar.ZIndex 2), matching its exact bounds.
	-- Fallback while this is "rbxassetid://0": sidebar's own flat
	-- Color3.fromRGB(40, 30, 22), completely unaffected either way.
	--
	-- BUGFIX (everything in the sidebar vanished after this was first
	-- added): this used to be parented to `sidebar` itself, which also
	-- holds sidebarLayout (a UIListLayout, added right below). A
	-- UIListLayout auto-arranges EVERY GuiObject child of its parent into
	-- a vertical stack, texture included -- and since this is sized to
	-- fill the full sidebar height, it became the layout's first (and
	-- effectively only visible) item, pushing the Round/Tips/Patrons/etc.
	-- boxes stacked after it straight out of the visible area. Parenting
	-- it to `root` instead (same Size/Position as `sidebar`, just a
	-- lower ZIndex so it sits behind it) keeps it out of sidebarLayout's
	-- reach entirely while still looking identical on screen.
	--
	-- REFERENCE-MATCH PASS: turned OFF. This texture never actually
	-- showed -- it sat behind `sidebar`, which was fully opaque -- and
	-- now that the column is see-through, stretching one panel image
	-- over a 240px x full-height strip would distort it. The asset id is
	-- still in ArtAssets.lua; set sidebarColumnTextureEnabled = true there
	-- to bring it back.
	local ArtAssetsModule = require(script.Parent.ArtAssets)
	if ArtAssetsModule.sidebarColumnTextureEnabled == true
		and ArtAssetsModule.sidebarPanelTexture ~= "rbxassetid://0" then
		local sidebarTexture = Instance.new("ImageLabel")
		sidebarTexture.Name = "SidebarBackgroundTexture"
		sidebarTexture.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0)
		sidebarTexture.BackgroundTransparency = 1
		sidebarTexture.Image = ArtAssetsModule.sidebarPanelTexture
		sidebarTexture.ScaleType = Enum.ScaleType.Stretch
		sidebarTexture.ZIndex = 1
		sidebarTexture.Parent = root
	end

	local sidebarPadding = Instance.new("UIPadding")
	-- 76px, not 16 -- Roblox's own top-left system UI (menu/chat/voice icons)
	-- lives in roughly that space and was overlapping the "Round" box's text.
	sidebarPadding.PaddingTop = UDim.new(0, 76)
	sidebarPadding.PaddingLeft = UDim.new(0, 12)
	sidebarPadding.PaddingRight = UDim.new(0, 12)
	sidebarPadding.Parent = sidebar

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.FillDirection = Enum.FillDirection.Vertical
	sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sidebarLayout.Padding = UDim.new(0, 10)
	sidebarLayout.Parent = sidebar

	local SkinArtModule = require(script.Parent.SkinArt)
	local ArtAssetsForSkin = require(script.Parent.ArtAssets)

	-- ART: the wood column image (ArtAssets.sidebarColumnArt). Parented to
	-- root, NOT sidebar -- sidebar holds a UIListLayout that would lay it
	-- out like a box (see the old texture BUGFIX note above). ZIndex 1
	-- puts it under the sidebar (2) and over the room art (0).
	do
		local slice = SkinArtModule.Slices.sidebarColumn
		SkinArtModule.apply(root, ArtAssetsForSkin.sidebarColumnArt, {
			size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
			zIndex = 1,
			sliceCenter = slice.center,
			sliceScale = slice.scale,
			onLoaded = function()
				sidebar.BackgroundTransparency = 1
				local edgeLine = root:FindFirstChild("EdgeLine")
				if edgeLine then
					edgeLine.Visible = false -- the art has its own gold trim
				end
			end,
		})
	end

	local function makeSidebarBox(height)
		local box = Instance.new("Frame")
		box.Size = UDim2.new(1, 0, 0, height or 46)
		box.BackgroundColor3 = BOX_COLOR
		box.BackgroundTransparency = 0
		box.ZIndex = 2
		box.Parent = sidebar
		polishPanel(box, 4)
		ornamentBox(box)
		-- ART: the wood/gold plaque image (ArtAssets.plaqueFrameArt),
		-- created BEFORE the box's labels so it draws under them. Skipped
		-- for very short boxes (the 28px run-mode badge) -- the plaque's
		-- corners need ~44px of height to not overlap.
		if (height or 46) >= 44 then
			local slice = SkinArtModule.Slices.plaque
			SkinArtModule.apply(box, ArtAssetsForSkin.plaqueFrameArt, {
				sliceCenter = slice.center,
				sliceScale = slice.scale,
				onLoaded = function()
					SkinArtModule.hideCodeChrome(box)
				end,
			})
		end
		return box
	end

	local function makeSidebarLabel(parent, textSize, color)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = textSize or 16
		label.TextColor3 = color or CREAM
		label.TextWrapped = true
		label.Text = ""
		label.ZIndex = 2
		label.Parent = parent
		return label
	end

	-- DAILY CHALLENGE (Phase 11) / WEEKLY CHALLENGE + SEED CODES (Phase
	-- 16): a small badge shown only while the current run is one of the
	-- 3 seeded modes, so it's always obvious you're in a seeded/
	-- leaderboard(or shared) run and not a normal one. Hidden by
	-- default; toggled via the `setRunModeBadge` function this module
	-- returns below, called from render() in init.client.lua.
	-- LayoutOrder -1 (every other sidebar box defaults to 0) keeps this
	-- pinned to the very top of the sidebar without having to add an
	-- explicit LayoutOrder to every existing box.
	local runModeBadgeBox = makeSidebarBox(28)
	runModeBadgeBox.LayoutOrder = -1
	runModeBadgeBox.BackgroundColor3 = Color3.fromRGB(80, 55, 110)
	runModeBadgeBox.Visible = false
	local runModeBadgeLabel = makeSidebarLabel(runModeBadgeBox, 13, Color3.fromRGB(230, 210, 255))
	runModeBadgeLabel.Text = "\240\159\147\133 Daily Challenge"

	-- At most one of isDaily/isWeekly/isSeeded is ever true for a given
	-- run (Server/init.server.lua's startNewSession only ever sets one
	-- seedMode per call) -- checked in that order, first match wins,
	-- purely so the fallthrough `else` (a normal run) is unambiguous.
	local function setRunModeBadge(isDaily, dailyDateKey, isWeekly, weeklyDateKey, isSeeded, seedCode)
		if isDaily then
			runModeBadgeBox.Visible = true
			runModeBadgeBox.BackgroundColor3 = Color3.fromRGB(80, 55, 110)
			runModeBadgeLabel.Text = "\240\159\147\133 Daily Challenge" .. (dailyDateKey and (" -- " .. tostring(dailyDateKey)) or "")
		elseif isWeekly then
			runModeBadgeBox.Visible = true
			runModeBadgeBox.BackgroundColor3 = Color3.fromRGB(45, 75, 110)
			runModeBadgeLabel.Text = "🗓 Weekly Challenge" .. (weeklyDateKey and (" -- " .. tostring(weeklyDateKey)) or "")
		elseif isSeeded then
			runModeBadgeBox.Visible = true
			runModeBadgeBox.BackgroundColor3 = Color3.fromRGB(55, 95, 60)
			runModeBadgeLabel.Text = "🎲 Seed Run" .. (seedCode and (" -- " .. tostring(seedCode)) or "")
		else
			runModeBadgeBox.Visible = false
		end
	end

	local nightRoundBox = makeSidebarBox(50)
	local nightRoundLabel = makeSidebarLabel(nightRoundBox, 21)

	-- LAYOUT FEATURE 2: blind/round name + ability (the only always-on
	-- Boss Round readout -- the old top bossBanner that duplicated it was
	-- removed) and the target score + tip reward
	-- for clearing it, computed the same way the server does (see RunState.lua
	-- playHand: tipsPerRoundWin, doubled on a Boss Round) so it never drifts
	-- out of sync with the actual payout.
	local blindInfoBox = makeSidebarBox(84)
	local blindInfoLabel = makeSidebarLabel(blindInfoBox, 14)
	-- Rich text: render() puts the boss/round name on a bigger first
	-- line and the rule text smaller underneath, like the reference.
	blindInfoLabel.RichText = true
	-- Inset so wrapped boss descriptions don't touch the gold frame.
	blindInfoLabel.Position = UDim2.fromOffset(8, 8)
	blindInfoLabel.Size = UDim2.new(1, -16, 1, -14)
	blindInfoLabel.TextWrapped = true
	blindInfoLabel.TextYAlignment = Enum.TextYAlignment.Center

	local scoreBox = makeSidebarBox(70)
	local scoreLabel = makeSidebarLabel(scoreBox, 19)

	-- ART: gold coin icon to the left of the "Reward" line
	-- (ArtAssets.coinIconArt). Only appears once the image has actually
	-- loaded; placeRewardIcon (called from render) keeps it snug against
	-- the start of the line, whatever the number's width.
	local rewardIcon = SkinArtModule.apply(scoreBox, ArtAssetsForSkin.coinIconArt, {
		size = UDim2.fromOffset(20, 20),
		anchor = Vector2.new(1, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		zIndex = 2,
		scaleType = Enum.ScaleType.Fit,
	})
	local lastRewardLine = nil
	local function placeRewardIcon(rewardLine)
		if not rewardIcon or rewardLine == lastRewardLine then
			return
		end
		lastRewardLine = rewardLine
		task.spawn(function()
			local TextService = game:GetService("TextService")
			local params = Instance.new("GetTextBoundsParams")
			params.Text = rewardLine
			params.Font = scoreLabel.FontFace
			params.Size = scoreLabel.TextSize
			params.Width = 1000
			local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
			if ok and rewardLine == lastRewardLine and rewardIcon.Parent then
				local lineHeight = scoreLabel.TextSize * 1.25
				rewardIcon.Position = UDim2.new(0.5, -bounds.X / 2 - 5, 0.5, lineHeight / 2)
			end
		end)
	end

	local tipsBox = makeSidebarBox(50)
	local tipsLabel = makeSidebarLabel(tipsBox, 19)

	local handsDiscardsBox = makeSidebarBox(50)
	local handsDiscardsLabel = makeSidebarLabel(handsDiscardsBox, 18)

	-- LAYOUT FEATURE 5: Patron slot icons, mirroring Balatro's persistent
	-- Joker-slot row -- shows how many Patrons you've picked up this run at a
	-- glance, without opening the Collection Gallery. This game has no hard
	-- cap on Patrons owned (unlike Balatro's Joker slots), so this shows
	-- owned-out-of-total-in-the-game rather than a hard capacity.
	local patronsBox = makeSidebarBox(78)

	local patronsHeader = Instance.new("TextLabel")
	patronsHeader.Size = UDim2.new(0.6, -12, 0, 20)
	patronsHeader.Position = UDim2.new(0, 12, 0, 8)
	patronsHeader.BackgroundTransparency = 1
	patronsHeader.Font = Enum.Font.GothamBold
	patronsHeader.TextSize = 17
	patronsHeader.TextColor3 = CREAM
	patronsHeader.TextXAlignment = Enum.TextXAlignment.Left
	patronsHeader.Text = "Patrons"
	patronsHeader.ZIndex = 2
	patronsHeader.Parent = patronsBox

	local patronsCountLabel = Instance.new("TextLabel")
	patronsCountLabel.Size = UDim2.new(0.4, -12, 0, 20)
	patronsCountLabel.Position = UDim2.new(0.6, 0, 0, 8)
	patronsCountLabel.BackgroundTransparency = 1
	patronsCountLabel.Font = Enum.Font.GothamBold
	patronsCountLabel.TextSize = 17
	patronsCountLabel.TextColor3 = CREAM
	patronsCountLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	patronsCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	patronsCountLabel.Text = ""
	patronsCountLabel.ZIndex = 2
	patronsCountLabel.Parent = patronsBox

	local patronsSlotRow = Instance.new("Frame")
	patronsSlotRow.Size = UDim2.new(1, 0, 0, 34)
	patronsSlotRow.Position = UDim2.new(0, 0, 0, 36)
	patronsSlotRow.BackgroundTransparency = 1
	patronsSlotRow.ZIndex = 2
	patronsSlotRow.Parent = patronsBox

	local patronsSlotLayout = Instance.new("UIListLayout")
	patronsSlotLayout.FillDirection = Enum.FillDirection.Horizontal
	-- Was Left -- with only patronSlotLimit (5 by default) of the 14
	-- possible slots actually Visible at once (see LAYOUT FEATURE 5 in
	-- init.client.lua's render()), Left-aligned left the row looking
	-- lopsided, bunched against the left edge with a big empty gap on the
	-- right. Center keeps it looking balanced no matter how many slots
	-- are actually shown.
	patronsSlotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	patronsSlotLayout.Padding = UDim.new(0, 9)
	patronsSlotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	patronsSlotLayout.Parent = patronsSlotRow

	-- Built once, refreshed in render() below each time state.ownedPatrons
	-- changes. Capped at MAX_SIDEBAR_PATRON_SLOTS regardless of how big the
	-- Patron catalog grows -- this is a quick-glance strip, not the full
	-- browser (that's the Shop's "My Patrons" tab / Collection Gallery), and
	-- a catalog of 50+ would otherwise overflow the sidebar entirely. The
	-- exact "X / Y owned" count (patronsCountLabel above) is always accurate
	-- even when the icon row itself is truncated.
	local MAX_SIDEBAR_PATRON_SLOTS = 14
	local patronSlots = {}
	for i = 1, math.min(MAX_SIDEBAR_PATRON_SLOTS, #Patrons.Definitions) do
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, 32, 0, 32)
		slot.BackgroundColor3 = Color3.fromRGB(45, 40, 38)
		slot.LayoutOrder = i
		slot.ZIndex = 2
		slot.Parent = patronsSlotRow
		-- REFERENCE-MATCH PASS: round gold-ringed seats, not rounded squares.
		roundCorner(slot, 16)
		local seatRing = Instance.new("UIStroke")
		seatRing.Color = GOLD
		seatRing.Thickness = 2
		seatRing.Transparency = 0.15
		seatRing.Parent = slot

		local slotLabel = Instance.new("TextLabel")
		slotLabel.Size = UDim2.fromScale(1, 1)
		slotLabel.BackgroundTransparency = 1
		slotLabel.Font = Enum.Font.GothamBold
		slotLabel.TextSize = 17
		slotLabel.TextColor3 = Color3.fromRGB(140, 135, 130)
		slotLabel.Text = "?"
		slotLabel.ZIndex = 2
		slotLabel.Parent = slot

		patronSlots[i] = { frame = slot, label = slotLabel }
	end

	-- LAYOUT FEATURE 6: live chips x mult preview for the currently-selected
	-- cards, mirroring Balatro's running score readout. Computed with the same
	-- HandEvaluator/Scoring modules the server uses, so the preview can't
	-- drift out of sync with the real payout -- see refreshScorePreview()
	-- back in init.client.lua, which wires this up once
	-- selected/latestState exist.
	local scorePreviewBox = makeSidebarBox(56)
	local scorePreviewLabel = makeSidebarLabel(scorePreviewBox, 18)

	-- ART: painted icons that replace the 💰 / 🃏 / 👑 emojis at the start
	-- of a label's first line. Each icon is a child of its label, sitting
	-- just left of the text. Until the icon has actually loaded, the label
	-- keeps its emoji, so a missing image never leaves a gap.
	--   setIconText(key, plainText, emojiText, measureText, measureSize)
	--     plainText   -- label text WITHOUT the emoji (used once loaded)
	--     emojiText   -- label text WITH the emoji (used until then)
	--     measureText -- the first line's visible text, to find its width
	--     measureSize -- that first line's text size
	local TextService = game:GetService("TextService")
	local lineIcons = {}
	local function addLineIcon(key, label, imageId, iconSize)
		local icon = SkinArtModule.apply(label, imageId, {
			size = UDim2.fromOffset(iconSize, iconSize),
			anchor = Vector2.new(1, 0.5),
			position = UDim2.fromScale(0, 0.5),
			zIndex = label.ZIndex,
			scaleType = Enum.ScaleType.Fit,
		})
		if icon then
			lineIcons[key] = { label = label, icon = icon }
		end
	end
	addLineIcon("tips", tipsLabel, ArtAssetsForSkin.tipsIconArt, 24)
	addLineIcon("hands", handsDiscardsLabel, ArtAssetsForSkin.cardsIconArt, 24)
	addLineIcon("boss", blindInfoLabel, ArtAssetsForSkin.crownIconArt, 20)

	local function setIconText(key, plainText, emojiText, measureText, measureSize)
		local entry = lineIcons[key]
		if not entry then
			-- No icon slot at all: just show the emoji version.
			local label = (key == "tips" and tipsLabel) or (key == "hands" and handsDiscardsLabel) or blindInfoLabel
			label.Text = emojiText
			return
		end
		entry.args = { plainText, emojiText, measureText, measureSize }
		local icon, label = entry.icon, entry.label
		if not (icon.Parent and icon.IsLoaded) then
			label.Text = emojiText
			if not entry.hooked and icon.Parent then
				-- Re-apply the moment the icon finishes loading.
				entry.hooked = true
				icon:GetPropertyChangedSignal("IsLoaded"):Connect(function()
					if icon.IsLoaded and entry.args then
						setIconText(key, table.unpack(entry.args))
					end
				end)
			end
			return
		end
		label.Text = plainText
		icon.Visible = true
		local myArgs = entry.args
		task.spawn(function()
			local params = Instance.new("GetTextBoundsParams")
			params.Text = measureText
			params.Font = label.FontFace
			params.Size = measureSize
			params.Width = 1000
			local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
			task.wait() -- let label.TextBounds catch up with the new text
			if not ok or entry.args ~= myArgs or not icon.Parent then
				return
			end
			local firstLineCenter = -label.TextBounds.Y / 2 + (measureSize * 1.2) / 2
			icon.Position = UDim2.new(0.5, -bounds.X / 2 - 6, 0.5, firstLineCenter)
		end)
	end

	-- For a label that shouldn't show its icon right now (e.g. the round
	-- box on a non-Boss round).
	local function hideLineIcon(key)
		local entry = lineIcons[key]
		if entry then
			entry.args = nil
			entry.icon.Visible = false
		end
	end

	return {
		SIDEBAR_WIDTH = SIDEBAR_WIDTH,
		sidebar = sidebar,
		nightRoundLabel = nightRoundLabel,
		blindInfoLabel = blindInfoLabel,
		scoreLabel = scoreLabel,
		-- TUTORIAL WALKTHROUGH: exposes the BOX (not just the label inside
		-- it), same reasoning as tipsBox/handsDiscardsBox just below --
		-- TutorialWalkthrough.lua spotlights the whole box, which reads
		-- much better than a highlight ring hugging just the text.
		scoreBox = scoreBox,
		tipsLabel = tipsLabel,
		tipsBox = tipsBox,
		handsDiscardsLabel = handsDiscardsLabel,
		handsDiscardsBox = handsDiscardsBox,
		patronsCountLabel = patronsCountLabel,
		patronSlots = patronSlots,
		MAX_SIDEBAR_PATRON_SLOTS = MAX_SIDEBAR_PATRON_SLOTS,
		scorePreviewBox = scorePreviewBox,
		scorePreviewLabel = scorePreviewLabel,
		setRunModeBadge = setRunModeBadge,
		placeRewardIcon = placeRewardIcon,
		setIconText = setIconText,
		hideLineIcon = hideLineIcon,
	}
end
