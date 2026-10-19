--[[
	Client/TutorialWalkthrough.lua
	INTERACTIVE TUTORIAL (replaces Client/Tutorial.lua's old static modal
	for the AUTO-TRIGGERED first-time-player experience only -- that file
	stays exactly as it was and stays wired to Menu.lua's "Tutorial"
	button as a quick-reference recap; see its own header).

	Requested directly by Ahmed: "I want the tutorial to be more
	interactive... they get to follow an actual run and the strategies
	they can take and which cards to play with, and it just highlights
	and focuses the camera while darkening the surrounding so their eyes
	are focused on that specific area on what to click."

	This game's whole "camera" IS a full-screen 2D UI (see PhaseA.lua's
	own header on why -- no 3D camera is ever pointed at gameplay), so
	"focus the camera" means a coach-mark SPOTLIGHT here: 4 dark Frames
	("Active = true", so they also BLOCK clicks to anything dimmed out --
	not just visual, a real focus) surrounding a precise cutout around one
	real, live UI element, plus a pulsing gold UIStroke border around it
	and a caption card near it. No fake/scripted data anywhere -- every
	step spotlights the SAME real hand/buttons/Shop the player is
	actually playing with, during their own actual first run.

	STEP GATING (per Ahmed's own call when asked): the 2 steps that teach
	the CORE loop (select cards, play a hand) require the player to
	actually DO it -- the spotlight simply won't advance until they have.
	The supporting steps (Discard, the sidebar readouts, the Shop) are
	real/live but softly gated -- a "Got it" button, not a forced action --
	since those are genuinely optional on any given round and a hard gate
	there risks stranding a player who, say, can't afford any Patron on
	this particular Shop visit.

	COVERAGE: first Round only, then fades out for good -- selecting/
	playing a hand, Discard, the Hands/Discards/Score sidebar, waiting out
	the Round, and one guided Shop/Patron visit. Everything after the
	first "Next Round" click is unassisted, same as any returning player.

	HOW STEPS ADVANCE: this module owns ZERO game state -- every gate is a
	notify*() call from the exact spot in init.client.lua (or nowhere else)
	that already knows the real thing happened (a card toggled, PlayHand
	fired, Discard fired, the phase pushed to "shop", Next Round clicked).
	Each notify is a safe no-op unless the walkthrough is both active AND
	currently sitting on the one step it matches -- so out-of-order play
	(e.g. discarding before ever playing a hand) can never desync it.

	deps fields:
		root                 -- Frame, the full-screen gameplay root (every
		                        piece here parents to it, same convention
		                        as PhaseA.lua/ScorePopup.lua)
		tweenTo              -- function(instance, props, duration, style?, direction?)
		polishPanel          -- function(instance, radius)
		playClickSfx         -- function(volume?)
		addButtonHoverScale  -- function(button, opts?)
		MarkTutorialSeenRemote -- RemoteEvent, fired () once this finishes/is skipped
		handFrame            -- Frame, the dealt-hand card area
		playButton           -- TextButton, "Play Hand"
		discardButton        -- TextButton, "Discard"
		nextRoundButton      -- TextButton, Shop's "Next Round"
		sidebarScoreBox      -- Frame, Sidebar's Round-target/score box
		sidebarTipsBox       -- Frame, Sidebar's Tips box
		sidebarHandsDiscardsBox -- Frame, Sidebar's Hands/Discards box
		shopBuyListFrame     -- Frame, the Shop's scrolling offer list

	Returns:
		{
			start = function(),                    -- begins at step 1; no-op if already active/done
			onRender = function(state),             -- call every render(); the one step that needs
			                                        -- real server state (waiting for a run to start)
			notifySelectionChanged = function(n),   -- n = how many cards are currently selected
			notifyHandPlayed = function(),          -- call right when PlayHandRemote fires
			notifyDiscardUsed = function(),         -- call right when DiscardRemote fires
			notifyEnteredShop = function(),         -- call once shop is visible+built after a round win
			notifyNextRoundClicked = function(),    -- call from nextRoundButton's own click handler
		}
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MODE_SPOTLIGHT = "spotlight"
local MODE_CENTER = "center"
local MODE_LIGHT = "light"

local STEPS = {
	{
		id = "welcome",
		mode = MODE_CENTER,
		title = "Welcome to Wildcard Tavern!",
		body = "Let's learn by playing your first hand together -- for real, no fake demo. Everything below points at the actual table in front of you.",
		button = "Let's go!",
	},
	-- Covers the real, common case this whole feature's design has to
	-- account for: hasSeenTutorial flips false the moment a brand-new
	-- player connects, which is almost always BEFORE they've clicked
	-- "Start Run" on the menu -- there's no hand dealt yet to spotlight.
	-- Lightest possible touch (no dim, no spotlight -- the menu itself
	-- needs to stay fully usable) while onRender() below waits for
	-- state.phase to actually become "playing".
	{
		id = "waiting_for_run_start",
		mode = MODE_LIGHT,
		body = "Hit Start Run (or Daily/Weekly Challenge) on the menu whenever you're ready -- I'll pick up the moment your hand's dealt.",
	},
	{
		id = "select_cards",
		mode = MODE_SPOTLIGHT,
		target = "hand",
		title = "Pick your cards",
		body = "Click cards here to select up to 5. Look for a poker hand -- even a single Pair scores, and a Flush or Full House scores a lot more.",
	},
	{
		id = "play_hand",
		mode = MODE_SPOTLIGHT,
		target = "play",
		title = "Play your hand",
		body = "Hit Play Hand to score your selected cards. Stronger hands score more Chips and Mult, which multiply together.",
	},
	{
		id = "discard_info",
		mode = MODE_SPOTLIGHT,
		target = "discard",
		title = "Not feeling this hand?",
		body = "Discard swaps your selected cards for new ones -- it costs a Discard, not a Hand, so it's free to fish for something better.",
		button = "Got it",
	},
	{
		id = "sidebar_info",
		mode = MODE_SPOTLIGHT,
		target = "sidebar",
		title = "Keep an eye on these",
		body = "Your Round target score, your Tips, and your Hands/Discards remaining -- all live right here. Run out of Hands before hitting the target and the Round's lost.",
		button = "Got it",
	},
	{
		id = "waiting_for_round",
		mode = MODE_LIGHT,
		body = "Keep playing hands until you clear the Round's target score!",
	},
	{
		id = "shop_patrons",
		mode = MODE_SPOTLIGHT,
		target = "shop",
		title = "The Shop",
		body = "Clearing a Round pays Tips -- spend them here. Patrons sit at your table and passively boost your scoring every hand after this, so grab one that fits the hand you're building.",
		button = "Got it, let's go!",
	},
	{
		id = "next_round",
		mode = MODE_SPOTLIGHT,
		target = "nextRound",
		title = "You're all set",
		body = "Hit Next Round whenever you're ready. Good luck out there!",
	},
}

local CAPTION_WIDTH = 360
local SPOTLIGHT_PADDING = 10
local DIM_TRANSPARENCY = 0.55

return function(deps)
	local root = deps.root
	local tweenTo = deps.tweenTo
	local polishPanel = deps.polishPanel
	local playClickSfx = deps.playClickSfx
	local addButtonHoverScale = deps.addButtonHoverScale
	local MarkTutorialSeenRemote = deps.MarkTutorialSeenRemote

	local TARGETS = {
		hand = deps.handFrame,
		play = deps.playButton,
		discard = deps.discardButton,
		sidebar = { deps.sidebarScoreBox, deps.sidebarTipsBox, deps.sidebarHandsDiscardsBox },
		shop = deps.shopBuyListFrame,
		nextRound = deps.nextRoundButton,
	}

	-- ===== Spotlight chrome (4 dark "cutout" frames + a pulsing border) =====
	-- Same 4-rectangle trick used anywhere a precise rectangular hole is
	-- needed in a UI with no real masking primitive: size/position each of
	-- Top/Bottom/Left/Right to exactly surround the target rect, leaving
	-- the rect itself uncovered. "Active = true" is the actual FOCUS part
	-- of "focus on what to click" -- these don't just look dim, they
	-- physically block clicks to anything dimmed out, same as a real
	-- spotlight forcing your attention.
	local function makeDimFrame(name)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		frame.BackgroundTransparency = DIM_TRANSPARENCY
		frame.BorderSizePixel = 0
		frame.Active = true
		frame.ZIndex = 50
		frame.Visible = false
		frame.Parent = root
		return frame
	end

	local darkTop = makeDimFrame("TutorialDimTop")
	local darkBottom = makeDimFrame("TutorialDimBottom")
	local darkLeft = makeDimFrame("TutorialDimLeft")
	local darkRight = makeDimFrame("TutorialDimRight")

	local highlightFrame = Instance.new("Frame")
	highlightFrame.Name = "TutorialHighlight"
	highlightFrame.BackgroundTransparency = 1
	highlightFrame.BorderSizePixel = 0
	highlightFrame.ZIndex = 51
	highlightFrame.Visible = false
	highlightFrame.Parent = root

	local highlightCorner = Instance.new("UICorner")
	highlightCorner.CornerRadius = UDim.new(0, 12)
	highlightCorner.Parent = highlightFrame

	local highlightStroke = Instance.new("UIStroke")
	highlightStroke.Thickness = 3
	highlightStroke.Color = Color3.fromRGB(255, 214, 130)
	highlightStroke.Transparency = 0.1
	highlightStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	highlightStroke.Parent = highlightFrame

	-- Breathing pulse on the border -- loops forever while a spotlight is
	-- up, paused (not destroyed) the rest of the time. A real Tween with
	-- RepeatCount=-1/Reverses=true, not a manual task.wait loop -- cheaper
	-- and can't drift.
	local pulseTween = TweenService:Create(
		highlightStroke,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.6 }
	)

	-- ===== Caption card (title + body + optional single action button) =====
	local captionCard = Instance.new("Frame")
	captionCard.Name = "TutorialCaption"
	captionCard.Size = UDim2.new(0, CAPTION_WIDTH, 0, 0)
	captionCard.AutomaticSize = Enum.AutomaticSize.Y
	captionCard.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	captionCard.Active = true
	captionCard.ZIndex = 52
	captionCard.Visible = false
	captionCard.Parent = root
	polishPanel(captionCard, 14)

	local captionStroke = Instance.new("UIStroke")
	captionStroke.Thickness = 2
	captionStroke.Color = Color3.fromRGB(90, 60, 30)
	captionStroke.Parent = captionCard

	local captionPadding = Instance.new("UIPadding")
	captionPadding.PaddingTop = UDim.new(0, 16)
	captionPadding.PaddingBottom = UDim.new(0, 16)
	captionPadding.PaddingLeft = UDim.new(0, 18)
	captionPadding.PaddingRight = UDim.new(0, 18)
	captionPadding.Parent = captionCard

	local captionLayout = Instance.new("UIListLayout")
	captionLayout.Padding = UDim.new(0, 8)
	captionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	captionLayout.Parent = captionCard

	local function makeCaptionText(order, font, size, color)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextSize = size
		label.TextColor3 = color
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = order
		label.ZIndex = 52
		label.Text = ""
		label.Parent = captionCard
		return label
	end

	local captionTitle = makeCaptionText(1, Enum.Font.GothamBlack, 18, Color3.fromRGB(255, 214, 130))
	local captionBody = makeCaptionText(2, Enum.Font.Gotham, 14, Color3.fromRGB(230, 220, 205))

	local captionActionButton = Instance.new("TextButton")
	captionActionButton.Size = UDim2.new(1, 0, 0, 36)
	captionActionButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	captionActionButton.Font = Enum.Font.GothamBold
	captionActionButton.TextSize = 15
	captionActionButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	captionActionButton.Text = "Got it"
	captionActionButton.LayoutOrder = 3
	captionActionButton.ZIndex = 52
	captionActionButton.Visible = false
	captionActionButton.Parent = captionCard
	polishPanel(captionActionButton, 10)
	if addButtonHoverScale then
		addButtonHoverScale(captionActionButton)
	end

	local skipLink = Instance.new("TextButton")
	skipLink.Size = UDim2.new(1, 0, 0, 16)
	skipLink.BackgroundTransparency = 1
	skipLink.AutoButtonColor = false
	skipLink.Font = Enum.Font.Gotham
	skipLink.TextSize = 12
	skipLink.TextColor3 = Color3.fromRGB(180, 170, 155)
	skipLink.Text = "Skip tutorial"
	skipLink.LayoutOrder = 4
	skipLink.ZIndex = 52
	skipLink.Parent = captionCard

	-- ===== State =====
	local active = false
	local completed = false
	local currentStepIndex = 0
	local hasDiscardedAlready = false
	local currentTarget = nil -- Instance | {Instance, ...} | nil
	local heartbeatConn = nil
	local captionActionConn = nil

	local function setCaptionButton(labelOrNil, onClick)
		if captionActionConn then
			captionActionConn:Disconnect()
			captionActionConn = nil
		end
		if labelOrNil then
			captionActionButton.Text = labelOrNil
			captionActionButton.Visible = true
			captionActionConn = captionActionButton.MouseButton1Click:Connect(function()
				playClickSfx()
				onClick()
			end)
		else
			captionActionButton.Visible = false
		end
	end

	-- x, y, w, h: root-relative pixel rect, already padded.
	local function computeRect(targetOrList)
		local list = targetOrList
		if typeof(targetOrList) == "Instance" then
			list = { targetOrList }
		end
		local rootPos = root.AbsolutePosition
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, inst in ipairs(list) do
			local pos = inst.AbsolutePosition
			local size = inst.AbsoluteSize
			minX = math.min(minX, pos.X)
			minY = math.min(minY, pos.Y)
			maxX = math.max(maxX, pos.X + size.X)
			maxY = math.max(maxY, pos.Y + size.Y)
		end
		local x = (minX - rootPos.X) - SPOTLIGHT_PADDING
		local y = (minY - rootPos.Y) - SPOTLIGHT_PADDING
		local w = (maxX - minX) + SPOTLIGHT_PADDING * 2
		local h = (maxY - minY) + SPOTLIGHT_PADDING * 2
		return x, y, w, h
	end

	local function repositionCaption(x, y, w, h)
		local rootSize = root.AbsoluteSize
		local cx = math.clamp(x + w / 2 - CAPTION_WIDTH / 2, 12, math.max(12, rootSize.X - CAPTION_WIDTH - 12))
		local captionHeight = math.max(captionCard.AbsoluteSize.Y, 70)
		local belowY = y + h + 16
		local aboveY = y - 16 - captionHeight
		local cy
		if belowY + captionHeight <= rootSize.Y - 12 then
			cy = belowY
		elseif aboveY >= 12 then
			cy = aboveY
		else
			cy = math.clamp(belowY, 12, math.max(12, rootSize.Y - captionHeight - 12))
		end
		captionCard.Position = UDim2.new(0, cx, 0, cy)
	end

	-- Recomputed every Heartbeat while a spotlight step is up, not just
	-- once on show -- the hand grid, Shop list, and sidebar can all
	-- reflow (new cards dealt, window resized) while the player is
	-- looking right at them.
	local function updateSpotlightPositions()
		if not currentTarget then
			return
		end
		local ok = pcall(function()
			local rootSize = root.AbsoluteSize
			local x, y, w, h = computeRect(currentTarget)
			x = math.clamp(x, 0, rootSize.X)
			y = math.clamp(y, 0, rootSize.Y)
			w = math.clamp(w, 0, rootSize.X - x)
			h = math.clamp(h, 0, rootSize.Y - y)

			darkTop.Position = UDim2.new(0, 0, 0, 0)
			darkTop.Size = UDim2.new(0, rootSize.X, 0, y)

			darkBottom.Position = UDim2.new(0, 0, 0, y + h)
			darkBottom.Size = UDim2.new(0, rootSize.X, 0, math.max(0, rootSize.Y - (y + h)))

			darkLeft.Position = UDim2.new(0, 0, 0, y)
			darkLeft.Size = UDim2.new(0, x, 0, h)

			darkRight.Position = UDim2.new(0, x + w, 0, y)
			darkRight.Size = UDim2.new(0, math.max(0, rootSize.X - (x + w)), 0, h)

			highlightFrame.Position = UDim2.new(0, x, 0, y)
			highlightFrame.Size = UDim2.new(0, w, 0, h)

			repositionCaption(x, y, w, h)
		end)
		if not ok then
			-- A target that's momentarily off-tree (mid rebuild) shouldn't
			-- ever hard-error the whole render loop -- just skip this frame,
			-- the next Heartbeat tries again.
			return
		end
	end

	local function startFollowing()
		if heartbeatConn then
			return
		end
		heartbeatConn = RunService.Heartbeat:Connect(updateSpotlightPositions)
	end

	local function stopFollowing()
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end

	local function hideSpotlightChrome()
		stopFollowing()
		pulseTween:Pause()
		darkTop.Visible = false
		darkBottom.Visible = false
		darkLeft.Visible = false
		darkRight.Visible = false
		highlightFrame.Visible = false
		currentTarget = nil
	end

	local showStep -- forward declare, used by advanceFrom below

	local function advanceFrom(expectedId)
		if not active then
			return
		end
		local step = STEPS[currentStepIndex]
		if not step or step.id ~= expectedId then
			return
		end
		showStep(currentStepIndex + 1)
	end

	local function completeWalkthrough()
		if completed then
			return
		end
		completed = true
		active = false
		hideSpotlightChrome()
		captionCard.Visible = false
		MarkTutorialSeenRemote:FireServer()
	end

	skipLink.MouseButton1Click:Connect(function()
		if not active then
			return
		end
		playClickSfx()
		completeWalkthrough()
	end)

	showStep = function(index)
		local step = STEPS[index]
		if not step then
			completeWalkthrough()
			return
		end

		-- Order-independent play: if the player already discarded (e.g.
		-- before ever playing a hand), this step has nothing left to
		-- teach -- skip straight through instead of asking them to read
		-- about something they already did.
		if step.id == "discard_info" and hasDiscardedAlready then
			showStep(index + 1)
			return
		end

		currentStepIndex = index
		captionCard.Visible = true
		captionTitle.Visible = step.title ~= nil
		captionTitle.Text = step.title or ""
		captionBody.Text = step.body or ""

		if step.button then
			setCaptionButton(step.button, function()
				advanceFrom(step.id)
			end)
		else
			setCaptionButton(nil)
		end

		if step.mode == MODE_SPOTLIGHT then
			currentTarget = TARGETS[step.target]
			darkTop.Visible = true
			darkBottom.Visible = true
			darkLeft.Visible = true
			darkRight.Visible = true
			highlightFrame.Visible = true
			pulseTween:Play()
			updateSpotlightPositions()
			startFollowing()
			return
		end

		-- MODE_CENTER / MODE_LIGHT both have no single element to cut a
		-- hole around -- just position the caption and (for CENTER only)
		-- dim the whole screen evenly with no cutout at all.
		hideSpotlightChrome()
		local rootSize = root.AbsoluteSize
		if step.mode == MODE_CENTER then
			darkTop.Position = UDim2.new(0, 0, 0, 0)
			darkTop.Size = UDim2.new(0, rootSize.X, 0, rootSize.Y)
			darkTop.Visible = true
			captionCard.Position = UDim2.new(0, rootSize.X / 2 - CAPTION_WIDTH / 2, 0, rootSize.Y / 2 - 90)
		else
			captionCard.Position = UDim2.new(0, rootSize.X / 2 - CAPTION_WIDTH / 2, 1, -120)
		end
	end

	local function start()
		if active or completed then
			return
		end
		active = true
		showStep(1)
	end

	local function notifySelectionChanged(count)
		if not active or count < 1 then
			return
		end
		advanceFrom("select_cards")
	end

	local function notifyHandPlayed()
		if not active then
			return
		end
		if not (STEPS[currentStepIndex] and STEPS[currentStepIndex].id == "play_hand") then
			return
		end
		-- Hides immediately, synchronously, the instant the hand is played
		-- -- the score popup/Legendary/Wildcard reveal is about to take
		-- over the screen for several seconds, and this can never be
		-- allowed to still be sitting on top of (or racing z-order with)
		-- that sequence.
		hideSpotlightChrome()
		captionCard.Visible = false

		-- Deliberately does NOT call showStep(nextIndex) right away --
		-- that would show the NEXT step's own spotlight immediately,
		-- right as the reveal is starting, exactly the collision this is
		-- trying to avoid. Bumps currentStepIndex now (so a repeat/
		-- out-of-order notify in the meantime still resolves correctly --
		-- see notifyDiscardUsed's own matching logic) and shows it for
		-- real after a delay sized to comfortably clear a normal reveal.
		-- There's no existing "the reveal finished" signal to hang this
		-- off of instead, and adding one in ScorePopup.lua isn't worth it
		-- for a single one-time tutorial moment.
		local nextIndex = currentStepIndex + 1
		currentStepIndex = nextIndex
		task.delay(4.5, function()
			-- Only still correct if NOTHING else advanced past this step
			-- in the meantime (e.g. the player discarded during the gap,
			-- which resolves discard_info on its own -- see
			-- notifyDiscardUsed). If currentStepIndex has moved on, this
			-- would just be showing a stale, already-passed step.
			if active and currentStepIndex == nextIndex then
				showStep(nextIndex)
			end
		end)
	end

	local function notifyDiscardUsed()
		hasDiscardedAlready = true
		advanceFrom("discard_info")
	end

	local function notifyEnteredShop()
		advanceFrom("waiting_for_round")
	end

	-- Called every render() regardless of whether the walkthrough is
	-- active (mirrors PhaseAModule.announceBossIfNew's own convention) --
	-- the ONE transition this module needs real server state for: moving
	-- off the menu-safe "waiting_for_run_start" step the instant a run
	-- actually begins (state.phase flips to "playing"). Every other step
	-- advances purely off the explicit notify*() calls above.
	local function onRender(state)
		if not active or not state then
			return
		end
		local step = STEPS[currentStepIndex]
		if step and step.id == "waiting_for_run_start" and state.phase == "playing" then
			showStep(currentStepIndex + 1)
		end
	end

	local function notifyNextRoundClicked()
		if not active then
			return
		end
		if STEPS[currentStepIndex] and STEPS[currentStepIndex].id == "next_round" then
			completeWalkthrough()
		end
	end

	return {
		start = start,
		onRender = onRender,
		notifySelectionChanged = notifySelectionChanged,
		notifyHandPlayed = notifyHandPlayed,
		notifyDiscardUsed = notifyDiscardUsed,
		notifyEnteredShop = notifyEnteredShop,
		notifyNextRoundClicked = notifyNextRoundClicked,
	}
end
