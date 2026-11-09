--[[
	Shared/Engine/TutorialSteps.lua
	The first-run tutorial as DATA plus a small state machine (pure, tested). One table, easy to edit.

	Rules every step follows:
	  * exactly ONE action: the next step starts only when the player does it, no choices, no "or";
	  * one short line of text, 12 words at most, no double dashes or em dashes;
	  * the whole screen is dimmed except the one thing to click (Client/TutorialWalkthrough draws that);
	  * the pick steps name an exact combo from the scripted hands (Engine/TutorialScript): a pair, two pair,
	    a flush, then a straight flush. The target cards are the first `count` cards of the hand.

	Step fields: id, action, target, allow, text, [expect = "pair"|..., count]
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
TutorialSteps.TargetNames = {
	menuPlay = true, selectButton = true, handCards = true, play = true, nextRound = true,
	sidebarScore = true, sidebarTips = true, sidebarHands = true, sidebarPatrons = true,
	shopPatronsRow = true, cheapestPatron = true, cheapestPack = true, packItems = true, packConfirm = true,
	shopTabMyPatrons = true, shopTabMyRecipes = true, shopTabBuy = true, reroll = true,
}

TutorialSteps.Steps = {
	{ id = "menu_play", action = "menu_play", target = "menuPlay", allow = { "menuPlay" }, text = "Press Play to start your first run." },
	{ id = "select_round", action = "select_round", target = "selectButton", allow = { "select" }, text = "Press Select to play this round." },
	{ id = "pick_pair", action = "pick", target = "handCards", allow = { "card" }, expect = "pair", count = 2, text = "Pick the two matching Sevens." },
	{ id = "play_pair", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand to score your pair." },
	{ id = "pick_two_pair", action = "pick", target = "handCards", allow = { "card" }, expect = "two_pair", count = 4, text = "Pick both pairs: Kings and Fours." },
	{ id = "play_two_pair", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand. Two pair scores more." },
	{ id = "pick_flush", action = "pick", target = "handCards", allow = { "card" }, expect = "flush", count = 5, text = "Pick the five Diamonds for a flush." },
	{ id = "play_flush", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand. A flush scores big." },
	{ id = "pick_straight_flush", action = "pick", target = "handCards", allow = { "card" }, expect = "straight_flush", count = 5, text = "Pick the straight in Clubs, five to nine." },
	{ id = "play_straight_flush", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand for the biggest score." },
	-- After the combos the round is cleared and the Shop opens (`shop = true` marks this section). Each step is
	-- ONE action: tap the spotlighted piece ("tap") or do the named thing.
	{ id = "panel_target", action = "tap", target = "sidebarScore", allow = { "tap" }, shop = true, text = "Reach this target to clear a round and earn Tips." },
	{ id = "panel_tips", action = "tap", target = "sidebarTips", allow = { "tap" }, shop = true, text = "Tips are your money. Spend them at the Counter." },
	{ id = "panel_hands", action = "tap", target = "sidebarHands", allow = { "tap" }, shop = true, text = "Hands and Discards: your plays and card swaps." },
	{ id = "panel_patrons", action = "tap", target = "sidebarPatrons", allow = { "tap" }, shop = true, text = "Patron slots hold the helpers you hire." },
	{ id = "shop_patrons", action = "tap", target = "shopPatronsRow", allow = { "tap" }, shop = true, text = "Patrons give you bonuses every hand." },
	{ id = "buy_patron", action = "buy_patron", target = "cheapestPatron", allow = { "buy" }, shop = true, text = "Buy the cheapest Patron." },
	{ id = "buy_pack", action = "buy_pack", target = "cheapestPack", allow = { "pack" }, shop = true, text = "Buy a Pack and open it." },
	{ id = "pick_pack_item", action = "pack_item", target = "packItems", allow = { "packItem" }, shop = true, text = "Tap one card to keep." },
	{ id = "confirm_pack", action = "pack_confirm", target = "packConfirm", allow = { "packConfirm" }, shop = true, text = "Press Confirm to keep it." },
	{ id = "tab_patrons", action = "tab_mypatrons", target = "shopTabMyPatrons", allow = { "tab" }, tab = "mypatrons", shop = true, text = "Open the My Patrons tab." },
	{ id = "tab_shop", action = "tab_buy", target = "shopTabBuy", allow = { "tab" }, tab = "buy", shop = true, text = "Go back to the Shop tab." },
	{ id = "reroll", action = "reroll", target = "reroll", allow = { "reroll" }, shop = true, text = "Reroll costs Tips and shows new offers." },
	{ id = "next_round", action = "next_round", target = "nextRound", allow = { "nextRound" }, text = "Press Next Round to keep going." },
	{ id = "done", action = "ok", target = nil, allow = { "ok" }, celebrate = true, text = "You did it! Ready to play for real?", button = "Finish" },
}

-- TIME BUDGET. Rough seconds a player needs per action (reading the line, finding the spotlight, doing it; a played
-- hand includes its scoring animation). The whole walkthrough must stay under TutorialSteps.MAX_SECONDS (2 minutes):
-- a test sums it, so adding a step that pushes it over fails until another step is cut.
TutorialSteps.MAX_SECONDS = 120
TutorialSteps.SECONDS = {
	menu_play = 3, select_round = 3, pick = 4, play_hand = 7, tap = 3, buy_patron = 4, buy_pack = 4, pack_item = 3,
	pack_confirm = 3, tab_mypatrons = 3, tab_myrecipes = 3, tab_buy = 3, reroll = 4, next_round = 3, ok = 3,
}

function TutorialSteps.estimatedSeconds()
	local total = 0
	for _, step in ipairs(TutorialSteps.Steps) do
		total = total + (TutorialSteps.SECONDS[step.action] or 4)
	end
	return total
end

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

-- INPUT ALLOW LIST. Every step lists the ONE kind of input it accepts in `allow`; everything else
-- (sort, discard, corner icons, deck pile, buys, reroll, other cards, other menu buttons) is rejected.
-- kinds: menuPlay, select, card, play, discard, sort, nextRound, reroll, buy, pack, ok
-- A `card` allow on a scripted pick step only accepts hand indices 1..count (the scripted combo).
function TutorialSteps.stepAllows(step, kind, detail)
	if not step then return true end
	for _, k in ipairs(step.allow or {}) do
		if k == kind then
			if kind == "tab" then
				return detail ~= nil and detail.key == step.tab -- only the named Shop tab
			end
			if kind == "card" and step.count and detail and detail.scripted then
				local idx = detail.index
				return type(idx) == "number" and idx >= 1 and idx <= step.count
			end
			return true
		end
	end
	return false
end

local DELIBERATE = {
	menu_play = true, select_round = true, play_hand = true, next_round = true, tap = true,
	buy_patron = true, buy_pack = true, pack_confirm = true, reroll = true,
	tab_mypatrons = true, tab_myrecipes = true, tab_buy = true,
}

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

-- Is this input allowed on the current step? True when the tutorial is over.
function Machine:allows(kind, detail)
	return TutorialSteps.stepAllows(self:current(), kind, detail)
end

-- The Shop appeared (the last combo cleared the round): jump to the first Shop-section step.
function Machine:catchUpShop()
	for i = self.index, #TutorialSteps.Steps do
		if TutorialSteps.Steps[i].shop then
			self.index = i
			return true
		end
	end
	return false
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
