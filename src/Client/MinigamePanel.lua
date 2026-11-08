--[[
	Client/MinigamePanel.lua
	The small overlay for the four map minigames (Engine/Minigames.lua scores everything on the server; this
	only draws `state.minigame.view` and sends moves through the `Minigame` remote).
	  dice      Roll / Hold buttons, your dice and total, the house's dice at the end
	  cardflip  six cards in a grid; matched ones stay face up, a miss shows both for a moment
	  lockpick  a bar with a green zone and a sweeping needle (the server reads its own clock; this is only a
	            picture, so it is measured from the moment the state arrived), a Stop button
	  trivia    the question, three answers and a countdown bar
	Built once by RoundSelect.lua: require(MinigamePanel)({ root, roundCorner, playClickSfx }) ->
	{ update = function(state) }. Text is 15px or larger.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Minigames = require(Engine:WaitForChild("Minigames"))
local WorldMap = require(Engine:WaitForChild("WorldMap"))

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GREEN = Color3.fromRGB(86, 140, 70)
local FACES = { "🍎", "🍞", "🍲" }

return function(deps)
	local root, roundCorner = deps.root, deps.roundCorner
	local playClickSfx = deps.playClickSfx or function() end

	local function fire(stopId, action, arg)
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		local r = folder and folder:FindFirstChild("Minigame")
		if r then
			r:FireServer(stopId, action, arg)
		end
	end

	local function text(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = 17
		l.TextColor3 = INK
		l.TextWrapped = true
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		for k, v in pairs(props) do l[k] = v end
		l.Parent = parent
		return l
	end

	local function button(parent, props)
		local b = Instance.new("TextButton")
		b.Font = Enum.Font.GothamBold
		b.TextSize = 17
		b.TextColor3 = CREAM
		b.BackgroundColor3 = GREEN
		b.TextWrapped = true
		for k, v in pairs(props) do b[k] = v end
		b.Parent = parent
		roundCorner(b, 8)
		return b
	end

	local window = Instance.new("Frame")
	window.Name = "MinigameWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(500, 380)
	window.BackgroundColor3 = PARCHMENT
	window.ZIndex = 40
	window.Visible = false
	window.Parent = root
	roundCorner(window, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(110, 80, 45)
	stroke.Thickness = 3
	stroke.Parent = window
	local title = text(window, { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 10), TextSize = 22, ZIndex = 41 })
	local status = text(window, { Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(12, 44), ZIndex = 41,
		Font = Enum.Font.GothamMedium })
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 94)
	body.Size = UDim2.new(1, -24, 1, -160)
	body.ZIndex = 41
	body.Parent = window
	local close = button(window, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(180, 38),
		Text = "Leave", BackgroundColor3 = Color3.fromRGB(110, 76, 44), ZIndex = 41,
	})

	local stopId = nil
	local needleConn = nil
	local shownAt = 0
	local lastKey = nil
	local missHideAt = 0

	local function clear()
		if needleConn then needleConn:Disconnect(); needleConn = nil end
		for _, c in ipairs(body:GetChildren()) do c:Destroy() end
	end

	close.MouseButton1Click:Connect(function()
		playClickSfx()
		if stopId then fire(stopId, "close") end
		window.Visible = false
		clear()
		stopId = nil
		lastKey = nil
	end)

	local function resultLine(view, result)
		if not view.done then return nil end
		if view.won then
			local extra = {}
			if result and result.token then extra[#extra + 1] = "a map token" end
			if result and result.compass then extra[#extra + 1] = "a compass charge" end
			return "You win!" .. (#extra > 0 and (" You got " .. table.concat(extra, " and ") .. ".") or "")
		end
		return "Not this time. No harm done."
	end

	local function drawDice(view)
		status.Text = resultLine(view, view.result) or string.format("Total %d. Get close to 7 without going over.", view.total or 0)
		local dice = text(body, { Size = UDim2.new(1, 0, 0, 60), TextSize = 38, ZIndex = 42, Text = "" })
		local list = {}
		for _, d in ipairs(view.dice or {}) do list[#list + 1] = "[" .. d .. "]" end
		dice.Text = #list > 0 and table.concat(list, " ") or "Roll a die!"
		if view.done and view.house then
			local h = {}
			for _, d in ipairs(view.house.dice or {}) do h[#h + 1] = "[" .. d .. "]" end
			text(body, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 66), ZIndex = 42,
				Text = "House: " .. table.concat(h, " ") .. " = " .. tostring(view.house.total) })
		elseif not view.done then
			local roll = button(body, { Size = UDim2.fromOffset(140, 44), Position = UDim2.new(0.5, -150, 1, -50), Text = "Roll", ZIndex = 42 })
			roll.MouseButton1Click:Connect(function() playClickSfx(); fire(stopId, "roll") end)
			local hold = button(body, { Size = UDim2.fromOffset(140, 44), Position = UDim2.new(0.5, 10, 1, -50), Text = "Hold", ZIndex = 42,
				BackgroundColor3 = Color3.fromRGB(150, 110, 50) })
			hold.MouseButton1Click:Connect(function() playClickSfx(); fire(stopId, "hold") end)
		end
	end

	local function drawFlip(view)
		status.Text = resultLine(view, view.result) or string.format("Flips used: %d of %d. Find 3 pairs.", view.flips or 0, view.flipLimit or 8)
		local miss = view.lastMiss
		local showMiss = miss and os.clock() < missHideAt
		for i = 1, 6 do
			local face
			if view.matchedFaces and view.matchedFaces[i] then
				face = view.matchedFaces[i]
			elseif view.pending == i then
				face = view.pendingFace
			elseif showMiss and (miss[1] == i or miss[3] == i) then
				face = (miss[1] == i) and miss[2] or miss[4]
			end
			local card = button(body, {
				Size = UDim2.fromOffset(110, 100), Position = UDim2.fromOffset(((i - 1) % 3) * 125 + 20, math.floor((i - 1) / 3) * 112),
				Text = face and FACES[face] or "?", TextSize = face and 44 or 34, ZIndex = 42,
				BackgroundColor3 = face and Color3.fromRGB(240, 226, 190) or Color3.fromRGB(90, 66, 110),
				TextColor3 = face and INK or CREAM,
			})
			card.MouseButton1Click:Connect(function()
				if not view.done and not (view.matchedFaces and view.matchedFaces[i]) then
					playClickSfx()
					fire(stopId, "flip", i)
				end
			end)
		end
	end

	local function drawLock(view)
		status.Text = resultLine(view, view.result) or string.format("Hits %d of %d. Tries %d of %d. Stop the needle in the green zone.",
			view.hits or 0, view.needHits or 3, view.tries or 0, view.maxTries or 5)
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, -20, 0, 36)
		bar.Position = UDim2.fromOffset(10, 30)
		bar.BackgroundColor3 = Color3.fromRGB(120, 92, 60)
		bar.ZIndex = 42
		bar.Parent = body
		roundCorner(bar, 8)
		-- The green zone (arc center +- half width, wrapped onto the 0..360 bar)
		local half = (view.width or 50) / 2
		local lo = math.max(0, (view.center or 0) - half)
		local hi = math.min(360, (view.center or 0) + half)
		local zone = Instance.new("Frame")
		zone.Position = UDim2.fromScale(lo / 360, 0)
		zone.Size = UDim2.fromScale((hi - lo) / 360, 1)
		zone.BackgroundColor3 = GREEN
		zone.BorderSizePixel = 0
		zone.ZIndex = 43
		zone.Parent = bar
		local needle = Instance.new("Frame")
		needle.AnchorPoint = Vector2.new(0.5, 0.5)
		needle.Size = UDim2.new(0, 6, 1.4, 0)
		needle.BackgroundColor3 = Color3.fromRGB(190, 60, 44)
		needle.BorderSizePixel = 0
		needle.ZIndex = 44
		needle.Parent = bar
		if not view.done then
			local t0 = os.clock()
			needleConn = RunService.RenderStepped:Connect(function()
				needle.Position = UDim2.fromScale(Minigames.needleAt(os.clock() - t0, view.speed or 200) / 360, 0.5)
			end)
			local stop = button(body, { Size = UDim2.fromOffset(160, 46), Position = UDim2.new(0.5, -80, 1, -52), Text = "Stop!", ZIndex = 42 })
			stop.MouseButton1Click:Connect(function() playClickSfx(); fire(stopId, "stop") end)
		else
			needle.Position = UDim2.fromScale(0.5, 0.5)
		end
	end

	local function drawTrivia(view)
		status.Text = resultLine(view, view.result) or string.format("Question %d of %d. Correct so far: %d", view.current or 1, view.total or 3, view.correct or 0)
		if view.question then
			text(body, { Size = UDim2.new(1, 0, 0, 50), Text = view.question.text, ZIndex = 42, TextSize = 18 })
			for i, answer in ipairs(view.question.answers) do
				local b = button(body, { Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 54 + (i - 1) * 50), Text = answer, ZIndex = 42,
					TextSize = 15, BackgroundColor3 = Color3.fromRGB(110, 76, 44) })
				b.MouseButton1Click:Connect(function() playClickSfx(); fire(stopId, "answer", i) end)
			end
			local timer = Instance.new("Frame")
			timer.Size = UDim2.new((view.secondsLeft or 15) / Minigames.QUESTION_SECONDS, 0, 0, 8)
			timer.Position = UDim2.new(0, 0, 1, -8)
			timer.BackgroundColor3 = Color3.fromRGB(222, 182, 104)
			timer.BorderSizePixel = 0
			timer.ZIndex = 42
			timer.Parent = body
			-- Count down for the picture only; the server judges lateness itself.
			local t0, left = os.clock(), view.secondsLeft or 15
			needleConn = RunService.RenderStepped:Connect(function()
				local s = math.max(0, left - (os.clock() - t0))
				timer.Size = UDim2.new(s / Minigames.QUESTION_SECONDS, 0, 0, 8)
			end)
		end
	end

	local M = {}

	function M.update(state)
		local mg = type(state) == "table" and state.phase == "roundSelect" and state.minigame or nil
		if not mg or not mg.view then
			window.Visible = false
			clear()
			stopId, lastKey = nil, nil
			return
		end
		stopId = mg.stopId
		local view = mg.view
		view.result = mg.result
		local info = WorldMap.Stops[stopId]
		title.Text = (info and info.icon or "") .. " " .. (info and info.name or "Minigame")
		if view.lastMiss then
			missHideAt = os.clock() + 0.9
		end
		window.Visible = true
		clear()
		if view.game == "dice" then drawDice(view)
		elseif view.game == "cardflip" then drawFlip(view)
		elseif view.game == "lockpick" then drawLock(view)
		elseif view.game == "trivia" then drawTrivia(view) end
		shownAt = os.clock()
	end

	return M
end
