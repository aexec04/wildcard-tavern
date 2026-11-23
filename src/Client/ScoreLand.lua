--[[
	Client/ScoreLand.lua
	The round score on the left board lands with the hand's payout, not before it (rules: Engine/ScoreLand).

	The server's answer to a played hand carries the new total. The board used to show it at once, while the reveal in
	the middle of the table was still counting the hand up, so the result was on screen before the reveal got there.

	  ScoreLand.bind(draw)            Client/Sidebar hands over its drawing: draw(score, target)
	  ScoreLand.set(score, target)    every score the server sends (Client/Sidebar calls this where it used to draw)
	  ScoreLand.hold(before)          a reveal starts: the board shows the score from before the hand until land()
	  ScoreLand.expect(score, target) the numbers that land when the new state is itself being held (Client/RevealHold)
	  ScoreLand.land()                the payout has landed (the score popup's finale): count up to the newest total

	Calm mode and Reduce motion get the new number at once, with no count-up. A hold never outlives a round and gives up
	by itself after Engine/ScoreLand.MAX_HOLD seconds, so an old score cannot stay on the board.
]]

local RunService = game:GetService("RunService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("ScoreLand"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local ScoreLand = {}

local draw = nil     -- function(score, target)
local latest = nil   -- { score, target }: the newest numbers the server sent
local pending = nil  -- { score, target }: numbers of a state that is not drawn yet (Client/RevealHold)
local shown = nil    -- { score, target }: what the board shows right now
local held = false
local holdId = 0
local rollId = 0
local rollGoal = nil -- the total a running count-up is heading for

local function put(score, target)
	shown = { score = score, target = target }
	if draw then draw(score, target) end
end

function ScoreLand.bind(fn)
	draw = fn
	if shown then fn(shown.score, shown.target) end
end

function ScoreLand.set(score, target)
	if type(score) ~= "number" or type(target) ~= "number" then return end
	latest = { score = score, target = target }
	if held and shown and Rules.keepsOld(shown.score, shown.target, score, target) then
		return -- the reveal is still playing: the board keeps the score from before the hand
	end
	held, pending = false, nil
	if rollGoal == score and shown and shown.target == target then
		return -- a count-up to this very total is under way: let it finish
	end
	rollId += 1
	rollGoal = nil
	put(score, target)
end

-- The Score plate's count-up (Client/Gameplay2) hands its running value here every step, so the left board and the Target plate always
-- show the same number. No effect while a hold keeps the score from before the hand.
function ScoreLand.mirror(score, target)
	if held or type(score) ~= "number" or type(target) ~= "number" then return end
	put(score, target)
end

function ScoreLand.hold(before)
	if not shown then return end -- nothing has been drawn yet: there is no old score to keep
	held = true
	holdId += 1
	rollId += 1 -- a count-up still running stops where the new hand starts
	rollGoal = nil
	local id = holdId
	if type(before) == "number" then put(before, shown.target) end
	task.delay(Rules.MAX_HOLD, function()
		if held and holdId == id then ScoreLand.land() end
	end)
end

function ScoreLand.expect(score, target)
	if type(score) == "number" and type(target) == "number" then
		pending = { score = score, target = target }
	end
end

function ScoreLand.land()
	if not held then return end
	held = false
	local goal = pending or latest
	pending = nil
	local counted = false -- the Score plate counted up and drove this board with the same running value (ScoreLand.mirror)
	if goal then pcall(function() counted = require(script.Parent.Gameplay2).landScore(goal.score) == true end) end -- the Score plate's numeral too
	if not goal or not shown then return end
	local from = shown.score
	if counted and goal.target == shown.target and goal.score > from then
		rollId += 1
		rollGoal = goal.score
		local id = rollId
		task.delay(4, function() -- safety only: the count's last step already wrote the final total
			if rollId == id then rollGoal = nil; put(goal.score, goal.target) end
		end)
		return
	end
	if goal.target ~= shown.target or goal.score <= from or not ClientSettings.motionAllowed() then
		rollId += 1
		rollGoal = nil
		put(goal.score, goal.target)
		return
	end
	rollId += 1
	rollGoal = goal.score
	local id, t0 = rollId, os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if rollId ~= id then
			conn:Disconnect()
			return
		end
		local t = os.clock() - t0
		put(Rules.rolled(from, goal.score, t, Rules.ROLL_TIME), goal.target)
		if t >= Rules.ROLL_TIME then
			rollGoal = nil
			conn:Disconnect()
		end
	end)
end

function ScoreLand.holding()
	return held
end

return ScoreLand
