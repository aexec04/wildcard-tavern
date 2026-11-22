import re

# ---- Engine/Gameplay2Moments
p = 'src/Shared/Engine/Gameplay2Moments.lua'
s = open(p).read()
old = '''	return { title = "Target cleared", score = string.format("Score %d of %d", score, target), tips = string.format("Tips +%d", earned), tipsEarned = earned }
end'''
assert old in s
s = s.replace(old, '''	local lines = { title = "Target cleared", score = string.format("Score %d of %d", score, target), tips = string.format("Tips +%d", earned), tipsEarned = earned }
	lines.night = M.nightLines(prev)
	return lines
end

-- the last round of a Night (the Boss Round) was cleared: a bigger plate with a Continue button; clearing the last Night of a run is
-- "Run complete" with a crown glow. nil for an ordinary round.
function M.nightLines(prev)
	if not prev or not prev.bossModifier or floor(prev.round) < 3 then return nil end
	local night, cap = floor(prev.night), floor(prev.nightCap)
	local complete = cap > 0 and night >= cap and prev.endless ~= true
	return {
		title = complete and "Run complete" or "Night cleared",
		sub = cap > 0 and string.format("Night %d of %d", night, cap) or string.format("Night %d", night),
		runComplete = complete,
		button = "Continue",
	}
end

function M.nightPlate(w, h, runComplete)
	local pw = math.min(runComplete and 560 or 480, math.max(280, math.floor(w * (runComplete and 0.5 or 0.44))))
	local ph = math.min(runComplete and 300 or 260, math.max(190, math.floor(h * (runComplete and 0.40 or 0.36))))
	ph = math.min(ph, h - 16)
	return { x = math.floor((w - pw) / 2), y = math.max(8, math.floor((h - ph) / 2)), w = pw, h = ph }
end

-- the Continue plate sits at the bottom of the night plate (relative to it), 48 px tall, inside it
function M.continueRect(plate)
	local bw, bh = math.min(200, plate.w - 40), 48
	return { x = math.floor((plate.w - bw) / 2), y = plate.h - bh - 14, w = bw, h = bh }
end

M.NIGHT_AUTO_CLOSE = 8 -- seconds; Continue ends it sooner, and it never blocks the Counter behind it''')
old = '''	defeatLine(state)                -> "Out of hands. Score X of Y."'''
assert old in s
s = s.replace(old, '''	nightLines(prev)                 -> nil | { title = "Night cleared" | "Run complete", sub, runComplete, button } (a Boss Round was cleared)
	nightPlate(w, h, runComplete)    -> { x, y, w, h } the Night plate (bigger for Run complete), inside the screen
	continueRect(plate)              -> { x, y, w, h } relative to the plate, 48 px tall
''' + old, 1)
open(p, 'w').write(s)

# ---- Gameplay2.lua remembers more of the state
p = 'src/Client/Gameplay2.lua'
s = open(p).read()
a = 'self.prev = { phase = "playing", targetScore = lastState.targetScore, roundScore = lastState.roundScore, tips = lastState.tips }'
assert a in s
s = s.replace(a, 'self.prev = { phase = "playing", targetScore = lastState.targetScore, roundScore = lastState.roundScore, tips = lastState.tips,\n\t\t\tround = lastState.round, night = lastState.night, nightCap = lastState.nightCap, endless = lastState.endless, bossModifier = lastState.bossModifier }')
open(p, 'w').write(s)

# ---- Client FX
p = 'src/Client/Gameplay2MomentsFX.lua'
s = open(p).read()
old = '''function M.clear(root, lines)
	if not root or not lines then return end
	local old = root:FindFirstChild("TargetClearedPlate")
	if old then old:Destroy() end'''
