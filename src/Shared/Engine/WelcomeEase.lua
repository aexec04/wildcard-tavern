--[[
	WelcomeEase.lua
	A gentler start for new profiles: for the first few normal runs, Night 1 and Night 2 targets are a bit lower, and a
	run that ends on Night 1 banks one extra Tip bonus for the next run. Server authoritative, never on Daily, Weekly,
	Seed, Boss Rush, Quick or challenge runs (so every shared board stays fair). The counter is saved with the profile.
]]

local WelcomeEase = {}

WelcomeEase.DATA = {
	runs = 3, -- eased runs per profile
	lastNight = 2, -- Nights 1 and 2 are eased
	multiplier = 0.85, -- 15 percent lower
	roundTo = 5, -- targets land on a multiple of this
	nightOneLossTips = 5, -- extra Tips banked when an eased run ends on Night 1
}
WelcomeEase.LINE = "Welcome bonus: target eased for your first runs"

-- true when this profile's next run is eased. normalRun is false for every seeded, Rush, Quick or challenge run.
function WelcomeEase.eligible(profile, normalRun)
	if normalRun ~= true or type(profile) ~= "table" then return false end
	local used = profile.easeRunsUsed
	return type(used) == "number" and used < WelcomeEase.DATA.runs
end

-- Saved counter. A save with no counter that already got past Night 1 counts as done; a fresh one starts at 0.
function WelcomeEase.cleanSaved(raw, bestNightReached)
	if type(raw) == "number" and raw == raw then
		return math.max(0, math.min(WelcomeEase.DATA.runs, math.floor(raw)))
	end
	if type(bestNightReached) == "number" and bestNightReached >= 2 then
		return WelcomeEase.DATA.runs
	end
	return 0
end

-- Count one eased run (call when an eased run starts). Returns true when the profile changed.
function WelcomeEase.recordRun(profile)
	if type(profile) ~= "table" then return false end
	local used = profile.easeRunsUsed
	if type(used) ~= "number" or used >= WelcomeEase.DATA.runs then return false end
	profile.easeRunsUsed = used + 1
	return true
end

-- The eased target for a night (unchanged after lastNight), rounded to a clean number, never below 1.
function WelcomeEase.scale(target, night)
	local d = WelcomeEase.DATA
	if type(target) ~= "number" or type(night) ~= "number" or night > d.lastNight then return target end
	local eased = math.floor(target * d.multiplier / d.roundTo + 0.5) * d.roundTo
	return math.max(1, math.min(target, eased))
end

return WelcomeEase
