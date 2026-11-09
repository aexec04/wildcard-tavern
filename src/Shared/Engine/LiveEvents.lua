--[[
	LiveEvents.lua
	Live ops as DATA: a table of timed events (UTC dates, both days included). The menu shows a News banner for the
	active event and a small News panel lists current and upcoming ones. Pure Lua, no Roblox APIs.

	An event never changes a fair board: Daily, Weekly and Seed runs play exactly the same rules during any event
	(the daily label below is only text beside the date; seeds, rules and boards are untouched). What an event may do:
	  modifier = { kind = "xpMultiplier", value = 2 }    Tavern Rank XP and quest XP are multiplied (account progress only)
	  modifier = { kind = "dailyLabel", text = "Harvest Week" }   a themed name shown beside the Daily date
	  modifier = { kind = "none" }                       a plain announcement with rewards
	  rewards = { { kind, id|amount } }                  claimed once per player while the event runs:
	                                                     title (Achievements id), cardBack, set, tips (banked for the next run)

	TO ADD AN EVENT: append one entry to LiveEvents.Definitions below with a unique id, name, icon, blurb,
	startDate and endDate ("YYYY-MM-DD", UTC), a modifier and optional rewards. Nothing else needs to change; a test
	checks the dates, ids and reward ids. See claude/ROADMAP.md ("Adding a live event in 5 lines").
]]

local TavernRank = require(script.Parent.TavernRank)

local LiveEvents = {}

LiveEvents.UPCOMING_DAYS = 14 -- how far ahead the News panel shows
LiveEvents.MAX_XP_MULTIPLIER = 3

-- EDIT ME. Dates are UTC and both days count.
LiveEvents.Definitions = {
	{
		id = "lantern_weekend", name = "Lantern Weekend", icon = "🏮", bannerKey = "news_lantern_weekend",
		blurb = "Double Tavern Rank XP all weekend.",
		startDate = "2026-11-13", endDate = "2026-11-15",
		modifier = { kind = "xpMultiplier", value = 2 },
	},
	{
		id = "harvest_week", name = "Harvest Week", icon = "🌾", bannerKey = "news_harvest_week",
		blurb = "The Daily Challenge is dressed for harvest. Same rules, same fair board.",
		startDate = "2026-11-16", endDate = "2026-11-22",
		modifier = { kind = "dailyLabel", text = "Harvest Week" },
	},
	{
		id = "feast_week", name = "The Founders' Feast", icon = "🍲", bannerKey = "news_feast_week",
		blurb = "Join the feast for a limited title and a card back.",
		startDate = "2026-11-25", endDate = "2026-12-02",
		modifier = { kind = "none" },
		rewards = { { kind = "title", id = "feast_guest" }, { kind = "cardBack", id = "kitchen_checks" }, { kind = "tips", amount = 6 } },
	},
}

-- ===== dates =====

