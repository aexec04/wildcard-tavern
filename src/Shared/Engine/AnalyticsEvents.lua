--[[
	AnalyticsEvents.lua
	Launch analytics: the first run funnel, Tips economy events and two custom events, as data plus one small
	logger. Pure Lua: the Roblox service is injected, so nothing here touches Roblox APIs and tests run silent.

	Rules:
	  * Every service call is wrapped in pcall. A failure never reaches gameplay.
	  * A funnel step is sent once per player session (a fresh funnel session id per visit).
	  * Economy events are rate limited per player (MAX_ECONOMY per minute); a hand never logs by itself.
	  * Only fixed ids go out: step names, source and sink names, a night number, a score, a cause and a boss id.
	    No names, no free text. Unknown values are dropped, never sent.
	  * Off unless `enabled` (the server passes false in Studio unless a debug flag is on). When off, nothing is
	    sent; `print` still lists each event name once so Studio shows what would fire.
]]

local AnalyticsEvents = {}

AnalyticsEvents.FUNNEL_NAME = "LaunchFunnel"

-- Funnel order. The index is the step number sent to Roblox.
AnalyticsEvents.Steps = {
	"menu_opened", "run_started", "first_hand_played", "first_round_cleared",
	"first_night_cleared", "first_patron_bought", "second_run_started",
}

AnalyticsEvents.EarnSources = { "round_clear", "events", "selling" }
AnalyticsEvents.SpendSinks = { "shop_patron", "shop_pack", "reroll" }
AnalyticsEvents.Causes = { "boss", "hands", "quit", "won" }
AnalyticsEvents.CustomEvents = { "run_ended", "boss_lost" }
AnalyticsEvents.CURRENCY = "Tips"
AnalyticsEvents.MAX_ECONOMY = 30 -- economy events per player per minute

local function setOf(list)
	local out = {}
	for i, v in ipairs(list) do out[v] = i end
	return out
end
local STEP, SOURCE, SINK, CAUSE = setOf(AnalyticsEvents.Steps), setOf(AnalyticsEvents.EarnSources),
	setOf(AnalyticsEvents.SpendSinks), setOf(AnalyticsEvents.Causes)

function AnalyticsEvents.stepIndex(id) return STEP[id] end
function AnalyticsEvents.isSource(id) return SOURCE[id] ~= nil end
function AnalyticsEvents.isSink(id) return SINK[id] ~= nil end
function AnalyticsEvents.isCause(id) return CAUSE[id] ~= nil end

-- Whole non negative number or nil.
local function whole(n)
	if type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then return nil end
	return math.floor(n)
end

-- A boss id is a short lowercase word with underscores; anything else is dropped.
function AnalyticsEvents.cleanId(id)
	if type(id) ~= "string" or #id == 0 or #id > 40 or not id:match("^[a-z0-9_]+$") then return nil end
	return id
end

-- Payload builders (pure, tested). Return nil when the input is not valid.
function AnalyticsEvents.economyPayload(kind, name, amount, balance)
	local a, b = whole(amount), whole(balance)
	if not a or a == 0 or not b then return nil end
	if kind == "earn" and SOURCE[name] then
		return { flow = "Source", currency = AnalyticsEvents.CURRENCY, balance = b, amount = a, transaction = name }
	elseif kind == "spend" and SINK[name] then
		return { flow = "Sink", currency = AnalyticsEvents.CURRENCY, balance = b, amount = a, transaction = name }
	end
	return nil
end

function AnalyticsEvents.runEndedPayload(night, score, cause)
	local n, s = whole(night), whole(score)
	if not n or not s or not CAUSE[cause] then return nil end
	return { name = "run_ended", value = s, fields = { night = tostring(n), cause = cause } }
end

function AnalyticsEvents.bossLostPayload(bossId)
	local id = AnalyticsEvents.cleanId(bossId)
	if not id then return nil end
	return { name = "boss_lost", value = 1, fields = { boss = id } }
end

local function enumOf(kind, name)
	local ok, v = pcall(function() return Enum[kind][name] end)
	return (ok and v) or name
end

-- opts: service (AnalyticsService or fake), enabled (bool), print (function or nil), now (function, default os.time)
function AnalyticsEvents.new(opts)
	opts = opts or {}
	local self = { sent = 0 }
	local players = {} -- [player] = { session, steps, runs, windowStart, count }
	local printed = {}

	local function slot(player)
		local s = players[player]
		if not s then
			s = { steps = {}, runs = 0, windowStart = 0, count = 0 }
			players[player] = s
		end
		return s
	end

	local function note(name)
		if opts.print and not printed[name] then
			printed[name] = true
			pcall(opts.print, "[Analytics] " .. name .. (opts.enabled and "" or " (not sent)"))
		end
	end

	local function call(fn)
		if not opts.enabled or not opts.service then return false end
		local ok = pcall(fn)
		if ok then self.sent = self.sent + 1 end
		return ok
	end

	function self.step(player, stepId)
		local index = STEP[stepId]
		if not index or not player then return false end
		local s = slot(player)
		if s.steps[stepId] then return false end
		s.steps[stepId] = true
		s.session = s.session or (tostring(player.UserId or 0) .. "-" .. tostring((opts.now or os.time)()))
		note("step_" .. stepId)
		local sid = s.session
		call(function() opts.service:LogFunnelStepEvent(player, AnalyticsEvents.FUNNEL_NAME, sid, index, stepId) end)
		return true
	end

	-- Counts runs this session: the first sends run_started, the second second_run_started.
	function self.runStarted(player)
		if not player then return end
		local s = slot(player)
		s.runs = s.runs + 1
		if s.runs == 1 then self.step(player, "run_started") elseif s.runs == 2 then self.step(player, "second_run_started") end
	end

	local function allowEconomy(s)
		local t = (opts.now or os.time)()
		if t - s.windowStart >= 60 then s.windowStart, s.count = t, 0 end
		if s.count >= AnalyticsEvents.MAX_ECONOMY then return false end
		s.count = s.count + 1
		return true
	end

	local function economy(player, kind, name, amount, balance)
		local p = AnalyticsEvents.economyPayload(kind, name, amount, balance)
		if not p or not player or not allowEconomy(slot(player)) then return false end
		note("economy_" .. kind .. "_" .. name)
		return call(function()
			opts.service:LogEconomyEvent(player, enumOf("AnalyticsEconomyFlowType", p.flow), p.currency, p.balance,
				p.amount, enumOf("AnalyticsEconomyTransactionType", "Gameplay"), p.transaction)
		end)
	end
	function self.earned(player, source, amount, balance) return economy(player, "earn", source, amount, balance) end
	function self.spent(player, sink, amount, balance) return economy(player, "spend", sink, amount, balance) end

	local function custom(player, p)
		if not p or not player then return false end
		note(p.name)
		return call(function() opts.service:LogCustomEvent(player, p.name, p.value, p.fields) end)
	end
	function self.runEnded(player, night, score, cause)
		return custom(player, AnalyticsEvents.runEndedPayload(night, score, cause))
	end
	function self.bossLost(player, bossId) return custom(player, AnalyticsEvents.bossLostPayload(bossId)) end

	function self.forget(player) players[player] = nil end
	return self
end

return AnalyticsEvents
