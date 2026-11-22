--[[
	Client/PatronPowerPanelFX.lua
	The Patron Power panel at the left of the table (Engine/PatronPowerPanel): the painted hint plate (crown medallion on the left), the
	gold heading and one line about the frame colours. It has no Got it plate: the Got it on the Pick your cards strip and a tap on the
	panel dismiss it. Shown on Night 1 rounds 1 and 2 and on every boss round for the whole round (Got it and playing hands never close it); only the boss intro hides it.
	No tweens, so Calm mode and Reduce motion look the same. Display only.

	update(layer, state, rects, viewW, viewH)   from Gameplay2.update; hides itself when nothing is due or nothing fits
	hide()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("PatronPowerPanel"))
local RoundHints = require(Engine:WaitForChild("RoundHints"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local plate, title, body, tap
local roundKey, handsAtStart -- the round the panel was last due in, and the hands played when it began

local closed, lastHands = false, 0 -- closed with its X: stays shut for the rest of the run

local function build(layer)
	plate = Instance.new("Frame")
	plate.Name = "PatronPowerPanel"
	plate.BackgroundColor3 = Color3.fromRGB(46, 28, 14)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = 28
	plate.Parent = layer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = plate
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(246, 196, 70); st.Thickness = 2; st.Parent = plate
	pcall(function() require(script.Parent.TavernKit).painted(plate, "wh_hint") end) -- crown medallion on the left, flat plate if it does not load
	local function label(name, size, color, font)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Font = font
		t.TextSize = size
		t.TextColor3 = color
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextYAlignment = Enum.TextYAlignment.Top
		t.ZIndex = 29
		t.Parent = plate
		return t
	end
	local TC = RoundHints.TITLE_COLOR
	title = label("Title", Rules.TITLE_SIZE, Color3.fromRGB(TC[1], TC[2], TC[3]), Enum.Font.Merriweather)
	body = label("Body", Rules.BODY_SIZE, Color3.fromRGB(235, 218, 180), Enum.Font.Gotham)
	title.Text, body.Text = Rules.TITLE, Rules.BODY
	title.Position = UDim2.new(0.31, 0, 0, 8); title.Size = UDim2.new(0.64, 0, 0, 28)
	body.Position = UDim2.new(0.31, 0, 0, 38); body.Size = UDim2.new(0.64, 0, 1, -42)
	-- the panel stays for the whole round: a tap or the strip Got it never closes it (it only waits while the round hint holds its spot)
	tap = Instance.new("TextButton")
	tap.Name = "PatronPowerTap"
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 31
	tap.Parent = plate
	pcall(function() -- a small X on the corner: shuts the panel for the rest of the run, the Hints setting stays as it is
		require(script.Parent.CloseX).attach(plate, function() closed = true; M.hide() end, { inset = 8, top = 8, z = 40 })
	end)
end

function M.hide()
	if plate then plate.Visible = false end
end

-- the live rect of the panel while it is on screen (the round hint places itself clear of it), else nil
function M.liveRect()
	local okB, br = pcall(function() return require(script.Parent.BossCardFX).liveRect() end)
	if okB and br then return br end -- on a boss round the Boss card holds the panel's spot
	if plate and plate.Visible and plate.Parent then
		return { x = plate.Position.X.Offset, y = plate.Position.Y.Offset, w = plate.Size.X.Offset, h = plate.Size.Y.Offset }
	end
	return nil
end

-- true while the round hint holds the only free spot: the panel waits and comes back after the hint's Got it
local yielded = false
function M.yieldTo(on) yielded = on == true end
function M.isYielded() return yielded end

local function why(reason, state)
	if not game:GetService("RunService"):IsStudio() then return end
	local line = ("[PanelCheck] %s (night %s round %s boss %s)"):format(reason, tostring(state and state.night), tostring(state and state.round), tostring(state and state.isBossRound))
	if M.lastWhy ~= line then M.lastWhy = line; print(line) end
end

local waiting, latest = false, nil
-- the panel is only drawn when update runs: after the boss intro closes nothing else triggers it, so look again 0.6 s after the intro is gone
local function recheckAfterIntro(layer, state, rects, viewW, viewH)
	if waiting then return end
	waiting = true
	task.spawn(function()
		local t = 0
		while layer.Parent and layer:FindFirstChild("BossIntro") and t < 30 do task.wait(0.1); t += 0.1 end
		task.wait(0.6)
		waiting = false
		if layer.Parent and latest then M.update(table.unpack(latest, 1, 5)) end
	end)
end

function M.update(layer, state, rects, viewW, viewH)
	latest = { layer, state, rects, viewW, viewH } -- the recheck after a boss intro uses the newest call, never a stale one
	if state and state.bossModifier and (state.round or 0) >= 3 then M.hide(); why("hidden: the Boss card replaces it", state); return end
	local hands = tonumber(state and state.handsPlayedTotal) or 0
	if Rules.newRun(lastHands, hands) then closed = false end
	lastHands = hands
	local opts = { enabled = ClientSettings.get("roundHints") ~= false, closedByX = closed }
	local off = Rules.reason(state, opts)
	if off then M.hide(); why("hidden: " .. off, state); return end
	if yielded then M.hide(); why("hidden: the round hint holds the spot", state); return end
	local key = ("%s:%s"):format(tostring(state.night), tostring(state.round))
	if key ~= roundKey then roundKey = key; handsAtStart = tonumber(state.handsPlayedTotal) or 0 end
	if layer:FindFirstChild("BossIntro") then M.hide(); why("hidden: the boss intro is on screen", state); recheckAfterIntro(layer, state, rects, viewW, viewH); return end -- never shares the screen with the boss intro
	local avoid = {}
	local bp = layer:FindFirstChild("BossRulePlate")
	if bp and bp.Visible then avoid[1] = { x = bp.Position.X.Offset, y = bp.Position.Y.Offset, w = bp.Size.X.Offset, h = bp.Size.Y.Offset } end
	pcall(function() -- the consumables tray is only drawn when something is held: an empty tray frees its column
		local held = require(Engine:WaitForChild("Gameplay2Tray")).held(state)
		for _, s in ipairs(held.slots) do if not s.empty then return end end
		local free = {}
		for k, v in pairs(rects) do free[k] = v end
		for _, key in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do free[key] = nil end
		rects = free
	end)
	local spot = Rules.place(rects, viewW, viewH, avoid)
	if not spot then M.hide(); why("hidden: nothing fits clear of the table", state); return end -- nothing fits clear of the table: skip it rather than overlap
	if not plate or plate.Parent ~= layer then build(layer) end
	plate.Visible = true
	why("shown", state)
	plate.Size = UDim2.fromOffset(spot.plate.w, spot.plate.h)
	plate.Position = UDim2.fromOffset(spot.plate.x, spot.plate.y)
	tap.Visible = true
	if game:GetService("RunService"):IsStudio() and M.lastKey ~= viewW .. "x" .. viewH .. spot.kind then
		M.lastKey = viewW .. "x" .. viewH .. spot.kind
		print(("[PowerPanel] %s plate=%d,%d,%d,%d"):format(spot.kind, spot.plate.x, spot.plate.y, spot.plate.w, spot.plate.h))
	end
end

-- the Hints toggle turns the panel off at once
-- the Q key: bring the panel back after its X closed it. True when it is on screen afterwards, false when it is not due this round.
function M.reopen()
	closed = false
	if latest then M.update(table.unpack(latest, 1, 5)) end
	return plate ~= nil and plate.Visible == true
end

pcall(function()
	ClientSettings.onChanged(function(key, value) if key == "roundHints" and value == false then M.hide() end end)
end)

return M
