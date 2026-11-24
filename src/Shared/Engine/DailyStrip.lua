--[[
	Engine/DailyStrip.lua
	Gameplay v2: the slim daily return strip on the Night map (phase roundSelect) and Run Over (phase gameover), never on the table.
	Pure and tested. Client/DailyStrip draws it. It adds no rules of its own: the streak, the UTC day rollover and the once a day
	claim all live in Engine/LoginStreak (server authoritative, ClaimLoginReward re-checks everything), the goal is the first
	unfinished daily quest from Engine/Quests.

	visible(phase)               -> true on roundSelect and gameover only
	view(login, quests)          -> { streakText, goalText, goalDone, progress, goal, chest, chestText, rewardLabel, claimDay }
	                                chest is "ready" (claim it), "opened" (claimed today) or "none" (no streak yet, old save)
	rect(w, h)                   -> { x, y, w, h } slim strip centred at the bottom, inside the screen, MIN_TOUCH tall
	chestRect(strip)             -> { x, y, w, h } relative to the strip, at least 44 x 44
	reveal(calm, fast)           -> { open, glow } seconds; 0 means no motion (Calm mode, Reduce motion)
	Old saves: login or quests may be nil or partly empty; every field falls back to a safe default.
]]

local M = {}

M.MIN_TOUCH = 44
M.HEIGHT = 48
M.MAX_W = 620
M.MARGIN = 12
M.CHEST_PAD, M.CHEST_MIN_W, M.CHEST_MAX_W = 12, 174, 194 -- the chest word stays 12 px inside the plate edge (24 px wider than before, so "Next in 19h 38m" has room)

function M.visible(phase)
	return phase == "roundSelect" -- Run Over hides it: the faded strip showed through under the panel
end

-- true while at least one full screen Tome or Collection page is open (PanelFullScreen counts them on the ScreenGui)
function M.hiddenByPage(openCount)
	return openCount == true or (type(openCount) == "number" and openCount > 0) -- FullScreenHud (the Tavern Map) sets true, PanelFullScreen counts pages
end

local function plural(n, word)
	return n .. " " .. word .. (n == 1 and "" or "s")
end

-- "5h 12m", "42m" or "<1m": the wait until the next UTC day, when the next reward can be claimed.
function M.countdownText(secs)
	secs = math.max(0, math.floor(tonumber(secs) or 0))
	local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
	if h >= 1 then return h .. "h " .. m .. "m" end
	if m >= 1 then return m .. "m" end
	return "<1m"
end

function M.view(login, quests)
	login = type(login) == "table" and login or {}
	quests = type(quests) == "table" and quests or {}
	local streak = math.max(0, math.floor(tonumber(login.streak) or 0))
	local out = { streak = streak }
	out.streakText = streak >= 1 and ("Streak: " .. plural(streak, "day")) or "Streak: 0 days"
	out.streakShort = plural(streak, "day") -- the narrow column falls back to this when "Streak: N days" does not fit on one line

	-- Goal: the first unfinished quest, else all done, else nothing to show.
	local goal
	local rows = type(quests.quests) == "table" and quests.quests or {}
	for _, q in ipairs(rows) do
		if not q.done then goal = q break end
	end
	local doneN = 0
	for _, q in ipairs(rows) do if q.done then doneN = doneN + 1 end end
	out.goalShort = #rows > 0 and ("Goals " .. doneN .. "/" .. #rows) or "Goals soon" -- the short word the narrow strip shows at 14 px or more
	out.goalCount = #rows > 0 and (doneN .. "/" .. #rows) or ""
	if goal then
		out.progress = math.floor(tonumber(goal.progress) or 0)
		out.goal = math.max(1, math.floor(tonumber(goal.goal) or 1))
		out.goalDone = false
		out.goalText = tostring(goal.desc or goal.name or "Daily goal") .. " " .. out.progress .. "/" .. out.goal
	elseif #rows > 0 then
		out.goalDone = true
		out.progress, out.goal = 1, 1
		out.goalText = "Goals done"
	else
		out.goalDone = false
		out.progress, out.goal = 0, 1
		out.goalText = "Daily goals load soon"
	end

	-- Chest: today's login reward. Claimable once per UTC day.
	out.chest, out.chestText, out.pulse = "none", "Chest soon", false
	for _, r in ipairs(type(login.rewards) == "table" and login.rewards or {}) do
		if r.claimable then
			out.chest, out.chestText, out.rewardLabel, out.claimDay, out.pulse = "ready", "Claim reward", r.label, r.day, true
			break
		elseif r.today and r.claimed then
			out.chest, out.chestText, out.rewardLabel = "opened", "Claimed today", r.label
			if tonumber(login.secondsToNextDay) then
				out.chestText = "Next in " .. M.countdownText(login.secondsToNextDay)
			end
		end
	end
	return out
end

function M.rect(w, h)
	w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
	local sw = math.min(M.MAX_W, math.max(1, w - 2 * M.MARGIN))
	local sh = math.min(math.max(M.HEIGHT, M.MIN_TOUCH), h)
	return { x = math.floor((w - sw) / 2), y = math.max(0, h - sh - M.MARGIN), w = sw, h = sh }
