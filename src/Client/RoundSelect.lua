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
		                     the Tip Jar Tag (and the On the House Tag's Tips
		                     fallback)
		showUnlockPopup   -- function(name, description) -- reused for the
		                     On the House Tag's free-Patron grant
		showWarning       -- function(text) -- reused for the Happy Hour
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
	local playClickSfx = deps.playClickSfx
	local tweenTo = deps.tweenTo
	local addTooltip = deps.addTooltip
	local BossRounds = deps.BossRounds
	local RunStateEngine = deps.RunStateEngine
	local SelectRoundRemote = deps.SelectRoundRemote
	local SkipRoundRemote = deps.SkipRoundRemote
	local showRoundReward = deps.showRoundReward
	local showUnlockPopup = deps.showUnlockPopup
	local showWarning = deps.showWarning
	local getLatestState = deps.getLatestState

	-- Same "solid opaque panel that just covers everything" trick shopFrame
	-- uses (see Shop.lua) instead of hiding the game table underneath --
	-- render() only toggles .Visible, nothing about the table itself needs
	-- to change.
	local roundSelectFrame = Instance.new("Frame")
	roundSelectFrame.Name = "RoundSelect"
	roundSelectFrame.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 1, 0)
	roundSelectFrame.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, 0)
	roundSelectFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	roundSelectFrame.Visible = false
	roundSelectFrame.ZIndex = 6 -- matches shopFrame -- see Shop.lua for why (beats the corner icon buttons)
	roundSelectFrame.Parent = root
	polishPanel(roundSelectFrame, 16)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -40, 0, 44)
	titleLabel.Position = UDim2.new(0, 20, 0, 16)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 26
	titleLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	titleLabel.Text = "This Night"
	titleLabel.ZIndex = 7
	titleLabel.Parent = roundSelectFrame

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.new(1, -40, 0, 24)
	subtitleLabel.Position = UDim2.new(0, 20, 0, 58)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextSize = 14
	subtitleLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.Text = "Play the round you're on, or skip it for a Tag instead."
	subtitleLabel.ZIndex = 7
	subtitleLabel.Parent = roundSelectFrame

	local panelRow = Instance.new("Frame")
	panelRow.Size = UDim2.new(1, -40, 1, -180)
	panelRow.Position = UDim2.new(0, 20, 0, 96)
	panelRow.BackgroundTransparency = 1
	panelRow.ZIndex = 7
	panelRow.Parent = roundSelectFrame

	local panelRowLayout = Instance.new("UIListLayout")
	panelRowLayout.FillDirection = Enum.FillDirection.Horizontal
	panelRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelRowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
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

	-- One static panel per round of a Night, built once, refreshed by
	-- rebuildRoundSelect below (same "build once, refresh in place"
	-- pattern as Journey.lua's stage nodes / Shop.lua's offer rows).
	local roundPanels = {}
	for round = 1, ROUNDS_PER_NIGHT do
		local panel = Instance.new("Frame")
		panel.Name = "RoundPanel" .. round
		panel.Size = UDim2.new(0, 220, 1, 0)
		panel.LayoutOrder = round
		panel.BackgroundColor3 = Color3.fromRGB(55, 42, 30)
		panel.ZIndex = 7
		panel.Parent = panelRow
		roundCorner(panel, 14)

		local headerLabel = Instance.new("TextLabel")
		headerLabel.Size = UDim2.new(1, -20, 0, 30)
		headerLabel.Position = UDim2.new(0, 10, 0, 14)
		headerLabel.BackgroundTransparency = 1
		headerLabel.Font = Enum.Font.GothamBold
		headerLabel.TextSize = 18
		headerLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
		headerLabel.Text = string.format("Round %d", round)
		headerLabel.ZIndex = 8
		headerLabel.Parent = panel

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Size = UDim2.new(1, -20, 0, 20)
		statusLabel.Position = UDim2.new(0, 10, 0, 44)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.Gotham
		statusLabel.TextSize = 12
		statusLabel.TextColor3 = Color3.fromRGB(200, 185, 165)
		statusLabel.Text = ""
		statusLabel.ZIndex = 8
		statusLabel.Parent = panel

		local targetLabel = Instance.new("TextLabel")
		targetLabel.Size = UDim2.new(1, -20, 0, 40)
		targetLabel.Position = UDim2.new(0, 10, 0, 68)
		targetLabel.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
		targetLabel.Font = Enum.Font.GothamBold
		targetLabel.TextSize = 20
		targetLabel.TextColor3 = Color3.fromRGB(120, 170, 255)
		targetLabel.Text = ""
		targetLabel.ZIndex = 8
		targetLabel.Parent = panel
		roundCorner(targetLabel, 8)

		local bossLabel = Instance.new("TextLabel")
		bossLabel.Size = UDim2.new(1, -20, 0, 78)
		bossLabel.Position = UDim2.new(0, 10, 0, 116)
		bossLabel.BackgroundTransparency = 1
		bossLabel.Font = Enum.Font.Gotham
		bossLabel.TextSize = 12
		bossLabel.TextColor3 = Color3.fromRGB(230, 180, 170)
		bossLabel.TextWrapped = true
		bossLabel.TextYAlignment = Enum.TextYAlignment.Top
		bossLabel.Text = ""
		bossLabel.ZIndex = 8
		bossLabel.Parent = panel

		-- Tag preview -- only ever filled in for the CURRENT round (see
		-- rebuildRoundSelect); every other round's panel leaves this blank
		-- (or explains why, on a future round).
		local tagLabel = Instance.new("TextLabel")
		tagLabel.Size = UDim2.new(1, -20, 0, 78)
		tagLabel.Position = UDim2.new(0, 10, 0, 116)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = Enum.Font.Gotham
		tagLabel.TextSize = 12
		tagLabel.TextColor3 = Color3.fromRGB(200, 220, 170)
		tagLabel.TextWrapped = true
		tagLabel.TextYAlignment = Enum.TextYAlignment.Top
		tagLabel.Text = ""
		tagLabel.ZIndex = 8
		tagLabel.Parent = panel

		local selectButton = Instance.new("TextButton")
		selectButton.Size = UDim2.new(1, -20, 0, 40)
		selectButton.Position = UDim2.new(0, 10, 1, -92)
		selectButton.Font = Enum.Font.GothamBold
		selectButton.TextSize = 16
		selectButton.Text = "Select"
		selectButton.BackgroundColor3 = Color3.fromRGB(70, 130, 70)
		selectButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		selectButton.ZIndex = 8
		selectButton.Visible = false
		selectButton.Parent = panel
		polishButton(selectButton, 10)

		local skipButton = Instance.new("TextButton")
		skipButton.Size = UDim2.new(1, -20, 0, 40)
		skipButton.Position = UDim2.new(0, 10, 1, -46)
		skipButton.Font = Enum.Font.GothamBold
		skipButton.TextSize = 14
		skipButton.Text = "Skip"
		skipButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		skipButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		skipButton.ZIndex = 8
		skipButton.Visible = false
		skipButton.Parent = panel
		polishButton(skipButton, 10)

		selectButton.MouseButton1Click:Connect(function()
			if actionPending then
				return
			end
			actionPending = true
			playClickSfx()
			SelectRoundRemote:FireServer()
		end)

		-- The actual reward text depends on which Tag is currently
		-- revealed (Tips vs a free Patron vs a discount) -- read fresh at
		-- click time, same "never trust a stale local" rule the Journey
		-- map's Skip button already follows (see that file's BUGFIX
		-- comment for why this can't just fire the popup here instead of
		-- off a confirmed state change).
		skipButton.MouseButton1Click:Connect(function()
			if actionPending then
				return
			end
			local latestState = getLatestState()
			if not (latestState and latestState.canSkipRound) then
				return -- button is visually hidden in this state, see rebuildRoundSelect
			end
			actionPending = true
			playClickSfx()
			SkipRoundRemote:FireServer()
		end)

		table.insert(roundPanels, {
			round = round,
			panel = panel,
			headerLabel = headerLabel,
			statusLabel = statusLabel,
			targetLabel = targetLabel,
			bossLabel = bossLabel,
			tagLabel = tagLabel,
			selectButton = selectButton,
			skipButton = skipButton,
		})
	end

	-- JOURNEY FEATURE / ROUND SELECT FEATURE: describes a Tag's effect the
	-- SAME way for both the panel's own tagLabel text and its tooltip, so
	-- the two can never say different things.
	local function describeTag(tag)
		return string.format("%s %s\n%s", tag.icon or "🏷️", tag.name, tag.description)
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
		elseif tag.id == "happy_hour" and showWarning then
			showWarning("Happy Hour Tag: your next shop visit is discounted!")
		end
	end

	local function rebuildRoundSelect(state, previousPhase)
		-- See actionPending's BUGFIX comment above: any fresh state push
		-- means whatever click caused it has definitely been resolved
		-- (accepted or rejected) by now, so clicking is safe again.
		actionPending = false

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
		-- BALATRO PARITY: an "Ante counter" (1/8, then Endless Mode) --
		-- shows "/nightCap" while under it, "(Endless)" once past for good
		-- (state.night only ever increases, so once you're past nightCap
		-- you never see the "/8" form again this run).
		local nightCap = state.nightCap or 8
		if state.night > nightCap then
			titleLabel.Text = string.format("Night %d (Endless)", state.night)
		else
			titleLabel.Text = string.format("Night %d/%d", state.night, nightCap)
		end
		subtitleLabel.Text = state.round == 1
			and "A new Night begins! Play the round you're on, or skip it for a Tag instead."
			or "Play the round you're on, or skip it for a Tag instead."

		local currentRound = state.round

		for _, entry in ipairs(roundPanels) do
			local isBossRound = (entry.round == ROUNDS_PER_NIGHT)
			local isPast = entry.round < currentRound
			local isCurrent = entry.round == currentRound
			-- BUGFIX: pass THIS run's nightCap (server-sent, see
			-- serializeState) through so a Boss Blind preview here always
			-- matches what RunState.startRound will actually compute
			-- server-side, instead of assuming the global default.
			local target = RunStateEngine.targetScoreFor(state.night, entry.round, ROUNDS_PER_NIGHT, state.nightCap)

			-- BALATRO PARITY: Small Blind (round 1, 1x target) / Big Blind
			-- (any round between, 1.5x) / Boss Blind (last round, 2x-6x
			-- scaling with Night) -- matches RunState.blindMultiplierFor,
			-- and the sidebar's blindInfoLabel uses the same naming.
			if isBossRound then
				entry.headerLabel.Text = "Boss Round"
			elseif entry.round == 1 then
				entry.headerLabel.Text = "Small Round"
			else
				entry.headerLabel.Text = string.format("Big Round %d", entry.round)
			end
			entry.targetLabel.Text = string.format("Target: %d", target)

			if isPast then
				entry.statusLabel.Text = "Cleared"
				entry.panel.BackgroundColor3 = Color3.fromRGB(45, 55, 45)
			elseif isCurrent then
				entry.statusLabel.Text = "You are here"
				entry.panel.BackgroundColor3 = Color3.fromRGB(70, 55, 38)
			else
				entry.statusLabel.Text = "Up next"
				entry.panel.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
			end

			if isBossRound then
				entry.bossLabel.Visible = true
				entry.tagLabel.Visible = false
				if state.nightBossModifier then
					entry.bossLabel.Text = string.format("👑 %s\n%s", state.nightBossModifier.name, state.nightBossModifier.description)
				elseif state.bossModifier then
					-- Defensive fallback: we're somehow already ON the Boss
					-- round (bossModifier set) but nightBossModifier wasn't
					-- sent -- use the one we definitely have.
					entry.bossLabel.Text = string.format("👑 %s\n%s", state.bossModifier.name, state.bossModifier.description)
				else
					entry.bossLabel.Text = "Boss Rounds are off this run."
				end
			else
				entry.bossLabel.Visible = false
				entry.tagLabel.Visible = true
				if isCurrent and state.currentRoundSkipTag then
					entry.tagLabel.Text = "Skip for: " .. describeTag(state.currentRoundSkipTag)
				elseif isPast then
					entry.tagLabel.Text = ""
				else
					entry.tagLabel.Text = "Tag revealed once you reach this round."
				end
			end

			-- Only the round you're actually on gets buttons -- everything
			-- else here is a preview, matching the reference game (you can
			-- only ever act on the CURRENT blind).
			entry.selectButton.Visible = isCurrent
			entry.skipButton.Visible = isCurrent and state.canSkipRound == true
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
