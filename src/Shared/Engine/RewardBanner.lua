--[[
	Shared/Engine/RewardBanner.lua
	Timing for the Round Complete banner (Client/RoundRewardBanner.lua): a small non-blocking plate that counts the Tips up, holds, and
	fades out by itself. Pure Lua, tested. The economy is untouched: the amounts come from Engine/RoundPayout.

	RewardBanner.plan(animSpeed, calm)     { hold, fadeIn, fadeOut, countUp, stagger, animated }
	    normal: holds 2.2 s; fast animation: 1.2 s; calm mode (Reduce screen shake): the plate just appears and goes, no fades, no count
	RewardBanner.phaseAt(plan, t, dismissedAt)   "in" | "hold" | "out" | "done" and an alpha (1 = fully shown)
	RewardBanner.shownLines(plan, count, t)      how many of the payout lines are revealed at time t
	RewardBanner.countAt(plan, total, t)         the Total counted up to its value (an integer)
	RewardBanner.canDismiss(plan, t)             a click or key press only counts after a short grace period
]]

local RewardBanner = {}

RewardBanner.HOLD = 0.65 -- with the 0.2 s fade in and 0.35 s fade out the toast is gone after 1.2 s (the Counter summary plate keeps the facts)
RewardBanner.HOLD_FAST = 0.4
RewardBanner.GRACE = 0.4 -- the click or key that played the winning hand must not close the banner at once

function RewardBanner.plan(animSpeed, calm)
	if calm then
		return { hold = RewardBanner.HOLD, fadeIn = 0, fadeOut = 0, countUp = 0, stagger = 0, animated = false }
	end
	if animSpeed == "fast" then
		return { hold = RewardBanner.HOLD_FAST, fadeIn = 0.1, fadeOut = 0.15, countUp = 0.25, stagger = 0.1, animated = true }
	end
	return { hold = RewardBanner.HOLD, fadeIn = 0.2, fadeOut = 0.35, countUp = 0.6, stagger = 0.25, animated = true }
end

-- t = seconds since the banner opened; dismissedAt = the time of an early click or key press (nil when none)
function RewardBanner.phaseAt(plan, t, dismissedAt)
	local outStart = plan.fadeIn + plan.hold
	if dismissedAt and dismissedAt < outStart then outStart = math.max(0, dismissedAt) end
	if t < 0 then return "in", 0 end
	if t < outStart then
		if plan.fadeIn > 0 and t < plan.fadeIn then return "in", t / plan.fadeIn end
		return "hold", 1
	end
	if plan.fadeOut <= 0 then return "done", 0 end
	local k = (t - outStart) / plan.fadeOut
	if k >= 1 then return "done", 0 end
	return "out", 1 - k
end

function RewardBanner.shownLines(plan, count, t)
	if plan.stagger <= 0 then return count end
	local n = math.floor(math.max(0, t) / plan.stagger) + 1
	return math.min(count, n)
end

function RewardBanner.countAt(plan, total, t)
	total = math.max(0, math.floor(tonumber(total) or 0))
	if plan.countUp <= 0 or t >= plan.countUp then return total end
	return math.floor(total * math.max(0, t) / plan.countUp)
end

function RewardBanner.canDismiss(_plan, t)
	return t >= RewardBanner.GRACE
end

-- Where the plate stands: top right of the scene, 300 px wide (narrower on small screens), its right edge clear of the Tips box and
-- the quest toast column (about 18 percent of the width, 120 to 340 px). Returns the right edge x and the width.
function RewardBanner.spot(screenW)
	local w = math.max(1, tonumber(screenW) or 1920)
	local width = math.min(300, math.floor(w * 0.30))
	local margin = math.max(120, math.min(340, math.floor(w * 0.18)))
	return { right = w - margin, width = width }
end

-- The merged Round Complete plate (painted, the same piece and size as the Counter summary plate): centred under the top bar, never over the
-- summary plate on the right (its left edge minus a 12 px gap caps the right edge) or the gear. `summary` is ShopSummary.rect(w, h).
RewardBanner.PLATE_W, RewardBanner.PLATE_H, RewardBanner.PLATE_TOP, RewardBanner.SUMMARY_GAP = 300, 124, 74, 12
function RewardBanner.place(screenW, summary)
	local w = math.max(1, tonumber(screenW) or 1920)
	local pw = math.min(RewardBanner.PLATE_W, math.floor(w * 0.30))
	local x = math.floor((w - pw) / 2)
	if summary and summary.y < RewardBanner.PLATE_TOP + RewardBanner.PLATE_H and x + pw > summary.x - RewardBanner.SUMMARY_GAP then x = summary.x - RewardBanner.SUMMARY_GAP - pw end
	return { x = math.max(0, x), y = RewardBanner.PLATE_TOP, w = pw, h = RewardBanner.PLATE_H }
end

-- Second line of the plate, so a stale "Target cleared" is never missed; the score joins it when the caller knows it
function RewardBanner.clearedLine(score, target)
	local sc = tonumber(score)
	if sc then return "Target cleared  " .. string.format("%d", math.floor(sc)) .. (tonumber(target) and (" of " .. string.format("%d", math.floor(target))) or "") end
	return "Target cleared"
end

return RewardBanner
