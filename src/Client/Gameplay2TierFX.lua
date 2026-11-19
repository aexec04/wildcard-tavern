--[[
	Client/Gameplay2TierFX.lua
	Draws Engine/Gameplay2Tier inside the centre score block: a gold pulse, a burst with a small shake, an OVERKILL banner with a
	coin shower, and a "Combo x N" pill when 3 or more Patrons triggered. Everything is a child of the score block, so it never
	reaches the Patron rows or the hand. One FxLoop job, no tweens. Calm mode and Reduce motion: the number and one static label.
	It takes no clicks.

	noteTrigger()                   ScorePopup calls it once per Patron beat of the hand being scored
	show(scoreBox, scoreNum, handTotal, target)   called by Gameplay2ScoreFX when the count up has landed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Gameplay2Tier"))
local FxLoop = require(script.Parent.FxLoop)
local Kit = require(script.Parent.TavernKit)
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local GOLD, DARK, CREAM = Color3.fromRGB(246, 196, 70), Color3.fromRGB(34, 22, 12), Color3.fromRGB(250, 240, 220)
local RED = Color3.fromRGB(120, 36, 30)
local triggers, lastTrigger = 0, 0
local live -- { job, parts = {instances}, restore }

function M.noteTrigger()
	local now = os.clock()
	if now - lastTrigger > Rules.STALE then triggers = 0 end
	triggers = triggers + 1
	lastTrigger = now
end

local function take()
	local n = (os.clock() - lastTrigger <= Rules.STALE) and triggers or 0
	triggers = 0
	return n
end

local function stop()
	if not live then return end
	if live.job then live.job.cancel() end
	for _, p in ipairs(live.parts) do p:Destroy() end
	if live.restore then live.restore() end
	live = nil
end

local function plate(parent, name, rect, text, fill)
	local f = Instance.new("Frame")
	f.Name = name
	f.Active = false
	f.BorderSizePixel = 0
	f.BackgroundColor3 = fill
	f.BackgroundTransparency = 0.05
	f.Position = UDim2.fromOffset(rect.x, rect.y)
	f.Size = UDim2.fromOffset(rect.w, rect.h)
	f.ZIndex = 12
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = GOLD; s.Thickness = 2; s.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.Merriweather
	t.TextSize = 16
	t.TextColor3 = CREAM
	t.TextTransparency = 0
	t.TextStrokeColor3 = DARK
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.ZIndex = 13
	t.Parent = f
	f.Parent = parent
	return f
end

function M.show(scoreBox, scoreNum, handTotal, target)
	stop()
	local n = take()
	if not scoreBox or not scoreBox.Parent then return end
	local tier = Rules.tierOf(handTotal, target)
	local still = Kit.still()
	local fast = ClientSettings.get("animSpeed") == "fast"
	local spec = Rules.spec(tier, n, still, fast)
	if not spec.label and not spec.comboText then return end -- quiet: the count up only
	local size = scoreBox.AbsoluteSize
	local box = { x = 0, y = 0, w = size.X, h = size.Y }
	if box.w < 60 or box.h < 60 then return end
	local mine = { parts = {} }
	live = mine
	local function add(p) mine.parts[#mine.parts + 1] = p; return p end
	local labelFrame
	if spec.label then
		labelFrame = add(plate(scoreBox, "TierLabel", Rules.labelRect(box), spec.label, spec.tier == 3 and RED or Color3.fromRGB(46, 28, 14)))
	end
	if spec.static then
		task.delay(spec.hold, function() if live == mine then stop() end end)
		return
	end
	local comboFrame
	if spec.comboText and box.h >= 2 * Rules.PILL_H + 40 then
		comboFrame = add(plate(scoreBox, "ComboPill", Rules.comboRect(box), spec.comboText, Color3.fromRGB(46, 28, 14)))
	end
	local ring
	if spec.pulse > 0 then
		ring = add(Instance.new("Frame"))
		ring.Name = "TierPulse"
		ring.Active = false
		ring.BackgroundTransparency = 1
		ring.Size = UDim2.fromScale(1, 1)
		ring.ZIndex = 11
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = ring
		local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 3; st.Transparency = 0.2; st.Parent = ring
		ring.Parent = scoreBox
		mine.ringStroke = st
	end
	local dots = {}
	for i = 1, spec.burst do
		local d = add(Instance.new("Frame"))
		d.Name = "TierDot"
		d.Active = false
		d.BorderSizePixel = 0
		d.BackgroundColor3 = GOLD
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(7, 7)
		d.BackgroundTransparency = 1
		d.ZIndex = 12
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = d
		d.Parent = scoreBox
		dots[i] = d
	end
	local coins = {}
	for i = 1, spec.coins do
		local d = add(Instance.new("Frame"))
		d.Name = "TierCoin"
		d.Active = false
		d.BorderSizePixel = 0
		d.BackgroundColor3 = GOLD
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(10, 10)
		d.BackgroundTransparency = 1
		d.ZIndex = 12
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = d
		local s = Instance.new("UIStroke"); s.Color = DARK; s.Thickness = 1; s.Parent = d
		d.Parent = scoreBox
		coins[i] = { d = d, path = Rules.coinPath(i, spec.coins, box), delay = (i % 5) * 0.08 }
	end
	local baseRot = scoreNum and scoreNum.Rotation or 0
	mine.restore = function() if scoreNum and scoreNum.Parent then scoreNum.Rotation = baseRot end end
	local t0 = os.clock()
	mine.job = FxLoop.add(function(_, now)
		if live ~= mine or not scoreBox.Parent then return true end
		local e = now - t0
		if mine.ringStroke then
			local f = math.min(1, e / spec.pulse)
			mine.ringStroke.Transparency = 0.2 + 0.8 * f
		end
		if #dots > 0 then
			local f = math.max(0, math.min(1, e / 0.45))
			for i, d in ipairs(dots) do
				local a = (i / #dots) * math.pi * 2
				local dist = 20 + 0.42 * math.min(box.w, box.h) * f
				d.Position = UDim2.fromOffset(box.w / 2 + math.cos(a) * dist, box.h * 0.45 + math.sin(a) * dist * 0.6)
				d.BackgroundTransparency = (f <= 0 or f >= 1) and 1 or 0.1 + 0.9 * f
			end
		end
		if scoreNum and spec.shake > 0 and e < spec.shake then
			scoreNum.Rotation = baseRot + math.sin(e * 60) * 2 * (1 - e / spec.shake)
		elseif scoreNum then
			scoreNum.Rotation = baseRot
		end
		for _, c in ipairs(coins) do
			local f = (e - c.delay) / 0.7
			if f <= 0 or f >= 1 then
				c.d.BackgroundTransparency = 1
			else
				c.d.Position = UDim2.fromOffset(c.path.x0, c.path.y0 + (c.path.y1 - c.path.y0) * f * f)
				c.d.BackgroundTransparency = f > 0.8 and (f - 0.8) * 5 or 0
			end
		end
		if e > spec.hold - 0.2 then
			local a = math.min(1, (e - (spec.hold - 0.2)) / 0.2)
			for _, p in ipairs({ labelFrame, comboFrame }) do
				if p then p.BackgroundTransparency = 0.05 + 0.95 * a end
			end
		end
		if e >= spec.hold then
			stop()
			return true
		end
		return false
	end, 1 / 30)
end

return M