assert old in s
new = '''-- Night cleared and Run complete: a bigger plate, gold and purple confetti, tips counting up, a green Continue plate
local function night(root, lines)
	local prior = root:FindFirstChild("NightClearedPlate")
	if prior then prior:Destroy() end
	local n = lines.night
	local size = root.AbsoluteSize
	local rect = Rules.nightPlate(size.X, size.Y, n.runComplete)
	local timing = Rules.clearTiming(calm(), fast())
	local holder = Instance.new("Frame")
	holder.Name = "NightClearedPlate"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(rect.w, rect.h)
	holder.Position = UDim2.fromOffset(rect.x, rect.y)
	holder.ZIndex = 41
	holder.Parent = root
	if n.runComplete then -- a soft gold crown glow behind the plate: a solid frame, never a Transparency gradient
		local glow = Instance.new("Frame")
		glow.Name = "CrownGlow"
		glow.BorderSizePixel = 0
		glow.Active = false
		glow.BackgroundColor3 = color("gold")
		glow.BackgroundTransparency = 0.82
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 28, 1, 28)
		glow.ZIndex = 40
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 20); gc.Parent = glow
		glow.Parent = holder
	end
	local plate = Kit.plate(holder, UDim2.fromScale(1, 1))
	plate.Name = "Plate"
	plate.Active = false
	plate.ZIndex = 41
	local big = n.runComplete
	text(plate, "Title", n.title, big and 40 or 32, "gold", Style.FONTS.title, 10, big and 48 or 40)
	text(plate, "Night", n.sub, 20, "cream", Style.FONTS.ui, big and 60 or 52, 26)
	text(plate, "Score", lines.score, 20, "cream", Style.FONTS.ui, big and 90 or 80, 26)
	local counting = timing.count and lines.tipsEarned > 0
	local tips = text(plate, "Tips", counting and "Tips +0" or lines.tips, 20, "cream", Style.FONTS.ui, big and 120 or 108, 26)
	local cr = Rules.continueRect({ w = rect.w, h = rect.h })
	local btn = Kit.primaryButton(plate, n.button)
	btn.Name = "Continue"
	btn.Size = UDim2.fromOffset(cr.w, cr.h)
	btn.Position = UDim2.fromOffset(cr.x, cr.y)
	btn.ZIndex = 44
	local closed = false
	local function close()
		if closed then return end
		closed = true
		if holder.Parent then holder:Destroy() end
	end
	btn.MouseButton1Click:Connect(close)
	task.delay(Rules.NIGHT_AUTO_CLOSE, close)
	pcall(function() require(script.Parent.ConfettiFX).burst(root, true) end) -- gold and purple, nothing in Calm mode
	if counting then
		local steps = Celebration.countSteps(lines.tipsEarned, false)
		if steps then
			task.spawn(function()
				for _, v in ipairs(steps.values) do
					if not tips.Parent then return end
					tips.Text = string.format("Tips +%d", v)
					task.wait(steps.step)
				end
			end)
		end
	end
end

function M.clear(root, lines)
	if not root or not lines then return end
	if lines.night then
		night(root, lines)
		return
	end
	local old = root:FindFirstChild("TargetClearedPlate")
	if old then old:Destroy() end'''
s = s.replace(old, new, 1)
open(p, 'w').write(s)

# ---- test
p = 'src/Shared/Tests/EngineTests.lua'
s = open(p).read()
marker = 'table.insert(tests, { name = "Gameplay v2 Patron tooltip: 0.25 s delay'
assert marker in s
test = '''table.insert(tests, { name = "Gameplay v2 Night cleared and Run complete: only a cleared Boss Round, Run complete on the last Night, plates inside the screen with a 48 px Continue", fn = function()
	local M = require(script.Parent.Parent.Engine.Gameplay2Moments)
	local boss = { phase = "playing", targetScore = 100, roundScore = 120, tips = 5, round = 3, night = 2, nightCap = 8, bossModifier = { id = "bouncer" } }
	local now = { phase = "shop", roundScore = 120, tips = 12 }
	local l = M.clearLines(boss, now)
	assert(l and l.night and l.night.title == "Night cleared" and l.night.sub == "Night 2 of 8" and not l.night.runComplete and l.night.button == "Continue")
	boss.night = 8
	assert(M.clearLines(boss, now).night.title == "Run complete" and M.clearLines(boss, now).night.runComplete)
	boss.endless = true
	assert(M.clearLines(boss, now).night.title == "Night cleared", "Endless Nights keep going")
	local plain = { phase = "playing", targetScore = 100, roundScore = 120, tips = 5, round = 1, night = 2, nightCap = 8 }
	assert(M.clearLines(plain, now) and M.clearLines(plain, now).night == nil, "an ordinary round has no Night plate")
	for _, sz in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 1024, 600 }, { 800, 400 } }) do
		for _, big in ipairs({ false, true }) do
			local p = M.nightPlate(sz[1], sz[2], big)
			assert(p.x >= 0 and p.y >= 0 and p.x + p.w <= sz[1] and p.y + p.h <= sz[2], "plate on screen at " .. sz[1])
			local c = M.continueRect(p)
			assert(c.h >= 44 and c.x >= 0 and c.x + c.w <= p.w and c.y + c.h <= p.h, "Continue inside the plate at " .. sz[1])
			assert(c.y >= 150, "Continue below the four text lines at " .. sz[1])
		end
	end
	assert(M.nightPlate(1920, 1080, true).w > M.nightPlate(1920, 1080, false).w, "Run complete is the bigger plate")
	if not io then return end
	local f = assert(io.open("src/Client/Gameplay2MomentsFX.lua", "r")); local src = f:read("a"); f:close()
	assert(src:find("ConfettiFX", 1, true) and src:find("CrownGlow", 1, true) and src:find("calm()", 1, true), "confetti and glow, Calm mode checked")
end })

'''
s = s.replace(marker, test + marker, 1)
open(p, 'w').write(s)
print("patched")
