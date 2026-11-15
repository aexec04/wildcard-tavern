--[[
	Client/RevealHold.lua
	The next screen waits for the hand that ended the round (rule: Engine/RevealHold).

	The server's answer to the hand that clears a round already says "the Counter is open" (or Run Over, or the next
	boss). Drawing that at once cancelled the hand's reveal in the frame it started, so the round-winning hand, its
	"TARGET CLEARED!" and its win sting were never seen. The hub now hands every state to deliver(): a state that ends
	the round while its reveal is starting is kept back, the table stays up, and the state is drawn when the score
	popup says the reveal has landed.

	  RevealHold.deliver(state, revealStarted, render) -> held   draws the state now, or keeps it for after the reveal
	  RevealHold.landed(after)     the score popup: the finale has played and the popup hides itself in `after` seconds
	  RevealHold.cancelled()       the score popup was cancelled: nothing is left to wait for
	  RevealHold.holding() -> bool

	While a state is kept back the hub's latestState is already the new one, so every table action is refused by the
	guards that were there before (the phase is no longer "playing"). A hold ends by itself after
	Engine/RevealHold.MAX_SECONDS, so a reveal that breaks can never leave the player looking at a finished round.
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("RevealHold"))

local RevealHold = {}

local held = nil -- { state, render, id }
local nextId = 0

local function flush()
	local mine = held
	if not mine then return end
	held = nil
	mine.render(mine.state)
end

function RevealHold.deliver(state, revealStarted, render)
	if held then
		held.state = state -- news that arrives while the reveal plays: the newest state is the one that gets drawn
		return true
	end
	if type(state) == "table" and Rules.holds(revealStarted, state.phase) then
		nextId += 1
		local id = nextId
		held = { state = state, render = render, id = id }
		-- the board's round score lands on the real total with the payout (Client/ScoreLand); the state that carries
		-- that total is the one being kept back, so the numbers are passed on here
		pcall(function() require(script.Parent.ScoreLand).expect(state.roundScore, state.targetScore) end)
		task.delay(Rules.MAX_SECONDS, function()
			if held and held.id == id then flush() end
		end)
		return true
	end
	render(state)
	return false
end

function RevealHold.landed(after)
	local mine = held
	if not mine then return end
	local id = mine.id
	task.delay(math.max(0, tonumber(after) or 0), function()
		if held and held.id == id then flush() end
	end)
end

function RevealHold.cancelled()
	local mine = held
	if not mine then return end
	held = nil
	-- Whatever cancelled the popup is drawing something right now; the kept state is drawn straight after it, so the
	-- newest state from the server is never the one that gets lost.
	task.defer(function() mine.render(mine.state) end)
end

function RevealHold.holding()
	return held ~= nil
end

return RevealHold
