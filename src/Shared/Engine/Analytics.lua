--[[
	Analytics.lua
	A thin wrapper over Roblox AnalyticsService (funnels and custom events). Server side only in practice, but it
	loads anywhere: outside Roblox (plain Lua tests) there is no service and every call quietly does nothing.

	Rules:
	  * Every call is wrapped in pcall. An analytics error can never block or break gameplay.
	  * A funnel step is sent once per player for life (Engine/Funnel.markIfNew + profile.funnelSeen).
	  * Custom events are small and numeric: run_start, run_end, quest_done, rank_up.
	  * No personal data: only the stake, the road (region id), the Night and whether the run was won.

	Tests inject a fake service with Analytics.setService(fake).
]]

local Funnel = require(script.Parent.Funnel)

local Analytics = {}

local service
local resolved = false

local function getService()
	if not resolved then
		resolved = true
		local ok, svc = pcall(function()
			return game:GetService("AnalyticsService")
		end)
		service = ok and svc or nil
	end
	return service
end

-- For tests: replace the service (pass nil to switch everything off).
function Analytics.setService(fake)
	service = fake
	resolved = true
end

local function safe(fn)
	local ok, err = pcall(fn)
	if not ok then
		pcall(warn, "[Analytics] " .. tostring(err))
	end
	return ok
end

local function fieldsOf(fields)
	local out = {}
	for key, value in pairs(fields or {}) do
		local t = type(value)
		if t == "string" or t == "number" or t == "boolean" then
			out[tostring(key)] = t == "string" and value or tostring(value)
		end
	end
	return out
end

-- Logs funnel step `stepId` for this player once (new for the profile). `sessionId` identifies this visit.
-- Returns true when something was sent.
function Analytics.step(player, profile, stepId, sessionId)
	if not profile then
		return false
	end
	local index = Funnel.markIfNew(profile, stepId)
	if not index then
		return false
	end
	local svc = getService()
	if not svc then
		return true -- counted as seen, nothing to send outside Roblox
	end
	safe(function()
		svc:LogFunnelStepEvent(player, Funnel.NAME, sessionId or "session", index, stepId)
	end)
	return true
end

-- Logs a custom event with a numeric value and a few string fields.
function Analytics.event(player, name, value, fields)
	local svc = getService()
	if not svc then
		return false
	end
	return safe(function()
		svc:LogCustomEvent(player, name, tonumber(value) or 1, fieldsOf(fields))
	end)
end

function Analytics.runStart(player, stake, mode)
	return Analytics.event(player, "run_start", 1, { stake = stake or 1, mode = mode or "normal" })
end

function Analytics.runEnd(player, stake, road, night, won)
	return Analytics.event(player, "run_end", night or 0, { stake = stake or 1, road = road or "unknown", won = won and "yes" or "no" })
end

function Analytics.questDone(player, questId)
	return Analytics.event(player, "quest_done", 1, { quest = questId })
end

function Analytics.rankUp(player, rank)
	return Analytics.event(player, "rank_up", rank, {})
end

return Analytics
