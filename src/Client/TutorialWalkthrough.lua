--[[
	Client/TutorialWalkthrough.lua
	The first-run tutorial: a guided, mandatory sequence. Every step has ONE action and dims the whole screen
	except the one thing to click, with a one-line ribbon and an arrow beside it. The steps are DATA in
	Engine/TutorialSteps (menu Play, Select, then scripted hands: a pair, two pair, a flush and a straight
	flush, then Next Round); the server deals those hands to a brand-new player's first run
	(Engine/TutorialScript, state.tutorialStage). Wrong clicks do nothing but wiggle the target.

	  * The dim frames are Active, so they really block every click outside the cutout.
	  * It works from the screen the player is on: started on the main menu at first launch; if the player is
	    somewhere else it catches up to the matching step, and if the target is not on screen it points back
	    at the menu's Play button instead of describing it.
	  * Skip tutorial is a small button at the top right (away from the text) and needs a 1.5s hold to confirm
	    (the same popup as Restart Run).
	  * This module owns no game state: it listens to Client/TutorialBus (menu_play, select_round) and to the
	    notify*() calls the hub already makes (selection changed, hand played, discard, shop, Next Round).

	deps: root, tweenTo, polishPanel, playClickSfx, addButtonHoverScale, MarkTutorialSeenRemote,
	      handFrame, playButton, discardButton, nextRoundButton, sidebarScoreBox, sidebarTipsBox,
	      sidebarHandsDiscardsBox, shopBuyListFrame

	Returns { start, replay, onRender(state), notifySelectionChanged(n, weak, selectedSet), notifyHandPlayed,
	          notifyDiscardUsed, notifyEnteredShop, notifyNextRoundClicked }
]]

local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Steps = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TutorialSteps"))
local TutorialBus = require(script.Parent.TutorialBus)
local TutorialStart = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TutorialStart"))

local PAD = 10
local DIM = 0.5
local Z = Layers.effect + 10

