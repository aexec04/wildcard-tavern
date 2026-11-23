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

function M.visible(phase)
	return phase == "roundSelect" -- Run Over hides it: the faded strip showed through under the panel
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
	out.streakText = streak >= 1 and ("Streak: " .. plural(streak, "day")) or "Streak: starts today"

	-- Goal: the first unfinished quest, else all done, else nothing to show.
	local goal
	local rows = type(quests.quests) == "table" and quests.quests or {}
	for _, q in ipairs(rows) do
		if not q.done then goal = q break end
	end
	if goal then
		out.progress = math.floor(tonumber(goal.progress) or 0)
		out.goal = math.max(1, math.floor(tonumber(goal.goal) or 1))
		out.goalDone = false
		out.goalText = tostring(goal.desc or goal.name or "Daily goal") .. " " .. out.progress .. "/" .. out.goal
	elseif #rows > 0 then
		out.goalDone = true
		out.progress, out.goal = 1, 1
		out.goalText = "All daily goals done"
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
function M.rectBelow(w, h, cardsBottom)
	local r = M.rect(w, h)
	if not cardsBottom then return r end
	local gap = 4
	if r.y >= cardsBottom + gap then return r end
	local y = math.floor(cardsBottom) + gap
	if y + r.h <= h - 2 then r.y = y; return r end
	return nil
end

-- On the main menu the strip stands in the bottom row to the RIGHT of the Deal Me In column: the tip plate (Engine/MenuLife) is on the
-- left, the sign column (340 px, centred) in the middle and All actions (220 x 56, 16 px from the corner) at the right, 16 px between
-- neighbours. Returns nil when the gap is narrower than MENU_MIN_W (small screens), then the strip is left out of the menu.
M.MENU_GAP, M.MENU_SIGN_HALF, M.MENU_ALL_W, M.MENU_MIN_W, M.MENU_MAX_W = 16, 170, 0, 340, 560 -- MENU_ALL_W 0: the All actions button is gone
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

function M.chestRect(strip)
	local cw = math.max(M.MIN_TOUCH, math.min(150, math.floor(strip.w * 0.28)))
	local ch = math.max(M.MIN_TOUCH, strip.h - 4)
	return { x = strip.w - cw - 2, y = math.floor((strip.h - ch) / 2), w = cw, h = ch }
end

function M.reveal(calm, fast)
	if calm then return { open = 0, glow = 0 } end
	if fast then return { open = 0.15, glow = 0.3 } end
	return { open = 0.3, glow = 0.6 }
end

return M