end

-- The strip never covers the room cards of the Night map: given the bottom edge of the lowest card (screen px), it stays at the bottom
-- when that is clear, otherwise sits right under the cards if the whole strip still fits, otherwise there is no room (nil).
M.GAP = 8

-- Lowest bottom edge (y + h) of a list of { y =, h = } rects, nil when empty. The client feeds it the room panels AND their Select,
-- Skip and Target plates, because those hang below the panel.
function M.lowestBottom(rects)
	local bottom
	for _, r in ipairs(rects or {}) do
		local b = r.y + r.h
		if not bottom or b > bottom then bottom = b end
	end
	return bottom
end

-- true when rect r overlaps any rect in the list (touching edges do not count)
function M.overlapsAny(r, rects)
	for _, o in ipairs(rects or {}) do
		if r.x < o.x + o.w and o.x < r.x + r.w and r.y < o.y + o.h and o.y < r.y + r.h then return true end
	end
	return false
end

function M.rectBelow(w, h, cardsBottom)
	local r = M.rect(w, h)
	if not cardsBottom then return r end
	local gap = M.GAP
	if r.y >= cardsBottom + gap then return r end
	local y = math.floor(cardsBottom) + gap
	if y + r.h <= h - 2 then r.y = y; return r end
	return nil
end

-- On the main menu the strip stands in the bottom row to the RIGHT of the Deal Me In column: the tip plate (Engine/MenuLife) is on the
-- left, the sign column (340 px, centred) in the middle and All actions (220 x 56, 16 px from the corner) at the right, 16 px between
-- neighbours. Returns nil when the gap is narrower than MENU_MIN_W (small screens), then the strip is left out of the menu.
M.MENU_GAP, M.MENU_SIGN_HALF, M.MENU_ALL_W, M.MENU_MIN_W, M.MENU_MAX_W = 16, 240, 0, 360, 560 -- MENU_ALL_W 0: the All actions button is gone
function M.menuRect(w, h)
	w, h = math.floor(tonumber(w) or 0), math.floor(tonumber(h) or 0)
	local left = math.floor(w / 2) + M.MENU_SIGN_HALF + M.MENU_GAP
	local right = w - M.MENU_GAP - M.MENU_ALL_W
	local sw = math.min(M.MENU_MAX_W, right - left)
	if sw < M.MENU_MIN_W or h < 300 then return nil end
	local sh = math.max(M.HEIGHT, M.MIN_TOUCH)
	-- level with All actions: both end 16 px above the bottom edge
	return { x = left, y = h - M.MENU_GAP - sh, w = sw, h = sh }
end

-- The menu strip placed for a menu frame of w x h whose top left sits at dx, dy inside the GameUI (Studio's scale:WxH centres a smaller
-- menu frame): the same rect as menuRect, moved by the frame offset so it stays inside the frame.
function M.menuRectAt(w, h, dx, dy)
	local r = M.menuRect(w, h)
	if not r then return nil end
	return { x = r.x + math.floor((tonumber(dx) or 0) + 0.5), y = r.y + math.floor((tonumber(dy) or 0) + 0.5), w = r.w, h = r.h }
end

-- The Streak and Goal columns left of the chest, in strip pixels: the Streak column takes about a quarter of the strip (92 to 130 px), the Goal
-- column starts 8 px after it and ends 12 px before the chest plate, so neither word runs under the chest.
M.EDGE_X, M.PAD_X = 30, 14 -- the carved gold end is 30 px, the words start 14 px inside it so no letter touches the plate border
M.START_X, M.COL_GAP, M.GOAL_GAP = M.EDGE_X + M.PAD_X, 4, 8
M.LABEL_MIN, M.LABEL_MAX = 14, 16 -- the Streak and Goals words
M.TRACK_H, M.TRACK_Y, M.TRACK_RGB, M.FILL_RGB, M.PLATE_RGB = 6, 32, { 140, 112, 70 }, { 230, 184, 70 }, { 30, 22, 16 } -- progress bar: a light track on the dark plate, gold fill
function M.columns(strip)
	local c = M.chestRect(strip)
	local streakW = math.max(72, math.min(130, math.floor(strip.w * 0.19)))
	local goalX = M.START_X + streakW + M.COL_GAP
	return { streak = { x = M.START_X, w = streakW }, goalX = goalX, goalW = math.max(40, c.x - goalX - M.GOAL_GAP), chest = c }
end

function M.chestRect(strip)
	-- wide enough for "Next in 20h 39m" with CHEST_PAD clear on each side of the word
	local cw = math.max(M.MIN_TOUCH, math.min(M.CHEST_MAX_W, math.max(M.CHEST_MIN_W, math.floor(strip.w * 0.3))))
	local ch = math.max(M.MIN_TOUCH, strip.h - 4)
	return { x = strip.w - cw - 2, y = math.floor((strip.h - ch) / 2), w = cw, h = ch }
end

function M.reveal(calm, fast)
	if calm then return { open = 0, glow = 0 } end
	if fast then return { open = 0.15, glow = 0.3 } end
	return { open = 0.3, glow = 0.6 }
end

return M
