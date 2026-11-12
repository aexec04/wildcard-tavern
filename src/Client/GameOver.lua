--[[
	Client/GameOver.lua
	The ONE Run Over screen, shown when state.phase == "gameover" (a loss, or a win: "Last call, but what a night!"). It replaces the old
	pair of screens (this Game Over panel, then the Run Summary modal behind a Continue button). One container frame, RunOverPanel,
	with named child frames so a painted scroll can sit behind it later (run_over_scroll art):
	  Title     icon and "Last call! You made it to Night N, Round R." (or the win line), the Revived badge
	  Facts     best hand, final score, Tips banked, road taken, blessing, next unlock, seed line, best Endless strip, a tip
	  PatronsLabel, Patrons   "Patrons used" and a medallion with the name under it for each
	  Actions   One More Round (only when offered), Play Again, Back to Tavern
	  More      Share result, Challenge a friend, Invite friends, Save as my badge, Win Card (only after a win or a new best)
	Rects come from the tested Engine/RunOverLayout: two columns on wide screens (left facts, right Patrons and actions), one column
	on narrow ones, scaled down only when the panel is still taller than the screen. Text is 15 px or more. Everything the old
	screens did still works through the same remotes: One More Round, Play Again, Back to Tavern, Save as my badge, Win Card, Share,
	Challenge, Invite.

	deps: root, polishPanel, polishButton, addSoftShadow, tweenTo, playSfx, SOUND_IDS, gameOverWinBackgroundImage,
	      playClick (function), saveBadge (function), makeSeed (function, Challenge a friend)

	Returns { gameOverFrame, playAgainButton, continueButton, tavernButton, refreshGameOver = function(state, bestHand) }
	(the click handlers for Play Again, Back to Tavern and One More Round are wired in init.client.lua next to their remotes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local GameOverTips = require(Engine:WaitForChild("GameOverTips"))
local RunOverLayout = require(Engine:WaitForChild("RunOverLayout"))
local SeedDisplay = require(Engine:WaitForChild("SeedDisplay"))
local ShareResult = require(Engine:WaitForChild("ShareResult"))
local EndlessRules = require(Engine:WaitForChild("EndlessRules"))
local WinCardRules = require(Engine:WaitForChild("WinCard"))

local CREAM = Color3.fromRGB(250, 240, 220)
local GOLD_TEXT = Color3.fromRGB(255, 214, 130)
local SOFT = Color3.fromRGB(235, 222, 195)
local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local WOOD = Color3.fromRGB(70, 50, 34)
local GREEN = Color3.fromRGB(60, 110, 70)
local BRASS = Color3.fromRGB(196, 150, 60)

local FACT_SIZE = 17
local LINE_PAD = 6

return function(deps)
	local root = deps.root
	local polishPanel, polishButton, addSoftShadow = deps.polishPanel, deps.polishButton, deps.addSoftShadow
	local playSfx, SOUND_IDS = deps.playSfx, deps.SOUND_IDS

	-- dim: the full-screen dark dim (hides the table so no cards peek out) and click sink; one Visible flag shows and hides all.
	local dim = Instance.new("Frame")
	dim.Name = "GameOver"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 8, 6)
	dim.BackgroundTransparency = 0.25
	dim.BorderSizePixel = 0
	dim.Active = true
	dim.Visible = false
	dim.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "RunOverPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(760, 460)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.Active = true
	panel.Parent = dim
	polishPanel(panel, 16, "wood")
	local fit = Instance.new("UIScale")
	fit.Parent = panel
	local panelArt = require(script.Parent.PanelArt).add(panel, {
		key = "game_over_lose_bg", zIndex = 20, scrim = { position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 1) },
		scrimTransparency = 0.35,
	})
	addSoftShadow(panel, 18)
	local winArt = Instance.new("ImageLabel") -- celebration picture, shown only on a win (still empty until an id is filled in)
	winArt.Name = "WinBackgroundArt"
	winArt.Size = UDim2.fromScale(1, 1)
	winArt.BackgroundTransparency = 1
	winArt.ImageTransparency = 0.15
	winArt.BorderSizePixel = 0
	winArt.ScaleType = Enum.ScaleType.Crop
	winArt.Image = deps.gameOverWinBackgroundImage or "rbxassetid://0"
	winArt.Visible = false
	winArt.ZIndex = 20
	winArt.Parent = panel

	local function frame(name, parent)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 22
		f.Parent = parent or panel
		return f
	end
	local function place(f, r)
		f.Position = UDim2.fromOffset(math.floor(r.x + 0.5), math.floor(r.y + 0.5))
		f.Size = UDim2.fromOffset(math.floor(r.w + 0.5), math.floor(r.h + 0.5))
	end
	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = FACT_SIZE
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.ZIndex = 23
		for k, v in pairs(props) do l[k] = v end
		l.Parent = parent
		return l
	end
	local function button(parent, name, text, color, textColor, size)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = text
		b.Font = Enum.Font.GothamBold
		b.TextSize = size or 17
		b.TextWrapped = true
		b.TextColor3 = textColor or CREAM
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		b.BackgroundColor3 = color
		b.ZIndex = 24
		b.Parent = parent
		polishButton(b, 10)
		return b
	end

	-- ===== named frames =====
	local titleF = frame("Title")
	local iconLabel = label(titleF, {
		Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(0, 4), TextSize = 40, Text = "\u{1F56F}\u{FE0F}",
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false,
	})
	local titleLabel = label(titleF, {
		Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(58, 0), TextSize = 26, Text = "", TextYAlignment = Enum.TextYAlignment.Center,
	})
	local revivedBadge = label(titleF, {
		Name = "RevivedBadge", AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(110, 26), Position = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 120, 150), TextSize = 15, Text = "\u{1F4AB} Revived",
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Visible = false,
	})
	polishPanel(revivedBadge, 13)
	local factsF = frame("Facts")
	local patronsLabel = label(panel, { Name = "PatronsLabel", Text = "Patrons used", TextSize = 18, TextColor3 = GOLD_TEXT })
	patronsLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local patronsF = frame("Patrons")
	patronsF.BackgroundTransparency = 0.15
	patronsF.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	local pk = Instance.new("UICorner")
	pk.CornerRadius = UDim.new(0, 10)
	pk.Parent = patronsF
	local noPatrons = label(patronsF, {
		Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), Text = "No Patrons this time.", TextSize = 16,
		Font = Enum.Font.GothamMedium, TextYAlignment = Enum.TextYAlignment.Center, Visible = false,
	})
	local actionsF = frame("Actions")
	local moreF = frame("More")

	local continueButton = button(actionsF, "ContinueButton", "One More Round", GREEN, CREAM, 18)
	local playAgainButton = button(actionsF, "PlayAgain", "Play Again", BRASS, Color3.fromRGB(40, 28, 14), 18)
	local tavernButton = button(actionsF, "BackToTavern", "Back to Tavern", WOOD, CREAM, 18)
	local shareButton = button(moreF, "ShareResult", "Share result", WOOD, CREAM, 15)
	local challengeButton = button(moreF, "ChallengeFriend", "Challenge a friend", WOOD, CREAM, 15)
	local inviteButton = button(moreF, "InviteFriends", "Invite friends", WOOD, CREAM, 15)
	local saveButton = button(moreF, "SaveBadge", "Save as my badge", GREEN, CREAM, 15)
	local winCardButton = button(moreF, "WinCard", "Win Card", GREEN, CREAM, 15)
	winCardButton.Visible = false
	require(script.Parent.InvitePrompt).bind(inviteButton)

	-- the share line: a selectable box over the first row of the More block (select it, then Ctrl+C)
	local shareBox = Instance.new("TextBox")
	shareBox.Name = "ShareSeedBox"
	shareBox.BackgroundColor3 = Color3.fromRGB(26, 17, 10)
	shareBox.BorderSizePixel = 0
	shareBox.Font = Enum.Font.GothamBold
	shareBox.TextSize = 15
	shareBox.TextColor3 = Color3.fromRGB(255, 232, 160)
	shareBox.TextEditable = false
	shareBox.ClearTextOnFocus = false
	shareBox.TextTruncate = Enum.TextTruncate.AtEnd
	shareBox.Visible = false
	shareBox.ZIndex = 24
	shareBox.Parent = moreF
	local sk = Instance.new("UICorner")
	sk.CornerRadius = UDim.new(0, 8)
	sk.Parent = shareBox
	shareBox.Focused:Connect(function()
		shareBox.SelectionStart = 1
		shareBox.CursorPosition = #shareBox.Text + 1
	end)
	local shareHint = label(moreF, { Name = "ShareHint", Text = "Select the line, then press Ctrl+C.", TextSize = 15, Font = Enum.Font.GothamMedium, Visible = false })

	local lastState, lastSummary
	local layoutNow -- set below; re-lays the panel out for the current screen size

	local function click()
		if deps.playClick then deps.playClick() end
	end
	local function showBox(text)
		shareBox.Text = text
		shareButton.Visible, challengeButton.Visible, inviteButton.Visible = false, false, false
		shareBox.Visible, shareHint.Visible = true, true
		shareBox:CaptureFocus()
	end
	shareButton.MouseButton1Click:Connect(function()
		click()
		local seedInfo = SeedDisplay.label(lastState)
		showBox(ShareResult.line(lastSummary, seedInfo and seedInfo.kind == "seed" and seedInfo.value or nil))
	end)
	challengeButton.MouseButton1Click:Connect(function()
		click()
		-- a Seed Run challenges with its own code; any other run asks the server for a fresh one to play together
		local seedInfo = SeedDisplay.label(lastState)
		local code = seedInfo and seedInfo.kind == "seed" and seedInfo.value or nil
		if not code and deps.makeSeed then
			local ok, made = pcall(deps.makeSeed)
			code = ok and made or nil
		end
		if code then showBox(ShareResult.challengeLine(lastSummary, code)) end
	end)
	saveButton.MouseButton1Click:Connect(function()
		if saveButton.Active and deps.saveBadge then
			click()
			deps.saveBadge()
		end
	end)
	winCardButton.MouseButton1Click:Connect(function()
		pcall(function() require(script.Parent.WinCard).show(root.Parent, lastState, lastSummary) end)
	end)

	-- ===== content =====
	local function clearFacts()
		for _, c in ipairs(factsF:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end
	local function clearPatrons()
		for _, c in ipairs(patronsF:GetChildren()) do
			if c:IsA("GuiObject") and c ~= noPatrons then c:Destroy() end
		end
	end

	-- the fact lines in the order the screen reads: best hand, score, Tips, road, blessing, next unlock, seed, Endless, tip
	local function factLines(state, summary, bestHand, isWin)
		local lines = {}
		local function add(text, props) lines[#lines + 1] = { text = text, props = props or {} } end
		local best = summary and summary.bestHand or bestHand
		if best then add(string.format("\u{26A1} Biggest hand: %s: %d", best.name, best.score), { TextColor3 = GOLD_TEXT }) end
		add(string.format("Final score: %d / %d", math.floor(state.roundScore or 0), math.floor(state.targetScore or 0)))
		add(string.format("Tips banked: %d", math.floor(state.tips or 0)))
		if summary then
			add("Road taken", { TextColor3 = GOLD_TEXT })
			local names = {}
			for _, stop in ipairs(summary.route or {}) do names[#names + 1] = stop.name or stop.id end
			add(#names > 0 and table.concat(names, "  >  ") or "No stops yet", { Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = SOFT })
			if summary.blessing then add("Blessing: " .. summary.blessing.name) end
		end
		if state.nextUnlock and state.nextUnlock.label then add("Next unlock: " .. state.nextUnlock.label, { TextColor3 = GOLD_TEXT }) end
		local seedInfo = SeedDisplay.label(state)
		if seedInfo then add(seedInfo.text, { Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = SOFT }) end
		if summary then
			local bestLines = EndlessRules.bestLines(summary.endlessBestByStake, summary.stake)
			if #bestLines > 0 then add("Best Endless Night   " .. table.concat(bestLines, "   |   "), { Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = SOFT }) end
		end
		local hint = (not isWin) and GameOverTips.pick(state.night, state.round) or nil
		if hint then add("Tip: " .. hint, { Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = SOFT }) end
		return lines
	end

	local current = {} -- what the screen shows now: { state, summary, bestHand, isWin, lines }

	local function buildFacts(width)
		clearFacts()
		local y = 0
		for i, line in ipairs(current.lines) do
			local size = line.props.TextSize or FACT_SIZE
			local n = RunOverLayout.estimateLines(line.text, width, size)
			local h = n * (size + 3) + LINE_PAD
			label(factsF, {
				Name = "Fact" .. i, Text = line.text, Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(width, h),
				TextSize = size, Font = line.props.Font or Enum.Font.GothamBold, TextColor3 = line.props.TextColor3 or CREAM,
			})
			y = y + h
		end
		return y
	end

	local function buildPatrons(r)
		clearPatrons()
		local summary = current.summary
		local list = summary and summary.patrons or {}
		noPatrons.Visible = #list == 0
		local PatronPlaque = require(script.Parent.PatronPlaque)
		for index, patron in ipairs(list) do
			if index > 10 then break end
			local col, rowN = (index - 1) % r.cols, math.floor((index - 1) / r.cols)
			local holder = Instance.new("Frame")
			holder.Name = "Patron" .. index
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			holder.Position = UDim2.fromOffset(8 + col * (RunOverLayout.SEAT_W + 8), 8 + rowN * (RunOverLayout.SEAT_H + 8))
			holder.Size = UDim2.fromOffset(RunOverLayout.SEAT_W, RunOverLayout.SEAT_H)
			holder.ZIndex = 23
			holder.Parent = patronsF
			local seat = Instance.new("Frame")
			seat.Name = "Medallion"
			seat.Position = UDim2.new(0.5, -26, 0, 0)
			seat.Size = UDim2.fromOffset(52, 52)
			seat.BackgroundColor3 = PARCHMENT
			seat.BorderSizePixel = 0
			seat.ZIndex = 24
			seat.Parent = holder
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = seat
			local ring = Instance.new("UIStroke")
			ring.Color = BRASS
			ring.Thickness = 2
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- never Contextual: it would stroke the text too
			ring.Parent = seat
			local emoji = label(seat, {
				Size = UDim2.fromScale(1, 1), Text = patron.icon or "?", TextSize = 24, Font = Enum.Font.GothamMedium, ZIndex = 25,
				TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = false, TextColor3 = INK,
			})
			PatronPlaque.apply(seat, patron.id, { zIndex = 26, cornerRadius = 26, emojiLabel = emoji })
			local nameLabel = label(holder, {
				Text = patron.name or patron.id, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 40), TextSize = 15,
				Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24,
			})
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end

	-- lay everything out for the current screen size and content
	layoutNow = function()
		if not current.state then return end
		local size = root.AbsoluteSize
		local sw, sh = size.X > 0 and size.X or 1280, size.Y > 0 and size.Y or 720
		local cols = RunOverLayout.columns(sw)
		local factsH = buildFacts(cols.leftW)
		local state = current.state
		local primaryList = {}
		local canContinue = state.continueOffer == "free" or state.continueOffer == "paid"
		continueButton.Visible = canContinue
		if canContinue then primaryList[#primaryList + 1] = continueButton end
		primaryList[#primaryList + 1] = playAgainButton
		primaryList[#primaryList + 1] = tavernButton
		local moreList = { shareButton, challengeButton, inviteButton, saveButton }
		local showWin = current.showWinCard
		winCardButton.Visible = showWin
		if showWin then moreList[#moreList + 1] = winCardButton end
		local patronN = math.min(10, current.summary and #current.summary.patrons or 0)
		-- six secondary cells are always reserved: the free ones hold the share hint once a share line is showing
		local r = RunOverLayout.compute(sw, sh, { factsH = factsH, patrons = patronN, primary = #primaryList, more = 6 })
		panel.Size = UDim2.fromOffset(r.panel.w, r.panel.h)
		fit.Scale = r.scale
		place(titleF, r.title)
		place(factsF, r.facts)
		place(patronsLabel, r.patronsLabel)
		place(patronsF, r.patrons)
		local ax, ay = r.primary[1].x, r.primary[1].y
		local actionsW = r.primary[#r.primary].x + r.primary[#r.primary].w - ax
		place(actionsF, { x = ax, y = ay, w = actionsW, h = r.primary[1].h })
		for i, b in ipairs(primaryList) do
			local c = r.primary[i]
			b.Position = UDim2.fromOffset(math.floor(c.x - ax + 0.5), 0)
			b.Size = UDim2.fromOffset(math.floor(c.w + 0.5), math.floor(c.h + 0.5))
		end
		local mx, my = r.more[1].x, r.more[1].y
		local last = r.more[#r.more]
		place(moreF, { x = mx, y = my, w = math.max(1, (last.x + last.w) - mx), h = (last.y + last.h) - my })
		for i, b in ipairs(moreList) do
			local c = r.more[i]
			b.Position = UDim2.fromOffset(math.floor(c.x - mx + 0.5), math.floor(c.y - my + 0.5))
			b.Size = UDim2.fromOffset(math.floor(c.w + 0.5), math.floor(c.h + 0.5))
		end
		-- the share box covers the first row of three; the hint takes the free cells after the last button
		local row1 = { r.more[1], r.more[math.min(#r.more, r.columns.mode == "wide" and 3 or 2)] }
		shareBox.Position = UDim2.fromOffset(math.floor(row1[1].x - mx + 0.5), math.floor(row1[1].y - my + 0.5))
		shareBox.Size = UDim2.fromOffset(math.floor(row1[2].x + row1[2].w - row1[1].x + 0.5), math.floor(row1[1].h + 0.5))
		local free = r.more[#moreList + 1]
		if free then
			local freeLast = free
			for i = #moreList + 2, #r.more do
				if r.more[i].y == free.y then freeLast = r.more[i] end
			end
			shareHint.Position = UDim2.fromOffset(math.floor(free.x - mx + 0.5), math.floor(free.y - my + 0.5))
			shareHint.Size = UDim2.fromOffset(math.floor(freeLast.x + freeLast.w - free.x + 0.5), math.floor(free.h + 0.5))
		end
		buildPatrons(r.patrons)
		current.rects = r
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if dim.Visible then pcall(layoutNow) end
	end)

	local lastKey = nil

	-- bestHand: optional { name, score } from Client/RunRecap.lua; the server's run summary wins when it has one.
	local function refreshGameOver(state, bestHand)
		if not state then return end
		local summary = state.runSummary
		local isWin = state.wonRun == true
		local isRevived = state.revived == true
		winArt.Visible = isWin
		if panelArt then
			panelArt.Visible = not isWin
			local scrim = panel:FindFirstChild("PanelScrim")
			if scrim then scrim.Visible = not isWin end
		end
		revivedBadge.Visible = isRevived
		continueButton.Text = state.continueOffer == "free" and "One More Round (Free)" or "One More Round"
		if isWin then
			iconLabel.Text = "\u{1F3C6}"
			titleLabel.Text = "Last call, but what a night! You beat the tavern."
		else
			iconLabel.Text = "\u{1F56F}\u{FE0F}"
			titleLabel.Text = string.format("Last call! You made it to Night %d, Round %d.", state.night, state.round)
		end

		lastState, lastSummary = state, summary
		local showWinCard = false
		if summary then
			local ok, worth = pcall(WinCardRules.worthShowing, summary, summary)
			showWinCard = ok and worth == true
		end
		local lines = factLines(state, summary, bestHand, isWin)
		current = { state = state, summary = summary, bestHand = bestHand, isWin = isWin, lines = lines, showWinCard = showWinCard }

		-- Save as my badge: on until it is saved
		local saved = summary ~= nil and summary.badgeSaved == true
		saveButton.Active = summary ~= nil and not saved
		saveButton.Text = saved and "Badge saved" or "Save as my badge"
		saveButton.BackgroundColor3 = (saved or summary == nil) and Color3.fromRGB(120, 110, 95) or GREEN
		shareButton.Active, challengeButton.Active = summary ~= nil, summary ~= nil

		local key = string.format("%s-%s-%s-%s-%s", tostring(state.night), tostring(state.round), tostring(isWin), tostring(isRevived), summary and "s" or "n")
		local fresh = key ~= lastKey
		if fresh then
			shareBox.Visible, shareHint.Visible = false, false
			shareButton.Visible, challengeButton.Visible, inviteButton.Visible = true, true, true
		end
		local ok, err = pcall(layoutNow)
		if not ok then warn("[RunOver] layout failed: " .. tostring(err)) end
		if fresh then
			lastKey = key
			-- an account panel (the Store with its tab strip) must not stay up behind the result
			local gui = root.Parent
			local store = gui and gui:FindFirstChild("StoreBackdrop")
			if store and store:IsA("GuiObject") then store.Visible = false end
			-- pop in: the panel grows from 85 percent to its fitted scale
			local target = fit.Scale
			fit.Scale = target * 0.85
			TweenService:Create(fit, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
			if playSfx and SOUND_IDS then
				require(script.Parent.Cue).play(isWin and "win" or "lose", 1.2)
			end
		end
	end

	return {
		gameOverFrame = dim,
		playAgainButton = playAgainButton,
		continueButton = continueButton,
		tavernButton = tavernButton, -- wired in init.client.lua (needs the Menu frame)
		refreshGameOver = refreshGameOver,
	}
end