-- Days since 1970-01-01 for a civil date (proleptic Gregorian, no time zones: pure arithmetic).
local function daysFromCivil(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = (y >= 0 and y or y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

-- "YYYY-MM-DD" -> UTC day number (the same numbering as LoginStreak.dayNumber), or nil for a bad date.
function LiveEvents.dayNumberOf(dateText)
	if type(dateText) ~= "string" then
		return nil
	end
	local y, m, d = dateText:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y or m < 1 or m > 12 or d < 1 or d > 31 then
		return nil
	end
	local day = daysFromCivil(y, m, d)
	-- reject a date that rolled over (2026-02-31)
	local back = daysFromCivil(y, m, 1)
	local nextMonth = m == 12 and daysFromCivil(y + 1, 1, 1) or daysFromCivil(y, m + 1, 1)
	if day >= nextMonth or day < back then
		return nil
	end
	return day
end

local function windowOf(event)
	return LiveEvents.dayNumberOf(event.startDate), LiveEvents.dayNumberOf(event.endDate)
end

function LiveEvents.getById(id)
	for _, event in ipairs(LiveEvents.Definitions) do
		if event.id == id then
			return event
		end
	end
	return nil
end

function LiveEvents.isActive(event, day)
	local first, last = windowOf(event)
	return first ~= nil and last ~= nil and day >= first and day <= last
end

-- Events running on `day`, in table order.
function LiveEvents.active(day)
	local list = {}
	for _, event in ipairs(LiveEvents.Definitions) do
		if LiveEvents.isActive(event, day) then
			list[#list + 1] = event
		end
	end
	return list
end

-- Events that start after `day` within `withinDays`, soonest first.
function LiveEvents.upcoming(day, withinDays)
	withinDays = withinDays or LiveEvents.UPCOMING_DAYS
	local list = {}
	for _, event in ipairs(LiveEvents.Definitions) do
		local first = windowOf(event)
		if first and first > day and first - day <= withinDays then
			list[#list + 1] = event
		end
	end
	table.sort(list, function(a, b) return windowOf(a) < windowOf(b) end)
	return list
end

-- ===== modifiers =====

-- Account XP multiplier on `day`: the best active xpMultiplier, 1 when none, never above MAX_XP_MULTIPLIER.
function LiveEvents.xpMultiplier(day)
	local best = 1
	for _, event in ipairs(LiveEvents.active(day)) do
		local m = event.modifier
		if m and m.kind == "xpMultiplier" and type(m.value) == "number" and m.value > best then
			best = m.value
		end
	end
	return math.min(best, LiveEvents.MAX_XP_MULTIPLIER)
end

-- Themed text beside the Daily date, or nil. Text only: seeds, rules and boards never change.
function LiveEvents.dailyLabel(day)
	for _, event in ipairs(LiveEvents.active(day)) do
		local m = event.modifier
		if m and m.kind == "dailyLabel" and type(m.text) == "string" then
			return m.text
		end
	end
	return nil
end

-- ===== rewards =====

function LiveEvents.rewardText(reward, lookup)
	lookup = lookup or {}
	if reward.kind == "title" then
		return "Title: " .. ((lookup.titleName and lookup.titleName(reward.id)) or reward.id)
	elseif reward.kind == "cardBack" then
		return "Card back: " .. ((lookup.cardBackName and lookup.cardBackName(reward.id)) or reward.id)
	elseif reward.kind == "set" then
		return "Card Set: " .. ((lookup.setName and lookup.setName(reward.id)) or reward.id)
	elseif reward.kind == "tips" then
		return "+" .. tostring(reward.amount) .. " Tips next run"
	end
	return ""
end

-- Claims an event's rewards once, while the event is running. Returns ok, result:
--   ok true:  result = { event, texts = { "Title: ...", ... } }
--   ok false: result = a short reason ("Not running.", "Already claimed.", "Nothing to claim.")
function LiveEvents.claim(profile, eventId, day, lookup)
	local event = LiveEvents.getById(eventId)
	if not event or not LiveEvents.isActive(event, day) then
		return false, "Not running."
	end
	if not event.rewards or #event.rewards == 0 then
		return false, "Nothing to claim."
	end
	profile.liveEventClaims = profile.liveEventClaims or {}
	if profile.liveEventClaims[eventId] then
		return false, "Already claimed."
	end
	local texts = {}
	for _, reward in ipairs(event.rewards) do
		if reward.kind == "title" then
			profile.rewardTitleIds = profile.rewardTitleIds or {}
			profile.rewardTitleIds[reward.id] = true
		elseif reward.kind == "cardBack" then
			profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
			profile.unlockedCardBackIds[reward.id] = true
		elseif reward.kind == "set" then
			profile.ownedSetIds = profile.ownedSetIds or {}
			profile.ownedSetIds[reward.id] = true
		elseif reward.kind == "tips" then
			profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + reward.amount)
		end
		texts[#texts + 1] = LiveEvents.rewardText(reward, lookup)
	end
	profile.liveEventClaims[eventId] = true
	return true, { event = event, texts = texts }
end

-- ===== what the client draws =====

local function daysLeft(event, day)
	local _, last = windowOf(event)
	return last and (last - day + 1) or 0
end

-- { banner = row|nil, active = { row }, upcoming = { row } }. A row = { id, name, icon, bannerKey, blurb, daysLeft|startsIn,
-- claimable, claimed, rewards = { text } }
function LiveEvents.view(profile, day, lookup)
	local claims = profile.liveEventClaims or {}
	local active, upcoming = {}, {}
	for _, event in ipairs(LiveEvents.active(day)) do
		local texts = {}
		for _, reward in ipairs(event.rewards or {}) do
			texts[#texts + 1] = LiveEvents.rewardText(reward, lookup)
		end
		active[#active + 1] = {
			id = event.id, name = event.name, icon = event.icon, bannerKey = event.bannerKey, blurb = event.blurb,
			daysLeft = daysLeft(event, day), hasRewards = #texts > 0, claimed = claims[event.id] == true,
			claimable = #texts > 0 and not claims[event.id], rewards = texts,
		}
	end
	for _, event in ipairs(LiveEvents.upcoming(day)) do
		local first = windowOf(event)
		upcoming[#upcoming + 1] = { id = event.id, name = event.name, icon = event.icon, blurb = event.blurb, startsIn = first - day }
	end
	return { banner = active[1], active = active, upcoming = upcoming }
end

-- Cleans saved sets: only known event ids survive (content can be renamed freely).
function LiveEvents.cleanSaved(raw)
	local out = {}
	if type(raw) == "table" then
		for id, flag in pairs(raw) do
			if flag == true and type(id) == "string" and LiveEvents.getById(id) then
				out[id] = true
			end
		end
	end
	return out
end

-- Checks the table for mistakes (used by a test): returns a list of problem strings, empty when fine.
function LiveEvents.validate()
	local problems = {}
	local seen = {}
	for i, event in ipairs(LiveEvents.Definitions) do
		local where = "event " .. tostring(event.id or i)
		if type(event.id) ~= "string" or event.id == "" or seen[event.id] then
			problems[#problems + 1] = where .. ": id missing or repeated"
		end
		seen[event.id or i] = true
		for _, field in ipairs({ "name", "icon", "blurb" }) do
			if type(event[field]) ~= "string" or event[field] == "" then
				problems[#problems + 1] = where .. ": " .. field .. " missing"
			end
		end
		local first, last = windowOf(event)
		if not first or not last then
			problems[#problems + 1] = where .. ": bad date"
		elseif last < first then
			problems[#problems + 1] = where .. ": ends before it starts"
		end
		local m = event.modifier
		if type(m) ~= "table" or (m.kind ~= "xpMultiplier" and m.kind ~= "dailyLabel" and m.kind ~= "none") then
			problems[#problems + 1] = where .. ": modifier kind"
		elseif m.kind == "xpMultiplier" and not (type(m.value) == "number" and m.value >= 1 and m.value <= LiveEvents.MAX_XP_MULTIPLIER) then
			problems[#problems + 1] = where .. ": xpMultiplier value"
		elseif m.kind == "dailyLabel" and type(m.text) ~= "string" then
			problems[#problems + 1] = where .. ": dailyLabel text"
		end
	end
	return problems
end

return LiveEvents