return function(deps)
	local root = deps.root
	local playClickSfx = deps.playClickSfx
	local MarkTutorialSeenRemote = deps.MarkTutorialSeenRemote
	local screenGui = root:FindFirstAncestorOfClass("ScreenGui") or root
	-- All chrome lives in one full-size overlay and every rect is converted by THIS frame's own AbsolutePosition,
	-- so the GuiInset (top bar) and any parent offset cancel out.
	local gui = Instance.new("Frame")
	gui.Name = "TutorialOverlay"
	gui.BackgroundTransparency = 1
	gui.BorderSizePixel = 0
	gui.Active = false
	gui.Size = UDim2.fromScale(1, 1)
	gui.ZIndex = Z - 1
	gui.Parent = screenGui

	-- targets owned by the hub; the others come from TutorialBus (registered by Menu / RoundSelect)
	TutorialBus.register("play", deps.playButton)
	TutorialBus.register("nextRound", deps.nextRoundButton)
	TutorialBus.register("sidebarScore", deps.sidebarScoreBox)
	TutorialBus.register("sidebarTips", deps.sidebarTipsBox)
	TutorialBus.register("sidebarHands", deps.sidebarHandsDiscardsBox)
	TutorialBus.register("sidebarPatrons", deps.sidebarPatronsBox)

	local machine = Steps.new()
	local active, completed = false, false
	local lastState = nil
	local scripted = false
	local lastSelected = {}

	-- ===== chrome: four dim frames, a pulsing border, the ribbon with an arrow, the Skip button =====
	local function dimFrame(name)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = DIM
		f.BorderSizePixel = 0
		f.Active = true -- blocks clicks outside the cutout
		f.ZIndex = Z
		f.Visible = false
		f.Parent = gui
		return f
	end
	local dims = { dimFrame("TutorialDimTop"), dimFrame("TutorialDimBottom"), dimFrame("TutorialDimLeft"), dimFrame("TutorialDimRight") }

	local highlight = Instance.new("Frame")
	highlight.Name = "TutorialHighlight"
	highlight.BackgroundTransparency = 1
	highlight.BorderSizePixel = 0
	highlight.Active = false
	highlight.ZIndex = Z + 1
	highlight.Visible = false
	highlight.Parent = gui
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 12)
	hCorner.Parent = highlight
	local hStroke = Instance.new("UIStroke")
	hStroke.Thickness = 3
	hStroke.Color = Color3.fromRGB(255, 214, 130)
	hStroke.Transparency = 0.1
	hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hStroke.Parent = highlight
	local pulse = TweenService:Create(hStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })

	-- the ribbon: a wood plaque with ONE short line and an arrow pointing at the target
	local ribbon = Instance.new("Frame")
	ribbon.Name = "TutorialRibbon"
	ribbon.Size = UDim2.fromOffset(380, 56)
	ribbon.BackgroundColor3 = Color3.fromRGB(70, 48, 30)
	ribbon.BorderSizePixel = 0
	ribbon.Active = true
	ribbon.ZIndex = Z + 2
	ribbon.Visible = false
	ribbon.Parent = gui
	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 10)
	rCorner.Parent = ribbon
	local rStroke = Instance.new("UIStroke")
	rStroke.Color = Color3.fromRGB(222, 182, 104)
	rStroke.Thickness = 2
	rStroke.Parent = ribbon
	local ribbonText = Instance.new("TextLabel")
	ribbonText.Size = UDim2.new(1, -24, 1, -8)
	ribbonText.Position = UDim2.fromOffset(12, 4)
	ribbonText.BackgroundTransparency = 1
	ribbonText.Font = Enum.Font.GothamBold
	ribbonText.TextSize = 20
	ribbonText.TextColor3 = Color3.fromRGB(250, 235, 200)
	ribbonText.TextWrapped = true
	ribbonText.Text = ""
	ribbonText.ZIndex = Z + 3
	ribbonText.Parent = ribbon
	-- the equipped Card Set plate and ink at 7:1 (classic keeps the wood look)
	require(script.Parent.HintSkin).bind(ribbon, rStroke, { ribbonText }, { plate = Color3.fromRGB(70, 48, 30), edge = Color3.fromRGB(222, 182, 104), ink = Color3.fromRGB(250, 235, 200) })
	local arrow = Instance.new("TextLabel")
	arrow.Name = "TutorialArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(40, 40)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextSize = 34
	arrow.TextColor3 = Color3.fromRGB(255, 214, 130)
	arrow.TextStrokeTransparency = 0.3
	arrow.Text = "v"
	arrow.ZIndex = Z + 3
	arrow.Visible = false
	arrow.Parent = gui
	local okButton = Instance.new("TextButton")
	okButton.Name = "TutorialOk"
	okButton.AnchorPoint = Vector2.new(0.5, 0)
	okButton.Size = UDim2.fromOffset(140, 44)
	okButton.BackgroundColor3 = Color3.fromRGB(86, 140, 80)
	okButton.Font = Enum.Font.GothamBold
	okButton.TextSize = 18
	okButton.TextColor3 = Color3.fromRGB(250, 235, 200)
	okButton.Text = "Nice!"
	okButton.ZIndex = Z + 3
	okButton.Visible = false
	okButton.Parent = gui

	-- "tap" steps: a clear Active button exactly over the spotlight hole. Tapping the highlighted piece is the action.
	local tapButton = Instance.new("TextButton")
	tapButton.Name = "TutorialTap"
	tapButton.BackgroundTransparency = 1
	tapButton.Text = ""
	tapButton.AutoButtonColor = false
	tapButton.ZIndex = Z + 2
	tapButton.Visible = false
	tapButton.Parent = gui

	-- Skip: small, top right, away from the text; needs a hold to confirm
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "TutorialSkip"
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, -24, 0, 84)
	skipButton.Size = UDim2.fromOffset(TutorialStart.skipLayout(1280, 720).width, 44)
	-- ghost button in the tavern style: mostly see-through dark wood, brass border, cream text
	skipButton.BackgroundColor3 = Color3.fromRGB(52, 36, 22)
	skipButton.BackgroundTransparency = 0.35
	skipButton.AutoButtonColor = false
	skipButton.Font = Enum.Font.GothamBold
	skipButton.TextSize = 16
	skipButton.TextColor3 = Color3.fromRGB(250, 235, 200)
	skipButton.TextTransparency = 0
	skipButton.TextStrokeTransparency = 0.6
	skipButton.Text = TutorialStart.SKIP_TEXT
	skipButton.ZIndex = Z + 4
	skipButton.Visible = false
	skipButton.Parent = gui
	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 8)
	sCorner.Parent = skipButton
	local sStroke = Instance.new("UIStroke")
	sStroke.Color = Color3.fromRGB(214, 172, 88)
	sStroke.Thickness = 2
	sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sStroke.Parent = skipButton
	local sScale = Instance.new("UIScale")
	sScale.Parent = skipButton
	skipButton.MouseEnter:Connect(function() skipButton.BackgroundTransparency = 0.15 end)
	skipButton.MouseLeave:Connect(function() skipButton.BackgroundTransparency = 0.35 end)
	-- safe placement: inside the screen edge, below the corner icons and the Tips chip, smaller on small screens
	local function placeSkip()
		local size = gui.AbsoluteSize
		local L = TutorialStart.skipLayout(size.X, size.Y)
		skipButton.Position = UDim2.new(1, -L.right, 0, L.top)
		sScale.Scale = L.scale
	end
	placeSkip()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeSkip)

	-- ===== targets and positions =====
	local currentList = nil -- { Instance, ... } being spotlighted
	local currentStep = nil -- the step whose target is re-resolved every frame (the UI is rebuilt under us)
	local warned = {} -- step id -> true, so a missing target warns once
	local conn = nil

	local function visible(inst)
		local obj = inst
		while obj and not obj:IsA("LayerCollector") do
			if obj:IsA("GuiObject") and not obj.Visible then return false end
			obj = obj.Parent
		end
		if inst == nil or inst.Parent == nil or not inst:IsDescendantOf(screenGui) then return false end
		-- a destroyed/rebuilt or zero-size element has no usable rect
		if inst:IsA("GuiObject") and (inst.AbsoluteSize.X <= 0 or inst.AbsoluteSize.Y <= 0) then return false end
		-- a piece that has slid off the screen (the left board at the Counter) is not there to point at: the spotlight
		-- used to be clamped to the screen edge and lit an empty patch of wall
		if inst:IsA("GuiObject") then
			local p, s, g, gs = inst.AbsolutePosition, inst.AbsoluteSize, gui.AbsolutePosition, gui.AbsoluteSize
			if p.X + s.X <= g.X or p.Y + s.Y <= g.Y or p.X >= g.X + gs.X or p.Y >= g.Y + gs.Y then return false end
		end
		return true
	end

	local function handSlots(count)
		local slots = {}
		for _, child in ipairs(deps.handFrame:GetChildren()) do
			if child:IsA("Frame") then slots[#slots + 1] = child end
		end
		-- slots are tagged with the hand index they show (init.client), so the scripted target cards are found
		-- by tag, not by their position on screen (the hand may be sorted)
		if count then
			local picked = {}
			for _, slot in ipairs(slots) do
				local idx = slot:GetAttribute("HandIndex")
				if idx and idx <= count then picked[#picked + 1] = slot end
			end
			return picked
		end
		return slots
	end

	-- The player is looking at something else (Engine/TutorialSteps.stepsAside): one of the game's own screens is open
	-- over the step, or the hand that was just played is still being scored. The tutorial draws nothing until that is over.
	local scoreReveal = nil
	local playReveal = nil -- Client/PlayReveal, required on first use (false when it cannot be loaded)
	local function aside()
		local names = {}
		for _, parent in ipairs({ screenGui, root }) do
			for _, c in ipairs(parent:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible then names[#names + 1] = c.Name end
			end
		end
		if not (scoreReveal and scoreReveal.Parent) then scoreReveal = screenGui:FindFirstChild("ScorePopup", true) end
		local scoring = scoreReveal ~= nil and scoreReveal.Visible
		if not scoring then
			-- Play Hand was pressed and the server's report is on its way: the reveal starts in a moment (Client/PlayReveal
			-- holds it for that round trip). Without this the next step was drawn for a frame or two and taken away again.
			if playReveal == nil then
				local ok, module = pcall(require, script.Parent.PlayReveal)
				playReveal = ok and module or false
			end
			scoring = playReveal ~= false and playReveal.waiting() == true
		end
		return Steps.stepsAside(names, scoring)
	end

	-- Resolve the list of instances to cut a hole around, plus the text to show (it can differ when the player
	-- is on another screen: then it points back at the menu's Play button).
	local function resolveTarget(step)
		if aside() then return nil, step.text end -- (nothing is pointed at while the tutorial stands aside)
		local menuPlay = TutorialBus.resolve("menuPlay")
		if step.target == "menuPlay" then
			return menuPlay and visible(menuPlay) and { menuPlay } or nil, step.text
		end
		if step.target == "handCards" then
			local slots = handSlots(scripted and step.count or nil)
			local onScreen = false
			if visible(deps.handFrame) then
				local p, s, g, gs = deps.handFrame.AbsolutePosition, deps.handFrame.AbsoluteSize, gui.AbsolutePosition, gui.AbsoluteSize
				onScreen = p.X < g.X + gs.X and p.X + s.X > g.X and p.Y < g.Y + gs.Y and p.Y + s.Y > g.Y
			end
			local names = {}
			for _, parent in ipairs({ screenGui, root }) do
				for _, c in ipairs(parent:GetChildren()) do
					if c:IsA("GuiObject") and c.Visible then names[#names + 1] = c.Name end
				end
			end
			local overlay = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("BannerVisibility")).isScreenOpen(names)
			if #slots > 0 and Steps.handShowable(lastState and lastState.phase, true, onScreen, overlay) then
				return slots, Steps.captionFor(step) -- the caption is always this step's own line
			end
		elseif step.target then
			local inst = TutorialBus.resolve(step.target)
			if typeof(inst) == "table" then
				-- a getter may return a LIST (the union of the named elements, e.g. every Patron card on the shelf)
				local list = {}
				for _, one in ipairs(inst) do if visible(one) then list[#list + 1] = one end end
				if #list > 0 then return list, step.text end
			elseif inst and visible(inst) then return { inst }, step.text end
		end
		-- not on this screen: point back at the menu's Play button when the menu is up
		if menuPlay and visible(menuPlay) then
			return { menuPlay }, "Press Play to get back to the table."
		end
		return nil, step.text
	end

	local function rectOf(list)
		local gp = gui.AbsolutePosition
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, inst in ipairs(list) do
			local p, s = inst.AbsolutePosition, inst.AbsoluteSize
			minX, minY = math.min(minX, p.X), math.min(minY, p.Y)
			maxX, maxY = math.max(maxX, p.X + s.X), math.max(maxY, p.Y + s.Y)
		end
		return minX - gp.X - PAD, minY - gp.Y - PAD, (maxX - minX) + PAD * 2, (maxY - minY) + PAD * 2
	end

	-- No spotlight (target missing or not on screen yet): keep ONE full-screen sink so nothing underneath can
	-- be clicked, without drawing a wrong highlight.
	-- clear: the sink still takes every click but the screen is not darkened (the step's own screen is not up yet).
	local function setChromeHidden(clear)
		tapButton.Visible = false
		for _, f in ipairs(dims) do f.Visible = false end
		dims[1].Position, dims[1].Size = UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1)
		dims[1].BackgroundTransparency = clear and 1 or DIM
		dims[1].Visible = true
		highlight.Visible = false
		arrow.Visible = false
	end

	-- A step that wants an action and whose target never turns up: the dim comes off and the line sits at the top of the
	-- screen. The game can be played and the step still ends when its action is done (Engine/TutorialSteps.whenMissing).
	local function setChromeFree(text)
		tapButton.Visible = false
		for _, f in ipairs(dims) do f.Visible = false end
		highlight.Visible = false
		arrow.Visible = false
		ribbonText.Text = text
		ribbon.Position = UDim2.fromOffset(math.floor(gui.AbsoluteSize.X / 2 - ribbon.AbsoluteSize.X / 2), 96)
		ribbon.Visible = true
	end

	-- Stepped aside: nothing of the tutorial is drawn over what the player is looking at (the Skip button stays).
	local function setChromeAside()
		tapButton.Visible = false
		for _, f in ipairs(dims) do f.Visible = false end
		highlight.Visible = false
		arrow.Visible = false
		ribbon.Visible = false
	end

	local show -- (layout goes back to it when the target goes away)

	local function layout()
		if not currentList then return end
		if currentStep then
			-- re-find the live target every frame: hand cards and the Select button are rebuilt on every render
			local list, text = resolveTarget(currentStep)
			if not list or #list == 0 then
				ribbon.Visible = false -- no target: no caption plate either
				show() -- the target went away: wait for it again (show gives up after a moment, so this is never a dead end)
				return
			end
			currentList = list
			ribbonText.Text = text or Steps.captionFor(currentStep)
			ribbon.Visible = true
			dims[1].BackgroundTransparency = DIM
			dims[1].Visible = true
			highlight.Visible = true
			arrow.Visible = true
		end
		local ok = pcall(function()
			local size = gui.AbsoluteSize
			local x, y, w, h = rectOf(currentList)
			x = math.clamp(x, 0, size.X); y = math.clamp(y, 0, size.Y)
			w = math.clamp(w, 0, size.X - x); h = math.clamp(h, 0, size.Y - y)
			dims[1].Position, dims[1].Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(size.X, y)
			dims[2].Position, dims[2].Size = UDim2.fromOffset(0, y + h), UDim2.fromOffset(size.X, math.max(0, size.Y - y - h))
			dims[3].Position, dims[3].Size = UDim2.fromOffset(0, y), UDim2.fromOffset(x, h)
			dims[4].Position, dims[4].Size = UDim2.fromOffset(x + w, y), UDim2.fromOffset(math.max(0, size.X - x - w), h)
			highlight.Position, highlight.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
			tapButton.Position, tapButton.Size = highlight.Position, highlight.Size
			tapButton.Visible = currentStep ~= nil and currentStep.action == "tap"
			-- ribbon below the cutout (above when there is no room), centred on it, kept on screen; the arrow
			-- sits between the ribbon and the target, pointing at it
				local rw, rh = ribbon.AbsoluteSize.X, 56
				local avoid, gp0 = {}, gui.AbsolutePosition
				for _, b in ipairs({ deps.playButton, deps.discardButton }) do
					if typeof(b) == "Instance" and b:IsA("GuiObject") and b.Visible and b ~= currentList[1] then
						avoid[#avoid + 1] = { x = b.AbsolutePosition.X - gp0.X, y = b.AbsolutePosition.Y - gp0.Y, w = b.AbsoluteSize.X, h = b.AbsoluteSize.Y }
					end
				end
				local place = Steps.captionPlace({ x = x, y = y, w = w, h = h }, { w = size.X, h = size.Y }, rw, rh, avoid)
				ribbon.Position = UDim2.fromOffset(place.x, place.y)
				arrow.Position = UDim2.fromOffset(place.arrowX, place.arrowY)
				arrow.Text = place.arrow
			-- The caption and its arrow never sit on the Skip button (Engine/TutorialSteps.clearOfSkip). The Tips plate at
			-- the Counter is right above that button: the caption under it was half covered, and the arrow stood on it.
			if skipButton.Visible then
				local gp, sp, ss = gui.AbsolutePosition, skipButton.AbsolutePosition, skipButton.AbsoluteSize
				local plan = Steps.clearOfSkip(
					{ x = ribbon.Position.X.Offset, y = ribbon.Position.Y.Offset, w = rw, h = rh },
					{ x = arrow.Position.X.Offset, y = arrow.Position.Y.Offset },
					{ x = sp.X - gp.X, y = sp.Y - gp.Y, w = ss.X, h = ss.Y }, { x = x, w = w }, size.X)
				ribbon.Position = UDim2.fromOffset(plan.ribbonX, ribbon.Position.Y.Offset)
				if plan.arrowX then
					arrow.Position = UDim2.fromOffset(plan.arrowX, arrow.Position.Y.Offset)
				else
					arrow.Visible = false
				end
			end
			-- The game's own tooltip (what the hovered card does) stays readable: the caption steps clear of it and the
			-- arrow rests while it would cross it (Engine/TutorialSteps.captionClearOf). Picking from a Pack, the caption
			-- used to sit on the last line of the card's description.
			local tip = screenGui:FindFirstChild("Tooltip")
			if tip and tip:IsA("GuiObject") and tip.Visible and tip.AbsoluteSize.Y > 0 then
				local gp = gui.AbsolutePosition
				local t = { x = tip.AbsolutePosition.X - gp.X, y = tip.AbsolutePosition.Y - gp.Y, w = tip.AbsoluteSize.X, h = tip.AbsoluteSize.Y }
				local rx, ry = ribbon.Position.X.Offset, ribbon.Position.Y.Offset
				local newY, moved = Steps.captionClearOf({ x = rx, y = ry, w = rw, h = rh }, t, size.Y)
				if moved then ribbon.Position = UDim2.fromOffset(rx, newY) end
				local ax, ay = arrow.Position.X.Offset, arrow.Position.Y.Offset
				if moved or Steps.meets({ x = ax - 20, y = ay - 20, w = 40, h = 40 }, t) then arrow.Visible = false end
			end
		end)
		return ok
	end

	local function setChrome(on)
		if on then dims[1].BackgroundTransparency = DIM end
		for _, f in ipairs(dims) do f.Visible = on end
		highlight.Visible = on
		arrow.Visible = on
		-- the looping glow stays still in Calm / Reduce Motion / Reduce Flashing
		if on and not require(script.Parent.ClientSettings).get("reduceShake") then pulse:Play() else pulse:Pause() end
	end

	local function stopFollowing()
		if conn then conn:Disconnect() conn = nil end
	end

	local function hideAll()
		tapButton.Visible = false
		stopFollowing()
		setChrome(false)
		ribbon.Visible = false
		okButton.Visible = false
		skipButton.Visible = false
		currentList = nil
		currentStep = nil
	end

	local function dismissNewRibbon()
		local ribbon = TutorialBus.resolve("tutorialNew")
		if ribbon then ribbon:SetAttribute("Dismiss", true) end
	end

	local complete
	local report

	function show()
		local step = machine:current()
		if not active or not step then
			hideAll()
			return
		end
		skipButton.Visible = true
		if step.action == "ok" then
			-- the last step: a dimmed screen, the line and one button
			stopFollowing()
			currentList = nil
			currentStep = nil
			for _, f in ipairs(dims) do f.Position, f.Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0) end
			dims[1].BackgroundTransparency = DIM
			dims[1].Visible = true
			for i = 2, 4 do dims[i].Visible = false end
			highlight.Visible = false
			arrow.Visible = false
			ribbonText.Text = step.text
			-- the final card is a bigger celebration card
			local big = step.celebrate == true
			ribbon.Size = big and UDim2.fromOffset(520, 90) or UDim2.fromOffset(380, 56)
			ribbonText.TextSize = big and 28 or 20
			ribbon.Visible = true
			local size = gui.AbsoluteSize
			local halfW = big and 260 or 190
			ribbon.Position = UDim2.fromOffset(size.X / 2 - halfW, size.Y / 2 - (big and 80 or 60))
			okButton.Position = UDim2.fromOffset(size.X / 2, size.Y / 2 + (big and 26 or 14))
			okButton.Text = step.button or "Nice!"
			okButton.Visible = true
			return
		end
		okButton.Visible = false
		local list, text = resolveTarget(step)
		ribbonText.Text = text or Steps.captionFor(step)
		ribbon.Visible = list ~= nil
		if not list then
			-- Nothing to point at right now (a hand is being dealt, the Counter has not opened yet): wait and retry.
			-- While the step's own screen is not up the wait is expected and nothing is darkened (the last hand of the
			-- round is still being scored). Once it is up, a target that stays missing ends the wait
			-- (Steps.whenMissing): the tutorial never stops on a dim screen with nothing to press.
			local function phaseNow() return lastState and lastState.phase or nil end
			local away = aside()
			if away then
				setChromeAside()
			else
				setChromeHidden(not Steps.onItsScreen(step, phaseNow()))
			end
			currentList = nil
			currentStep = nil
			stopFollowing()
			local since, freed = os.clock(), false
			conn = RunService.Heartbeat:Connect(function()
				if resolveTarget(step) then
					stopFollowing()
					show()
					return
				end
				if freed then
					ribbon.Visible = not aside() -- (a freed step's caption is not left over an open screen either)
					return
				end
				if aside() then
					-- The player is looking at something else (a screen of the game, the hand being scored): nothing is
					-- dimmed and nothing is counted. The step comes back when that is over.
					if not away then
						away = true
						setChromeAside()
					end
					since = os.clock()
					return
				elseif away then
					away = false
					setChromeHidden(not Steps.onItsScreen(step, phaseNow()))
				end
				local phase = phaseNow()
				if not Steps.onItsScreen(step, phase) then
					since = os.clock()
					return
				end
				dims[1].BackgroundTransparency = DIM
				local verdict = Steps.whenMissing(step, phase, os.clock() - since)
				if verdict == "wait" then return end
				if not warned[step.id] then
					warned[step.id] = true
					warn("[Tutorial] target not found for step " .. tostring(step.id) .. " (" .. tostring(step.target) .. "): "
						.. (verdict == "skip" and "the step is passed over" or "the dim is lifted"))
				end
				if verdict == "skip" then
					stopFollowing()
					report(step.action)
				else
					freed = true
					setChromeFree(text or Steps.captionFor(step))
				end
			end)
			return
		end
		currentList = list
		currentStep = step
		setChrome(true)
		layout()
		if RunService:IsStudio() then
			local gp = gui.AbsolutePosition
			local x, y, w, h = rectOf(list)
			print(string.format("[Tutorial] step %s target %s rect x=%d y=%d w=%d h=%d (%d element(s))",
				tostring(step.id), tostring(step.target), math.floor(x + gp.X), math.floor(y + gp.Y), math.floor(w), math.floor(h), #list))
		end
		stopFollowing()
		conn = RunService.Heartbeat:Connect(layout) -- the hand and buttons can reflow while the player looks at them
	end

	local function wiggle()
		if not highlight.Visible then return end
		task.spawn(function()
			for _, r in ipairs({ -4, 4, -3, 3, 0 }) do
				TweenService:Create(highlight, TweenInfo.new(0.05, Enum.EasingStyle.Sine), { Rotation = r }):Play()
				task.wait(0.05)
			end
		end)
	end
	for _, f in ipairs(dims) do
		f.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				wiggle() -- a click outside the cutout does nothing but wiggle the target
			end
		end)
	end

	function complete(skipped)
		if completed then return end
		completed = true
		active = false
		pcall(function() require(script.Parent.BoardDrawer).forceOpen("tutorial", false) end)
		if skipped then machine:skip() end
		hideAll()
		dismissNewRibbon()
		MarkTutorialSeenRemote:FireServer(skipped ~= true) -- true = finished, which pays the one-time reward
		-- Leave the scripted run: a fresh normal session replaces it and the player returns to the main menu.
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local startRun = remotes:FindFirstChild("StartRun")
		if startRun then startRun:FireServer() end
		local menu = screenGui:FindFirstChild("MenuRoot", true)
		root.Visible = false
		if menu then menu.Visible = true end
	end

	-- The logic half of forced input: the hub, Shop and buttons ask before acting. A rejected input wiggles
	-- the target and does nothing else. Always true when the tutorial is not running.
	local function allows(kind, detail)
		if not active then return true end
		detail = detail or {}
		detail.scripted = scripted
		if machine:allows(kind, detail) then return true end
		wiggle()
		return false
	end

	function report(action, detail)
		if not active then return end
		local result = machine:report(action, detail)
		if result == "advanced" then
			if machine:finished() then
				complete(false)
			else
				show()
			end
		elseif result == "wrong" then
			wiggle()
		end
	end

	tapButton.MouseButton1Click:Connect(function()
		playClickSfx()
		report("tap")
	end)

	okButton.MouseButton1Click:Connect(function()
		playClickSfx()
		report("ok")
	end)

	skipButton.MouseButton1Click:Connect(function()
		if not active then return end
		playClickSfx()
		local restart = require(script.Parent.RestartRun).get()
		if not restart then
			complete(true) -- the confirm dialog is missing: Skip still works, it never does nothing
			return
		end
		-- the tutorial pauses behind the popup; Cancel (the default) brings it back
		stopFollowing() -- (the per-frame layout switched the spotlight and the caption straight back on, over the popup)
		setChrome(false)
		ribbon.Visible = false
		restart.ask({
			title = TutorialStart.SKIP_TITLE,
			message = TutorialStart.SKIP_MESSAGE,
			holdText = TutorialStart.SKIP_HOLD,
			onConfirm = function() complete(true) end,
			onClose = function() if active then show() end end,
		})
	end)

	-- ===== feeds =====
	TutorialBus.listen(function(action)
		if action == "menu_play" or action == "select_round" then
			report(action)
		end
	end)

	local function start()
		if active or completed then return end
		active = true
		pcall(function() require(script.Parent.BoardDrawer).forceOpen("tutorial", true) end) -- the board stays open while the tutorial points at it
		show()
	end

	-- catch up to the screen the player is really on
	local function syncToState(state)
		local step = machine:current()
		if not step or not state then return end
		if step.action == "menu_play" and root.Visible then
			machine:report("menu_play") -- already past the menu
			step = machine:current()
		end
		if step and step.action == "select_round" and state.phase ~= "roundSelect" and root.Visible then
			if state.phase == "playing" then machine:catchUp("pick") elseif state.phase == "shop" then machine:catchUpShop() end
		end
		if step and (step.action == "pick" or step.action == "play_hand") and state.phase == "shop" then
			machine:catchUpShop() -- the round was cleared: carry on with the Shop steps
		end
	end

	local function onRender(state)
		if not state then return end
		lastState = state
		scripted = state.tutorialStage ~= nil
		-- Never auto-starts: the tutorial begins only from the menu's Tutorial tile (replay()).
		if state.hasSeenTutorial == true then
			dismissNewRibbon()
		end
		if not active then return end
		local before = machine:current()
		syncToState(state)
		if machine:current() ~= before then show() end
	end

	local function replay()
		if active then return end
		dismissNewRibbon()
		local startRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("StartTutorial")
		if startRemote then startRemote:FireServer() end -- scripted run on the server, isolated from the real profile
		machine = Steps.new()
		completed = false
		active = true
		pcall(function() require(script.Parent.BoardDrawer).forceOpen("tutorial", true) end)
		syncToState(lastState)
		show()
	end

	return {
		start = start,
		replay = replay,
		allows = allows,
		onRender = onRender,
		notifySelectionChanged = function(count, weakHand, selectedSet)
			lastSelected = selectedSet or {}
			report("pick", { selected = lastSelected, scripted = scripted })
		end,
		notifyHandPlayed = function() report("play_hand") end,
		notifyDiscardUsed = function() end,
		notifyEnteredShop = function()
			local cur = machine:current()
			if active and cur and not cur.shop and cur.action ~= "next_round" and cur.action ~= "ok" then
				machine:catchUpShop()
				show()
			end
		end,
		-- generic feed for the Shop: buy_patron, buy_pack, pack_item, pack_confirm, tab_*, reroll
		report = function(action, detail) report(action, detail) end,
		notifyNextRoundClicked = function() report("next_round") end,
	}
end
