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
local TextService = game:GetService("TextService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local GameOverTips = require(Engine:WaitForChild("GameOverTips"))
local RunOverLayout = require(Engine:WaitForChild("RunOverLayout"))
local SeedDisplay = require(Engine:WaitForChild("SeedDisplay"))
local ShareResult = require(Engine:WaitForChild("ShareResult"))
local EndlessRules = require(Engine:WaitForChild("EndlessRules"))
local WinCardRules = require(Engine:WaitForChild("WinCard"))
local Moments = require(Engine:WaitForChild("Gameplay2Moments"))
local ImageSpace = require(Engine:WaitForChild("ImageSpace"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local RunOverWin = require(Engine:WaitForChild("RunOverWin"))
local ClientSettings = require(script.Parent.ClientSettings)

local CREAM = Color3.fromRGB(250, 240, 220)
local GOLD_TEXT = Color3.fromRGB(255, 214, 130)
local SOFT = Color3.fromRGB(235, 222, 195)
local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local WOOD = Color3.fromRGB(46, 32, 20) -- the one wood plate colour: panel, facts plate, Patron plate and secondary buttons
local GREEN = Color3.fromRGB(60, 110, 70)
local BRASS = Color3.fromRGB(196, 150, 60)

local FACT_SIZE = 16 -- one body size; section titles are gold 18
local LINE_PAD = 6

-- text colours by tone: light on the dark wood panel, dark ink on the painted scroll's paper (4.5:1 or better on the paper)
local TONES = {
	plain = { text = CREAM, gold = GOLD_TEXT, soft = SOFT },
	scroll = { text = Color3.fromRGB(60, 40, 22), gold = Color3.fromRGB(110, 66, 16), soft = Color3.fromRGB(84, 58, 34) },
}

return function(deps)
	local root = deps.root
	local polishPanel, polishButton, addSoftShadow = deps.polishPanel, deps.polishButton, deps.addSoftShadow
	local playSfx, SOUND_IDS = deps.playSfx, deps.SOUND_IDS

	-- dim: the full-screen dark dim (hides the table so no cards peek out) and click sink; one Visible flag shows and hides all.
	local dim = Instance.new("ScrollingFrame") -- a short window (a phone on its side) scrolls the panel at a readable size instead of shrinking its text
	dim.Name = "GameOver"
	dim.ScrollBarThickness = 6
	dim.ScrollingDirection = Enum.ScrollingDirection.Y
	dim.CanvasSize = UDim2.fromOffset(0, 0)
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 8, 6)
	dim.BackgroundTransparency = 0.25 -- a dark scrim: the play screen behind is only a faint shape
	dim.BorderSizePixel = 0
	dim.Active = true
	dim.Visible = false
	dim.Parent = root
	-- the toast bar and its gold bracket border never draw over the Run Over screen
	local clearWash -- removes the defeat wash when the screen closes
	dim:GetPropertyChangedSignal("Visible"):Connect(function()
		if not dim.Visible and clearWash then clearWash(); clearWash = nil end
		if dim.Visible then -- the scrim takes a dark version of the equipped Card Set's colour (classic keeps its near black)
			local ink = nil
			pcall(function() ink = require(script.Parent.SetInk).get() end)
			dim.BackgroundColor3 = ink and ink.plate or Color3.fromRGB(10, 8, 6)
		end
		local bar = root:FindFirstChild("MessageBar")
		if dim.Visible and bar then bar.Visible = false end
	end)

	local panel = Instance.new("Frame")
	panel.Name = "RunOverPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(760, 460)
	panel.BackgroundColor3 = WOOD
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

	-- the painted scroll behind the content (run_over_scroll_a for a loss, _b for a win): shown when the window is roomy enough for the content at
	-- full size inside the scroll's measured text-safe rect (Engine/RunOverLayout.scroll), else the dark wood panel stays
	local scrollPicture = Instance.new("ImageLabel")
	scrollPicture.Name = "ScrollPicture"
	scrollPicture.BackgroundTransparency = 1
	scrollPicture.BorderSizePixel = 0
	scrollPicture.Active = false
	scrollPicture.ScaleType = Enum.ScaleType.Fit -- keeps the picture's own proportions, centred (the panel is sized to them)
	scrollPicture.ZIndex = 21
	scrollPicture.Visible = false
	scrollPicture.Parent = panel
	-- every named frame lives in Content, which is moved and scaled onto the safe rect of the scroll (or fills the plain panel)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Active = false
	content.ZIndex = 22
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = panel
	local contentScale = Instance.new("UIScale")
	contentScale.Parent = content
	local function frame(name, parent)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 22
		f.Parent = parent or content
		return f
	end
	local function place(f, r)
		f.Position = UDim2.fromOffset(math.floor(r.x + 0.5), math.floor(r.y + 0.5))
		f.Size = UDim2.fromOffset(math.floor(r.w + 0.5), math.floor(r.h + 0.5))
	end
	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Merriweather
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
		b.Font = Enum.Font.Merriweather
		b.TextSize = size or 16
		b.TextWrapped = false
		b.TextTruncate = Enum.TextTruncate.None
		b.TextColor3 = textColor or CREAM
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		b.BackgroundColor3 = color
		b.ZIndex = 24
		b.Parent = parent
		polishButton(b, 10)
		if color == GREEN then pcall(function() require(script.Parent.TavernKit).paintedButton(b, "primary") end)
		elseif color == WOOD then pcall(function() require(script.Parent.TavernKit).paintedButton(b, "secondary") end) end
		return b
	end

	-- ===== named frames =====
	local titleF = frame("Title")
	local iconLabel = label(titleF, { -- the trophy and candle glyphs are gone (they sat on the start of the title); kept as a hidden label
		Size = UDim2.fromOffset(1, 1), Text = "", Visible = false,
	})
	local titleLabel = label(titleF, {
		Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(0, 0), TextSize = 26, Text = "", TextYAlignment = Enum.TextYAlignment.Center,
	})
	local revivedBadge = label(titleF, {
		Name = "RevivedBadge", AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(110, 26), Position = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 120, 150), TextSize = 16, Text = "\u{1F4AB} Revived",
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Visible = false,
	})
	polishPanel(revivedBadge, 13)
	-- the win ribbon: a gold pill with the Night reached ("Tavern Champion" after a full clear), only on a win
	local winBanner = require(script.Parent.TavernKit).pill(titleF, "", "gold")
	winBanner.Name = "WinBanner"
	winBanner.Visible = false
	winBanner.ZIndex = 23
	winBanner.Size = UDim2.fromOffset(260, 30)
	local bannerWord = winBanner:FindFirstChild("Word")
	bannerWord.TextSize = 18
	bannerWord.ZIndex = 24
	bannerWord.TextStrokeTransparency = 1
	pcall(function() require(script.Parent.TavernKit).icon(bannerWord, "crown", 0.12) end) -- the medal, drawn from the existing icon set
	local factsPlate = frame("FactsPlate") -- solid dark wood behind the facts column, so no painted lantern or candle sits under the text
	factsPlate.BackgroundTransparency = 0.08
	factsPlate.BackgroundColor3 = WOOD
	do
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(0, 10)
		pc.Parent = factsPlate
		local ps = Instance.new("UIStroke")
		ps.Color = BRASS
		ps.Thickness = 1
		ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ps.Parent = factsPlate
	end
	pcall(function() require(script.Parent.TavernKit).painted(factsPlate, "wood_plate") end) -- thin painted wood border (10 to 14 px, inside PLATE_PAD), flat look if it does not load
	local factsF = frame("Facts")
	local patronsLabel = label(content, { Name = "PatronsLabel", Text = "Patrons used", TextSize = 18, TextColor3 = GOLD_TEXT })
	patronsLabel.TextTruncate = Enum.TextTruncate.AtEnd
	patronsLabel.TextYAlignment = Enum.TextYAlignment.Center
	do -- on the painted scroll the heading stands on its own dark plate, so gold never sits on the orange glow
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 8)
		hc.Parent = patronsLabel
		local hp = Instance.new("UIPadding")
		hp.PaddingLeft = UDim.new(0, 10)
		hp.PaddingRight = UDim.new(0, 10)
		hp.Parent = patronsLabel
	end
	local patronsF = frame("Patrons")
	patronsF.BackgroundTransparency = 0.15
	patronsF.BackgroundColor3 = WOOD
	local pk = Instance.new("UICorner")
	pk.CornerRadius = UDim.new(0, 10)
	pk.Parent = patronsF
	local noPatrons = label(patronsF, {
		Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), Text = "No Patrons this time.", TextSize = 16,
		Font = Enum.Font.Merriweather, TextYAlignment = Enum.TextYAlignment.Center, Visible = false,
	})
	local boonStrip = require(script.Parent.RunOverBoonStrip).new(content, 22) -- the Night boons taken (hidden when none)
	local actionsF = frame("Actions")
	local moreF = frame("More")
	-- one ink line on the paper under the content (the free sheet above the seal), only while the scroll is drawn
	local flavorLabel = label(panel, {
		Name = "Flavor", Text = "The house thanks you for the night.", TextSize = 18, Font = Enum.Font.Merriweather, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextColor3 = Color3.fromRGB(84, 58, 34), Visible = false,
	})

	local continueButton = button(actionsF, "ContinueButton", "One More Round", WOOD, GOLD_TEXT, 16)
	local playAgainButton = button(actionsF, "PlayAgain", "Play Again", GREEN, CREAM, 20)
	local tavernButton = button(actionsF, "BackToTavern", "Back to Tavern", WOOD, CREAM, 16)
	local shareButton = button(moreF, "ShareResult", "Share", WOOD, CREAM, 16)
	local challengeButton = button(moreF, "ChallengeFriend", "Challenge", WOOD, CREAM, 16)
	local inviteButton = button(moreF, "InviteFriends", "Invite", WOOD, CREAM, 16)
	local saveButton = button(moreF, "SaveBadge", "Save Badge", WOOD, CREAM, 16)
	local winCardButton = button(moreF, "WinCard", "Win Card", WOOD, CREAM, 16)
	winCardButton.Visible = false
	pcall(function() require(script.Parent.TavernScreens).apply(dim, "runover") end) -- Gameplay v2 look: closing time scene, one green primary
	require(script.Parent.InvitePrompt).bind(inviteButton)

	-- the share line: a selectable box over the first row of the More block (select it, then Ctrl+C)
	local shareBox = Instance.new("TextBox")
	shareBox.Name = "ShareSeedBox"
	shareBox.BackgroundColor3 = Color3.fromRGB(26, 17, 10)
	shareBox.BorderSizePixel = 0
	shareBox.Font = Enum.Font.Merriweather
	shareBox.TextSize = 16
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
	local shareHint = label(moreF, { Name = "ShareHint", Text = "Select the line, then press Ctrl+C.", TextSize = 16, Font = Enum.Font.Merriweather, Visible = false })

	local lastState, lastSummary
	local layoutNow -- set below; re-lays the panel out for the current screen size

	local function click()
		if deps.playClick then deps.playClick() end
	end
	local function showBox(text)
		shareBox.Text = text
		shareButton.Visible, challengeButton.Visible, inviteButton.Visible = false, false, false
		shareBox.Visible, shareHint.Visible = true, true
		local SF = require(Engine:WaitForChild("ShareFeedback"))
		local pressed = os.clock()
		shareHint.Text = SF.hint(pressed, pressed) -- "Line ready!" for 2 seconds, then the plain how to line (no tween, Calm mode safe)
		task.delay(SF.SECONDS, function()
			if shareHint.Parent then shareHint.Text = SF.hint(os.clock(), pressed) end
		end)
		shareBox:CaptureFocus()
	end
	shareButton.MouseButton1Click:Connect(function()
		click()
		local seedInfo = SeedDisplay.label(lastState)
		if lastState and lastState.isDaily then -- a Daily shares its seed name and twist, never a code to type
			local twist = type(lastState.dailyModifierInfo) == "table" and lastState.dailyModifierInfo.name or nil
			showBox(require(Engine:WaitForChild("DailyShare")).line(lastSummary, lastState.dailyDateKey, twist))
			return
		end
		local EndlessScreen = require(Engine:WaitForChild("EndlessScreen"))
		local view = EndlessScreen.lines(lastState, lastSummary and lastSummary.endlessBestByStake, lastSummary and lastSummary.stake or (lastState and lastState.stake))
		if view then
			showBox(EndlessScreen.shareLine(lastState.night, tonumber(view.best:match("(%d+)$")))) -- the Endless Night, not the plain Night line
		else
			showBox(ShareResult.line(lastSummary, seedInfo and seedInfo.kind == "seed" and seedInfo.value or nil))
		end
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
		do -- one line for this run: its biggest hand
			local okR, runLine = pcall(function() return require(Engine:WaitForChild("BestLine")).runLine(best and best.name, best and best.score) end)
			if okR and runLine then add(runLine, { TextSize = 16, tone = "gold" }) end
		end
		do
			local ST = require(Engine:WaitForChild("ScoreText"))
			add("Final score: " .. ST.short(state.roundScore) .. " / " .. ST.short(state.targetScore))
		end
		add(string.format("Tips banked: %d", math.floor(state.tips or 0)), { countTips = math.floor(state.tips or 0) })
		do -- best Night and best hand so far, from profile stats
			local okB, bestLine = pcall(function() return require(Engine:WaitForChild("BestLine")).recordLine(state.profileStats) end)
			if okB and bestLine and isWin and RunOverWin.isNewRecord(state) then add("New record! " .. bestLine, { tone = "gold", TextSize = 18 })
			elseif okB and bestLine then add(bestLine, { tone = "soft" }) end
		end
		if summary then
			add("Road taken", { TextSize = 18, tone = "gold" })
			local names = {}
			for _, stop in ipairs(summary.route or {}) do names[#names + 1] = stop.name or stop.id end
			add(#names > 0 and table.concat(names, "  >  ") or "No stops yet", { Font = Enum.Font.Merriweather, TextSize = 16, tone = "soft" })
			if summary.blessing then add("Blessing: " .. summary.blessing.name) end
			if summary.finalBoss then add("Final boss defeated: " .. summary.finalBoss.name, { tone = "gold" }) end
		end
		do -- what this run opened (Patrons, Recipes, House Passes), listed by name
			local okU, line = pcall(function()
				local names = require(script.Parent.UnlockToast).namesOf(state.unlockNotice and state.unlockNotice.items)
				return require(Engine:WaitForChild("ProgressionFeel")).unlockLine(names)
			end)
			local names = nil
			pcall(function() names = require(script.Parent.UnlockToast).namesOf(state.unlockNotice and state.unlockNotice.items) end)
			local pills = RunOverWin.unlockPills(names)
			if #pills > 0 then
				add("New unlocks", { tone = "gold", TextSize = 16 })
				add("", { pills = pills, fixedH = #pills * 34 + LINE_PAD })
			elseif okU and line then add(line, { tone = "gold" }) end
		end
		if state.nextUnlock and state.nextUnlock.label then add("Next unlock: " .. state.nextUnlock.label, { tone = "gold" }) end
		do -- one kind line about the next Starting Deck to open (nothing when every deck is open)
			local okD, deckLine = pcall(function() return require(Engine:WaitForChild("RunOverHint")).line(state.startingDecks) end)
			if okD and deckLine then add(deckLine, { TextSize = 16, tone = "soft" }) end
		end
		local seedInfo = SeedDisplay.label(state)
		if seedInfo then -- a Seed Run's code is tappable: the share box opens with the code selected, ready to copy
			add(seedInfo.text .. (seedInfo.shareable and "  (tap to copy)" or ""), { Font = Enum.Font.Merriweather, TextSize = 16, tone = "soft", copy = seedInfo.shareable and seedInfo.value or nil })
		end
		do -- Endless: this run's Night, the best Night and a kind share line (Engine/EndlessScreen)
			local okE, view = pcall(function() return require(Engine:WaitForChild("EndlessScreen")).lines(state, summary and summary.endlessBestByStake, summary and summary.stake or state.stake) end)
			if okE and view then
				add(view.headline .. (view.isBest and "  (new best)" or ""), { TextSize = 16, tone = "gold" })
				add(view.best, { Font = Enum.Font.Merriweather, TextSize = 16, tone = "soft" })
			end
		end
		if summary then
			local bestLines = EndlessRules.bestLines(summary.endlessBestByStake, summary.stake)
			if #bestLines > 0 then add("Best Endless Night   " .. table.concat(bestLines, "   |   "), { Font = Enum.Font.Merriweather, TextSize = 16, tone = "soft" }) end
		end
		local hint = (not isWin) and GameOverTips.forRun({
			patrons = type(state.ownedPatrons) == "table" and #state.ownedPatrons or nil,
			handsPlayed = state.handsPlayedTotal, discardsUsed = state.discardsUsedTotal,
			bestHandName = best and best.name or nil,
		}, state.night, state.round) or nil
		if hint then add("Tip: " .. hint, { Font = Enum.Font.Merriweather, TextSize = 16, tone = "soft" }) end
		return lines
	end

	local current = {} -- what the screen shows now: { state, summary, bestHand, isWin, lines }

	local mode = "plain" -- "plain" (dark wood panel) or "scroll" (painted paper): decides the text colours

	local function measureFacts(width)
		local y = RunOverLayout.TOP_PAD
		for _, line in ipairs(current.lines) do
			local size = line.props.TextSize or FACT_SIZE
			if line.props.fixedH then
				y = y + line.props.fixedH
			else
				y = y + RunOverLayout.estimateLines(line.text, RunOverLayout.factWidth(width), size) * (size + 3) + LINE_PAD
			end
		end
		return y
	end

	local function buildFacts(width)
		clearFacts()
		local y = RunOverLayout.TOP_PAD
		for i, line in ipairs(current.lines) do
			local size = line.props.TextSize or FACT_SIZE
			local n = RunOverLayout.estimateLines(line.text, RunOverLayout.factWidth(width), size)
			local h = n * (size + 3) + LINE_PAD
			if line.props.fixedH then
				h = line.props.fixedH
				for k, name in ipairs(line.props.pills) do -- one gold pill per new unlock
					local pill = require(script.Parent.TavernKit).pill(factsF, name, "gold")
					pill.Name = "UnlockPill" .. k
					pill.Position = UDim2.fromOffset(RunOverLayout.factInset(), y + (k - 1) * 34)
					pill.Size = UDim2.fromOffset(RunOverLayout.factWidth(width), 30)
					local word = pill:FindFirstChild("Word")
					word.TextSize = 16
					word.TextStrokeTransparency = 1
					word.ZIndex = 24
					pill.ZIndex = 23
				end
			else
			local factLabel = label(factsF, { -- inset so the words keep 12 px clear of the dark plate edge (TextFit.SIDE)
				Name = "Fact" .. i, Text = line.text, Position = UDim2.fromOffset(RunOverLayout.factInset(), y), Size = UDim2.fromOffset(RunOverLayout.factWidth(width), h),
				TextSize = size, Font = line.props.Font or Enum.Font.Merriweather, TextColor3 = TONES.plain[line.props.tone or "text"], -- always cream: the facts stand on a dark plate
			})
			if line.props.countTips and current.animate and ClientSettings.get("reduceShake") ~= true then -- Tips count up (the end state at once in Calm mode)
				pcall(function()
					require(script.Parent.CelebrationFX).countUp(factLabel, line.props.countTips, function(v) return string.format("Tips banked: %d", math.floor(v)) end)
				end)
			end
			if i > 1 and current.animate and ClientSettings.get("reduceShake") ~= true then -- the tally reads one line at a time (a static list in Calm mode)
				factLabel.TextTransparency = 1
				task.delay(0.18 * (i - 1), function()
					if factLabel.Parent then factLabel.TextTransparency = 0 end
				end)
			end
			if line.props.copy then
				local tap = Instance.new("TextButton")
				tap.Name = "CopySeed"
				tap.BackgroundTransparency = 1
				tap.Text = ""
				tap.Position = UDim2.fromOffset(0, y - math.max(0, 44 - h) // 2)
				tap.Size = UDim2.fromOffset(width, math.max(h, 44))
				tap.ZIndex = 20
				tap.Parent = factsF
				tap.MouseButton1Click:Connect(function() click() showBox(line.props.copy) end)
			end
			end
			y = y + h
		end
		return y
	end

	-- the text and plate colours for the current mode (ink on the scroll's paper, cream on the dark wood), and the panel's own chrome
	local chromeSaved = {}
	local function applyMode(newMode)
		mode = newMode
		local t = TONES[mode]
		titleLabel.TextColor3 = t.text
		patronsLabel.TextColor3 = mode == "scroll" and GOLD_TEXT or t.gold
		patronsLabel.BackgroundColor3 = WOOD
		patronsLabel.BackgroundTransparency = mode == "scroll" and 0.08 or 1
		boonStrip.setTone(t)
		noPatrons.TextColor3 = t.text
		shareHint.TextColor3 = t.text
		local onScroll = mode == "scroll"
		patronsF.BackgroundTransparency = onScroll and 0.88 or 0.15
		scrollPicture.Visible = onScroll
		panel:SetAttribute("OrnateOff", onScroll) -- VisualHelpers keeps InnerRim and the corner marks hidden on the painted scroll
		-- the dark wood panel's fill, stroke, gradient, sheen and shadow step aside while the paper is the panel
		for _, child in ipairs(panel:GetChildren()) do
			if child ~= content and child ~= scrollPicture and child ~= winArt and child ~= flavorLabel then
				if child:IsA("UIStroke") or child:IsA("UIGradient") then
					child.Enabled = not onScroll
				elseif child:IsA("GuiObject") then
					if onScroll and chromeSaved[child] == nil then chromeSaved[child] = child.Visible end
					if onScroll then
						child.Visible = false
					elseif chromeSaved[child] ~= nil then
						child.Visible = chromeSaved[child]
						chromeSaved[child] = nil
					end
				end
			end
		end
		panel.BackgroundTransparency = onScroll and 1 or 0
		local shadow = dim:FindFirstChild("Shadow")
		if shadow then shadow.Visible = not onScroll end
	end

	-- chrome that the skin adds to the panel AFTER the mode was applied (the code border with its gold corner brackets, plates, glosses) must not
	-- show over the scroll either: hide anything new while the scroll is the panel, and lift it above the play HUD with the rest
	local function isChrome(child)
		return child ~= content and child ~= scrollPicture and child ~= winArt and child ~= flavorLabel and child:IsA("GuiObject")
	end
	panel.ChildAdded:Connect(function(child)
		if mode == "scroll" and isChrome(child) then
			chromeSaved[child] = chromeSaved[child] == nil and child.Visible or chromeSaved[child]
			child.Visible = false
		end
	end)
	dim.DescendantAdded:Connect(function(d)
		task.defer(function()
			if d.Parent and d:IsA("GuiObject") and d:GetAttribute("RunOverBaseZ") == nil and dim.ZIndex >= RunOverLayout.Z_LIFT then
				d:SetAttribute("RunOverBaseZ", d.ZIndex)
				d.ZIndex = d.ZIndex + RunOverLayout.Z_LIFT
			end
		end)
	end)

	local function buildPatrons(r)
		clearPatrons()
		local summary = current.summary
		local list = summary and summary.patrons or {}
		noPatrons.Visible = #list == 0
		local PatronPlaque = require(script.Parent.PatronPlaque)
		for index, patron in ipairs(list) do
			if index > 10 then break end
			local col, rowN = (index - 1) % r.cols, math.floor((index - 1) / r.cols)
			local sw, shh = r.seatW or RunOverLayout.SEAT_W, r.seatH or RunOverLayout.SEAT_H
			local holder = Instance.new("Frame")
			holder.Name = "Patron" .. index
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			holder.Position = UDim2.fromOffset(8 + col * (sw + 8), 8 + rowN * (shh + 8))
			holder.Size = UDim2.fromOffset(sw, shh)
			holder.ZIndex = 23
			holder.Parent = patronsF
			-- a Patron with a cut Concept T card shows the whole card (its own rarity frame and name plate); one without keeps a small
			-- parchment card with the emoji and the name
			local seat = Instance.new("Frame")
			seat.Name = "Medallion"
			seat.Size = UDim2.fromScale(1, 1)
			seat.BackgroundColor3 = PARCHMENT
			seat.BorderSizePixel = 0
			seat.ZIndex = 24
			seat.Parent = holder
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = seat
			local ring = Instance.new("UIStroke")
			ring.Color = BRASS
			ring.Thickness = 2
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- never Contextual: it would stroke the text too
			ring.Parent = seat
			local emoji = label(seat, {
				Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 8), Text = patron.icon or "?", TextSize = 24, Font = Enum.Font.Merriweather, ZIndex = 25,
				TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = false, TextColor3 = INK,
			})
			local nameLabel = label(seat, {
				Text = patron.name or patron.id, Position = UDim2.fromOffset(2, 52), Size = UDim2.new(1, -4, 1, -54), TextSize = 16,
				Font = Enum.Font.Merriweather, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25, TextColor3 = INK,
			})
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			local art = PatronPlaque.apply(seat, patron.id, { zIndex = 26, cornerRadius = 8 })
			if art and art:GetAttribute("ConceptTCard") then
				seat.BackgroundTransparency = 1
				ring.Enabled = false
				emoji.Visible, nameLabel.Visible = false, false
			elseif art then
				emoji.Visible = false
			end
		end
	end

	-- lay everything out for the current screen size and content
	local function labelsOf(list)
		local out = {}
		for _, b in ipairs(list) do out[#out + 1] = b.Text end
		return out
	end
	-- the six reserved secondary cells: the real labels, then empty ones (free cells that hold the share hint)
	local function moreLabelsOf(list)
		local out = labelsOf(list)
		while #out < 6 do out[#out + 1] = "" end
		return out
	end
	layoutNow = function()
		if not current.state then return end
		local size = root.AbsoluteSize
		local sw, sh = size.X > 0 and size.X or 1280, size.Y > 0 and size.Y or 720
		local state = current.state
		local primaryList = {}
		local function textW(text)
			local ok, size = pcall(function() return TextService:GetTextSize(text, RunOverLayout.BTN_TEXT, Enum.Font.Merriweather, Vector2.new(1000, 100)) end)
			return ok and size and size.X or 0
		end
		local canContinue = state.continueOffer == "free" or state.continueOffer == "paid"
		continueButton.Visible = canContinue
		primaryList[#primaryList + 1] = playAgainButton -- the one big green primary
		if canContinue then primaryList[#primaryList + 1] = continueButton end
		primaryList[#primaryList + 1] = tavernButton
		local moreList = { shareButton, challengeButton, inviteButton, saveButton }
		local showWin = current.showWinCard
		winCardButton.Visible = showWin
		if showWin then moreList[#moreList + 1] = winCardButton end
		local patronN = math.min(10, current.summary and #current.summary.patrons or 0)
		local boonView = nil
		pcall(function() boonView = require(Engine:WaitForChild("RunOverBoons")).view(current.state and current.state.boonsTaken) end)
		local boonN = boonView and #boonView.chips or 0
		-- six secondary cells are always reserved: the free ones hold the share hint once a share line is showing
		-- the scroll first: it needs the content to fit its measured text-safe rect at (nearly) full size; otherwise the plain wood panel
		local scrollKey = current.isWin and "b" or "a"
		local artId = ContentArt.getImageId("shop_scene", "run_over_scroll_" .. scrollKey)
		local sc = nil
		if artId then
			sc = RunOverLayout.scroll(sw, sh, { factsH = measureFacts(RunOverLayout.LEFT_W), patrons = patronN, primary = #primaryList, more = 6, boons = boonN,
				bigPrimary = true, pills = true, cardSeats = true, textW = textW }, scrollKey)
		end
		local factsH
		local r
		flavorLabel.Visible = false
		if sc then
			applyMode("scroll")
			factsH = buildFacts(RunOverLayout.LEFT_W)
			r = sc.inner
			panel.Size = UDim2.fromOffset(sc.card.w, sc.card.h)
			fit.Scale = 1
			content.Position = UDim2.fromOffset(sc.origin.x, sc.origin.y)
			content.Size = UDim2.fromOffset(r.panel.w, r.panel.h)
			contentScale.Scale = sc.fit
			local art = RunOverLayout.SCROLLS[scrollKey].art
			local ix, iy, iw, ih = ImageSpace.rect(art.x, art.y, art.w, art.h, 1536, 1024)
			scrollPicture.Image = artId
			scrollPicture.ImageRectOffset = Vector2.new(ix, iy)
			scrollPicture.ImageRectSize = Vector2.new(iw, ih)
			scrollPicture.Position = UDim2.fromOffset(0, 0)
			scrollPicture.Size = UDim2.fromOffset(sc.card.w, sc.card.h)
				if sc.flavor then
					flavorLabel.Text = current.isWin and "The house will remember tonight." or ((current.state and current.state.targetScore) and Moments.defeatLine(current.state) or "The house thanks you for the night.")
					flavorLabel.Position = UDim2.fromOffset(math.floor(sc.flavor.x + 0.5), math.floor(sc.flavor.y + 0.5))
					flavorLabel.Size = UDim2.fromOffset(math.floor(sc.flavor.w + 0.5), math.floor(sc.flavor.h + 0.5))
					flavorLabel.Visible = true
				end
		else
			applyMode("plain")
			local cols = RunOverLayout.columns(sw)
			factsH = buildFacts(cols.leftW)
			local spec = { factsH = factsH, patrons = patronN, primary = #primaryList, more = 6, boons = boonN,
				bigPrimary = true, pills = true, cardSeats = true, textW = textW }
			r = RunOverLayout.computeTouch(sw, sh, spec)
			local scrolls = false
			if r.scale < RunOverLayout.MIN_READ_SCALE then -- too short to shrink: keep the text readable and let the player scroll
				local tall = RunOverLayout.computeTouch(sw, 100000, spec)
				if tall.scale >= RunOverLayout.MIN_READ_SCALE then r, scrolls = tall, true end
			end
			panel.Size = UDim2.fromOffset(r.panel.w, r.panel.h)
			fit.Scale = r.scale
			panel.AnchorPoint = Vector2.new(0.5, scrolls and 0 or 0.5)
			panel.Position = scrolls and UDim2.new(0.5, 0, 0, 8) or UDim2.fromScale(0.5, 0.5)
			dim.CanvasSize = UDim2.fromOffset(0, scrolls and math.ceil(r.panel.h * r.scale) + 16 or 0)
			dim.ScrollingEnabled = scrolls
			dim.ScrollBarImageTransparency = scrolls and 0.3 or 1
			content.Position = UDim2.fromOffset(0, 0)
			content.Size = UDim2.fromOffset(r.panel.w, r.panel.h)
			contentScale.Scale = 1
		end
		place(titleF, r.title)
		do -- a win: the gold ribbon on top (the Night reached), the line under it; a loss keeps the one title line
			local win = current.isWin == true
			winBanner.Visible = win
			if win then
				bannerWord.Text =RunOverWin.headline(current.state) or "You won"
				winBanner.Size = UDim2.fromOffset(math.min(300, math.max(180, r.title.w - 130)), 30)
				winBanner.Position = UDim2.fromOffset(0, 0)
				titleLabel.TextSize = 22
				titleLabel.Position = UDim2.fromOffset(0, 32)
				titleLabel.Size = UDim2.new(1, -150, 0, math.max(24, r.title.h - 32))
			else
				titleLabel.TextSize = 26
				titleLabel.Position = UDim2.fromOffset(0, 0)
				titleLabel.Size = UDim2.new(1, -150, 1, 0)
			end
		end
		place(factsF, r.facts)
		do -- the dark plate stands PLATE_PAD past the text on every side, only on the painted scroll (the plain panel is already dark)
			local pad = RunOverLayout.PLATE_PAD
			place(factsPlate, { x = r.facts.x - pad, y = r.facts.y - pad, w = r.facts.w + 2 * pad, h = r.facts.h + 2 * pad })
			factsPlate.Visible = mode == "scroll"
		end
		place(patronsLabel, r.patronsLabel)
		place(patronsF, r.patrons)
		local ax, ay = r.primary[1].x, r.primary[1].y
		local actionsW = 0
		for _, c in ipairs(r.primary) do actionsW = math.max(actionsW, c.x + c.w - ax) end
		local actionsBottom = ay
		for _, c in ipairs(r.primary) do actionsBottom = math.max(actionsBottom, c.y + c.h) end
		place(actionsF, { x = ax, y = ay, w = actionsW, h = actionsBottom - ay })
		for i, b in ipairs(primaryList) do
			local c = r.primary[i]
			b.Position = UDim2.fromOffset(math.floor(c.x - ax + 0.5), math.floor(c.y - ay + 0.5))
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
		-- every button is dressed again at its real size: the painted plate is nine-sliced (SliceCenter) for that size, so ornaments never stretch
		for _, b in ipairs(primaryList) do
			pcall(function() require(script.Parent.TavernKit).paintedButton(b, b == playAgainButton and "primary" or "secondary") end)
		end
		for _, b in ipairs(moreList) do
			pcall(function() require(script.Parent.TavernKit).paintedButton(b, "secondary") end)
		end
		-- the equipped Card Set's own plates on every Run Over button (primary green for Play Again, dark for the rest); classic keeps the painted kit plates
		for _, b in ipairs(primaryList) do
			pcall(function() require(script.Parent.TavernKit).setPlateButton(b, b == playAgainButton and "primary" or "secondary") end)
		end
		for _, b in ipairs(moreList) do
			pcall(function() require(script.Parent.TavernKit).setPlateButton(b, "secondary") end)
		end
		-- the share box covers the first row of three; the hint takes the free cells after the last button
		local row1 = { r.more[1], r.more[math.max(1, math.min(#r.more, r.morePerRow or (r.columns.mode == "wide" and 3 or 2)))] }
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
		boonStrip.show(boonView, r)
		current.rects = r
		-- ZIndex is absolute under Global: lift the whole screen above the play HUD (hand, plates, deck, corner icons) so none of it
		-- draws over the scroll; the original value is kept in an attribute so a re-layout never lifts twice
		for _, d in ipairs(dim:GetDescendants()) do
			if d:IsA("GuiObject") then
				local base = d:GetAttribute("RunOverBaseZ")
				if base == nil then base = d.ZIndex; d:SetAttribute("RunOverBaseZ", base) end
				d.ZIndex = base + RunOverLayout.Z_LIFT
			end
		end
		dim.ZIndex = 1 + RunOverLayout.Z_LIFT
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
		continueButton.Text = state.continueOffer == "free" and "One More (Free)" or "One More Round"
		playAgainButton.Text = isWin and "Play Again" or "Try Again" -- a calm retry after a loss
		pcall(function() require(script.Parent.TavernScreens).skin(dim, "runover") end)
		if isWin then
			titleLabel.Text = "Last call, but what a night! You beat the tavern!"
		else
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
		saveButton.Text = saved and "Badge saved" or "Save Badge"
		saveButton.BackgroundColor3 = (saved or summary == nil) and Color3.fromRGB(120, 110, 95) or WOOD
		shareButton.Active, challengeButton.Active = summary ~= nil, summary ~= nil

		local key = string.format("%s-%s-%s-%s-%s", tostring(state.night), tostring(state.round), tostring(isWin), tostring(isRevived), summary and "s" or "n")
		local fresh = key ~= lastKey
		current.animate = fresh -- the rows reveal one after another and Tips count up only the first time a result shows
		if fresh then
			shareBox.Visible, shareHint.Visible = false, false
			shareButton.Visible, challengeButton.Visible, inviteButton.Visible = true, true, true
		end
		local ok, err = pcall(layoutNow)
		current.animate = false
		if not ok then warn("[RunOver] layout failed: " .. tostring(err)) end
		if fresh then
			lastKey = key
			-- an account panel (the Store with its tab strip) must not stay up behind the result
			local gui = root.Parent
			local store = gui and gui:FindFirstChild("StoreBackdrop")
			if store and store:IsA("GuiObject") then store.Visible = false end
			-- pop in: the panel grows from 85 percent to its fitted scale
			local target = fit.Scale
			if mode == "scroll" then
				-- the scroll unrolls: a 0.3 s fade and settle (none in Reduce motion)
				if ClientSettings.get("reduceShake") ~= true then
					fit.Scale = 0.94
					scrollPicture.ImageTransparency = 1
					TweenService:Create(fit, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
					TweenService:Create(scrollPicture, TweenInfo.new(0.3), { ImageTransparency = 0 }):Play()
				else
					scrollPicture.ImageTransparency = 0
				end
			elseif ClientSettings.get("reduceShake") ~= true then -- Calm mode: the panel simply appears at its fitted scale
				fit.Scale = target * 0.85
				TweenService:Create(fit, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
			end
			if playSfx and SOUND_IDS then
				require(script.Parent.Cue).play(isWin and "win" or "defeat", 1.2)
				if isWin then pcall(function() require(script.Parent.Cue).play("jingle_run", 1) end) end -- Triumphant Fanfare, once per Victory screen
			end
			pcall(function() -- win: suit confetti and a springy title; loss: a gentle grey wash, no shake (all none in Calm mode)
				local fx = require(script.Parent.CelebrationFX)
				if clearWash then clearWash(); clearWash = nil end
				if isWin then
					fx.titleIn(titleLabel)
					require(script.Parent.ConfettiFX).burst(root.Parent, RunOverWin.confettiBig(state), RunOverLayout.Z_LIFT + 80) -- bigger after a full clear; nothing in Calm mode
				else
					clearWash = fx.defeatWash(dim)
				end
			end)
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
