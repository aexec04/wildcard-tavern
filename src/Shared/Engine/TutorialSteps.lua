--[[
	Shared/Engine/TutorialSteps.lua
	The first-run tutorial as DATA plus a small state machine (pure, tested). One table, easy to edit.

	Rules every step follows:
	  * exactly ONE action: the next step starts only when the player does it, no choices, no "or";
	  * one short line of text, 12 words at most, no double dashes or em dashes;
	  * the whole screen is dimmed except the one thing to click (Client/TutorialWalkthrough draws that);
	  * the pick steps name an exact combo from the scripted hands (Engine/TutorialScript): a pair, two pair,
	    a flush, then a straight flush. The target cards are the first `count` cards of the hand.

	Step fields: id, action, target, text, [expect = "pair"|..., count]
	  actions: menu_play, select_round, pick, play_hand, next_round, ok

	machine = TutorialSteps.new()
	  machine:current()                  the current step (nil when finished)
	  machine:report(action, detail)     -> "advanced" | "wrong" | "ignored"
	        pick: detail = { selected = { [handIndex] = true }, handCount = n }; it advances only when exactly the
	        target cards are selected (or, for an unscripted replay, at least one card)
	        a deliberate action that is not the current one is "wrong" (the client wiggles the target);
	        selecting is never wrong
	  machine:catchUp(action)            jump to the first step with this action at or after the current one
	                                     (for example the Shop appears early: jump to next_round)
	  machine:skipHold()                 a HoldConfirm (1.5s): the Skip button needs a deliberate hold
	  machine:finished() / machine:skipped()
]]

local HoldConfirm = require(script.Parent.HoldConfirm)

local TutorialSteps = {}

TutorialSteps.MAX_WORDS = 12

-- Every step target must be one of these names; Client/TutorialWalkthrough resolves each live, every frame.
TutorialSteps.TargetNames = { menuPlay = true, selectButton = true, handCards = true, play = true, nextRound = true }

TutorialSteps.Steps = {
	{ id = "menu_play", action = "menu_play", target = "menuPlay", text = "Press Play to start your first run." },
	{ id = "select_round", action = "select_round", target = "selectButton", text = "Press Select to play this round." },
	{ id = "pick_pair", action = "pick", target = "handCards", expect = "pair", count = 2, text = "Pick the two matching Sevens." },
	{ id = "play_pair", action = "play_hand", target = "play", text = "Press Play Hand to score your pair." },
	{ id = "pick_two_pair", action = "pick", target = "handCards", expect = "two_pair", count = 4, text = "Pick both pairs: Kings and Fours." },
	{ id = "play_two_pair", action = "play_hand", target = "play", text = "Press Play Hand. Two pair scores more." },
	{ id = "pick_flush", action = "pick", target = "handCards", expect = "flush", count = 5, text = "Pick the five Diamonds for a flush." },
	{ id = "play_flush", action = "play_hand", target = "play", text = "Press Play Hand. A flush scores big." },
	{ id = "pick_straight_flush", action = "pick", target = "handCards", expect = "straight_flush", count = 5, text = "Pick the straight in Clubs, five to nine." },
	{ id = "play_straight_flush", action = "play_hand", target = "play", text = "Press Play Hand for the biggest score." },
	{ id = "next_round", action = "next_round", target = "nextRound", text = "Press Next Round to keep going." },
	{ id = "done", action = "ok", target = nil, text = "Title unlocked: Newcomer. Equip it in Collection.", button = "Nice!" },
}

-- selected = { [handIndex] = true }; the target cards are hand slots 1..count.
function TutorialSteps.pickSatisfied(step, detail)
	detail = detail or {}
	local selected = detail.selected or {}
	local n = 0
	for _ in pairs(selected) do n = n + 1 end
	if not step.count or not detail.scripted then
		return n >= 1 -- an unscripted replay: any card will do
	end
	if n ~= step.count then return false end
	for i = 1, step.count do
		if not selected[i] then return false end
	end
	return true
end

local DELIBERATE = { menu_play = true, select_round = true, play_hand = true, next_round = true }

local Machine = {}
Machine.__index = Machine

function TutorialSteps.new()
	return setmetatable({ index = 1, done = false, wasSkipped = false, hold = HoldConfirm.new(1.5) }, Machine)
end

function Machine:current()
	if self.done then return nil end
	return TutorialSteps.Steps[self.index]
end

function Machine:finished()
	return self.done
end

function Machine:skipped()
	return self.wasSkipped
end

function Machine:_advance()
	self.index = self.index + 1
	if self.index > #TutorialSteps.Steps then
		self.done = true
	end
end

function Machine:report(action, detail)
	local step = self:current()
	if not step then return "ignored" end
	if action == "pick" then
		if step.action == "pick" and TutorialSteps.pickSatisfied(step, detail) then
			self:_advance()
			return "advanced"
		end
		return "ignored" -- selecting is never wrong, it just is not the right set yet
	end
	if action == step.action then
		self:_advance()
		return "advanced"
	end
	if DELIBERATE[action] then
		return "wrong"
	end
	return "ignored"
end

function Machine:catchUp(action)
	for i = self.index, #TutorialSteps.Steps do
		if TutorialSteps.Steps[i].action == action then
			self.index = i
			return true
		end
	end
	return false
end

-- Skipping needs a deliberate hold (HoldConfirm): press/release/update with os.clock-style times.
function Machine:skipHold()
	return self.hold
end

function Machine:skip()
	self.wasSkipped = true
	self.done = true
end

return TutorialSteps
