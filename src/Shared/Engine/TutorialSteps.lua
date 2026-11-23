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
	shopTabMyPatrons = true, shopTabMyRecipes = true, shopTabBuy = true, reroll = true, shopTips = true,
	myPatronCards = true, myPatronDiscard = true, myHousePasses = true,
}

TutorialSteps.Steps = {
	{ id = "menu_play", action = "menu_play", target = "menuPlay", allow = { "menuPlay" }, text = "Press Play to start your first run." },
	{ id = "select_round", action = "select_round", target = "selectButton", allow = { "select" }, text = "Pick The Corner Table to start your first round." },
	{ id = "pick_pair", action = "pick", target = "handCards", allow = { "card" }, expect = "pair", count = 2, text = "Pick the two matching Sevens." },
	{ id = "play_pair", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand to score your pair." },
	-- The left board is only on screen at the table (it slides away at the Counter), so its lesson sits here, on the
	-- score the first hand has just landed on it. It used to come in the Shop, where it pointed at an empty wall.
	{ id = "panel_target", action = "tap", target = "sidebarScore", allow = { "tap" }, text = "Reach this target to clear a round and earn Tips." },
	{ id = "pick_two_pair", action = "pick", target = "handCards", allow = { "card" }, expect = "two_pair", count = 4, text = "Pick both pairs: Kings and Fours." },
	{ id = "play_two_pair", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand to score two pair." },
	{ id = "pick_flush", action = "pick", target = "handCards", allow = { "card" }, expect = "flush", count = 5, text = "Pick the five Diamonds for a flush." },
	{ id = "play_flush", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand to score the flush." },
	{ id = "pick_straight_flush", action = "pick", target = "handCards", allow = { "card" }, expect = "straight_flush", count = 5, text = "Pick the straight in Clubs, five to nine." },
	{ id = "play_straight_flush", action = "play_hand", target = "play", allow = { "play" }, text = "Press Play Hand for the biggest score." },
	-- After the combos the round is cleared and the Shop opens (`shop = true` marks this section). Each step is
	-- ONE action: tap the spotlighted piece ("tap") or do the named thing.
	-- (the Counter shows the Tips on its own plate, top right: Client/ShopPurse)
	{ id = "panel_tips", action = "tap", target = "shopTips", allow = { "tap" }, shop = true, text = "Tips are your money to spend at the Counter." },
	{ id = "shop_patrons", action = "tap", target = "shopPatronsRow", allow = { "tap" }, shop = true, text = "Patrons give you bonuses every hand." },
	{ id = "buy_patron", action = "buy_patron", target = "cheapestPatron", allow = { "buy" }, shop = true, text = "Buy the cheapest Patron." },
	{ id = "buy_pack", action = "buy_pack", target = "cheapestPack", allow = { "pack" }, shop = true, text = "Buy a Pack and open it." },
	{ id = "pick_pack_item", action = "pack_item", target = "packItems", allow = { "packItem" }, shop = true, text = "Tap one card to keep." },
	{ id = "confirm_pack", action = "pack_confirm", target = "packConfirm", allow = { "packConfirm" }, shop = true, text = "Press Confirm to keep it." },
	{ id = "tab_patrons", action = "tab_mypatrons", target = "shopTabMyPatrons", allow = { "tab" }, tab = "mypatrons", shop = true, text = "Open the My Patrons tab." },
	-- What My Patrons holds (read from Client/Shop.lua rebuildMyPatronsTab): owned Patron cards with a Discard plate (refunds half
	-- the price) beside the empty seats (a full table needs a Discard before you can hire), House Passes below. Every target
	-- here is in the tab itself: the left panel is not on screen at the Counter.
	{ id = "mp_patrons", action = "tap", target = "myPatronCards", allow = { "tap" }, shop = true, text = "Hired Patrons live here and help every hand." },
	{ id = "mp_seats", action = "tap", target = "myPatronCards", allow = { "tap" }, shop = true, text = "Each seat holds one Patron, and full seats need a Discard." },
	{ id = "mp_discard", action = "tap", target = "myPatronDiscard", allow = { "tap" }, shop = true, text = "Discard sells a Patron back for half its price." },
	{ id = "mp_passes", action = "tap", target = "myHousePasses", allow = { "tap" }, shop = true, text = "House Passes last all run, and you have none yet." },
	{ id = "tab_shop", action = "tab_buy", target = "shopTabBuy", allow = { "tab" }, tab = "buy", shop = true, text = "Go back to the Shop tab." },
	{ id = "reroll", action = "reroll", target = "reroll", allow = { "reroll" }, shop = true, text = "Reroll costs Tips and shows new offers." },
	{ id = "next_round", action = "next_round", target = "nextRound", allow = { "nextRound" }, text = "Press Next Round to keep going." },
	{ id = "done", action = "ok", target = nil, allow = { "ok" }, celebrate = true, text = "Nice work, you are ready to play for real!", button = "Finish" },
}

-- TIME BUDGET. Rough seconds a player needs per action (reading the line, finding the spotlight, doing it; a played
-- hand includes its scoring animation). The whole walkthrough must stay under TutorialSteps.MAX_SECONDS (2 minutes):
-- a test sums it, so adding a step that pushes it over fails until another step is cut.
TutorialSteps.MAX_SECONDS = 120
TutorialSteps.SECONDS = {
	menu_play = 3, select_round = 3, pick = 4, play_hand = 7, tap = 3, buy_patron = 4, buy_pack = 4, pack_item = 3,
	pack_confirm = 3, tab_mypatrons = 3, tab_myrecipes = 3, tab_buy = 3, reroll = 4, next_round = 3, ok = 3,
}

-- Which screen a step lives on: "menu", "roundSelect", "table", "shop" or "done".
function TutorialSteps.screenOf(step)
	if step.action == "menu_play" then return "menu" end
	if step.action == "select_round" then return "roundSelect" end
	if step.action == "ok" then return "done" end
	if step.shop or step.action == "next_round" then return "shop" end
	return "table"
end

-- Which phase of the run draws a step's screen (the menu and the last card have none).
local SCREEN_PHASE = { roundSelect = "roundSelect", table = "playing", shop = "shop" }

-- Is the screen this step lives on the one that is up? While it is not (the Counter has not opened yet because the
-- last hand of the round is still being scored), a missing target is an expected wait and nothing is darkened.
function TutorialSteps.onItsScreen(step, phase)
	local want = step and SCREEN_PHASE[TutorialSteps.screenOf(step)]
	return want == nil or want == phase
end

-- A target that cannot be found must never leave the player on a dim screen with nothing to press (the Discard plate
-- used to exist only while its card was hovered, and the tutorial stopped there). After MISSING_GRACE seconds on the
-- step's own screen a tap step, which only explains something, is passed over ("skip"); a step that wants an action
-- has the dim lifted so the action can still be done ("free"). Before that, and on another screen: "wait".
TutorialSteps.MISSING_GRACE = 3
function TutorialSteps.whenMissing(step, phase, waited)
	if not step or not TutorialSteps.onItsScreen(step, phase) then return "wait" end
	if (waited or 0) < TutorialSteps.MISSING_GRACE then return "wait" end
	if step.action == "tap" then return "skip" end
	return "free"
end

-- Do two rects { x, y, w, h } overlap?
function TutorialSteps.meets(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- The game's own tooltip (what the hovered card does) is never covered by the caption plate. ribbon and tip are
-- { x, y, w, h } in the same space. Returns the caption's y and whether it moved: unchanged while the two keep AIR px
-- apart, otherwise just under the tooltip, or just above it when there is no room below.
TutorialSteps.CAPTION_AIR = 8
function TutorialSteps.captionClearOf(ribbon, tip, screenH)
	local air = TutorialSteps.CAPTION_AIR
	if not tip or tip.w <= 0 or tip.h <= 0 then return ribbon.y, false end
	if not TutorialSteps.meets({ x = ribbon.x, y = ribbon.y - air, w = ribbon.w, h = ribbon.h + 2 * air }, tip) then
		return ribbon.y, false
	end
	local below = tip.y + tip.h + air
	if below + ribbon.h <= screenH - air then return below, true end
	return math.max(air, tip.y - air - ribbon.h), true
end

-- The tutorial steps aside (nothing dimmed, no caption, nothing counted) while the player is looking at something
-- else: one of the game's own screens is open over the step (Volume, Settings, the Tavern Map, a popup: the frame of
-- every such screen is named "...Backdrop"), or the hand that was just played is still being scored. The corner icons
-- stay usable during the tutorial, and a screen opened from them used to sit under the tutorial's dim. The score
-- reveal of every tutorial hand played under that dim as well, with the next instruction already on top of it.
--   visibleNames = names of the visible top-level frames; revealPlaying = the score reveal is on screen
function TutorialSteps.stepsAside(visibleNames, revealPlaying)
	if revealPlaying == true then return true end
	for _, name in ipairs(visibleNames or {}) do
		if type(name) == "string" and name:sub(-8) == "Backdrop" then return true end
	end
	return false
end

-- The caption plate and its arrow never sit on the Skip button. The Tips plate at the Counter is right above that
-- button, and the caption under it was half covered by it. ribbon = { x, y, w, h }; arrow = { x, y } is the middle
-- of its ARROW px square; skip = { x, y, w, h }; target = { x, w } is the span of the lit target. A caption that
-- meets the button slides sideways until it is CAPTION_AIR clear of it, to the left when there is room and
-- otherwise to the right; with room on neither side it stays (it is never pushed off the screen). The arrow slides
-- the same way while it still points into the target; when it cannot, it is not drawn (arrowX = nil).
TutorialSteps.ARROW = 40
function TutorialSteps.clearOfSkip(ribbon, arrow, skip, target, screenW)
	local air = TutorialSteps.CAPTION_AIR
	local out = { ribbonX = ribbon.x, arrowX = arrow.x }
	local zone = { x = skip.x - air, y = skip.y - air, w = skip.w + 2 * air, h = skip.h + 2 * air }
	if TutorialSteps.meets(ribbon, zone) then
		local left, right = skip.x - air - ribbon.w, skip.x + skip.w + air
		if left >= air then
			out.ribbonX = left
		elseif right + ribbon.w <= screenW - air then
			out.ribbonX = right
		end
	end
	local half = TutorialSteps.ARROW / 2
	if TutorialSteps.meets({ x = arrow.x - half, y = arrow.y - half, w = 2 * half, h = 2 * half }, zone) then
		local function inTarget(x) return x - half >= target.x and x + half <= target.x + target.w end
		local leftX, rightX = skip.x - air - half, skip.x + skip.w + air + half
		if inTarget(leftX) then
			out.arrowX = leftX
		elseif inTarget(rightX) then
			out.arrowX = rightX
		else
			out.arrowX = nil
		end
	end
	return out
end

-- Where the caption plate and its arrow go for a lit target { x, y, w, h } on a screen of size { w, h }: below the
-- cutout, above it when there is no room below, and beside it for a tall target, centred and kept on screen, never on
-- the target itself. rw, rh = the plate size; avoid = optional rects (Play Hand, Discard) the plate steps off. Returns { x, y, arrowX, arrowY, arrow = "^" | "v" | "<" | ">" }.
-- Client/TutorialWalkthrough places the plate with this, so the tests see the same rect the player does.
function TutorialSteps.captionPlace(target, screen, rw, rh, avoid)
	local x, y, w, h = target.x, target.y, target.w, target.h
	local cx = math.min(math.max(x + w / 2 - rw / 2, 12), math.max(12, screen.w - rw - 12))
	local function clear(px, py)
		for _, a in ipairs(avoid or {}) do
			if TutorialSteps.meets({ x = px, y = py, w = rw, h = rh }, a) then return false end
		end
		return true
	end
	local below = y + h + 56 + rh <= screen.h - 8
	local above = y - 44 - rh >= 8
	-- Play Hand and Discard sit under the hand: a caption that would land on them goes above the hand instead.
	if below and not clear(cx, y + h + 44) and above and clear(cx, y - 44 - rh) then below = false end
	if below or above then
		return {
			x = cx,
			y = below and (y + h + 44) or (y - 44 - rh),
			arrowX = x + w / 2, arrowY = below and (y + h + 22) or (y - 22), arrow = below and "^" or "v",
		}
	end
	local right = x + w + 56 + rw <= screen.w - 8
	return {
		x = right and (x + w + 48) or math.max(8, x - 48 - rw),
		y = math.min(math.max(y + h / 2 - rh / 2, 8), math.max(8, screen.h - rh - 8)),
		arrowX = right and (x + w + 24) or (x - 24), arrowY = y + h / 2, arrow = right and "<" or ">",
	}
end

-- The caption is always the step's own line (never a generic fallback while a different thing is spotlighted).
function TutorialSteps.captionFor(step)
	if step and type(step.text) == "string" and step.text ~= "" then return step.text end
	return "Follow the highlight."
end

-- The hand may be spotlighted only while the hand is really on screen: the run is on the table, the hand frame and its parents
-- are visible, its rect is on screen, and no full-screen panel (RoundSelect, Shop, Menu, Collection ...) is up.
function TutorialSteps.handShowable(phase, frameVisible, rectOnScreen, overlayOpen)
	return phase == "playing" and frameVisible == true and rectOnScreen == true and overlayOpen ~= true
end

function TutorialSteps.estimatedSeconds()
	local total = 0
	for _, step in ipairs(TutorialSteps.Steps) do
		total = total + (TutorialSteps.SECONDS[step.action] or 4)
	end
	return total
end

-- Seconds from the Menu to the first cleared round (every step before the Counter section) and the longest single step.
TutorialSteps.MAX_STEP_SECONDS = 20
function TutorialSteps.secondsToRoundClear()
	local total = 0
	for _, step in ipairs(TutorialSteps.Steps) do
		if step.shop then break end
		total = total + (TutorialSteps.SECONDS[step.action] or 4)
	end
	return total
end

function TutorialSteps.longestStepSeconds()
	local longest, which = 0, nil
	for _, step in ipairs(TutorialSteps.Steps) do
		local t = TutorialSteps.SECONDS[step.action] or 4
		if t > longest then longest, which = t, step.id end
	end
	return longest, which
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
