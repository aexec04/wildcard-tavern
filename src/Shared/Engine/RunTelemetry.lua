--[[
	RunTelemetry.lua
	Post launch tuning data for Creator Analytics, kept compact on purpose. Pure Lua, no Roblox APIs (Analytics.lua sends).

	Per RUN the server keeps one small aggregator in memory (new, recordPatronBought, recordBoss) and flushes it ONCE when
	the run ends (flush), so a long run costs a handful of events instead of one per click:
	  patron_bought     value = times bought     fields: patron, stake, night
	  patron_end        value = 1                fields: patron, won   (one per Patron owned at run end, at most 8)
	  boss_result       value = hands used       fields: boss, won     (at most 8 per run)
	  run_quit          value = Night            fields: phase, stake  (a player left a run that was still going)
	  store_opened / store_prompt / store_bought    value = 1          fields: item
	  run_end, quest_done, rank_up already exist in Analytics.lua.

	Budget: every player may send at most BUDGET_PER_HOUR events per rolling hour (allow). A run flush that does not fit
	is cut to what fits, most important events first (boss results, Patrons owned, Patrons bought). Nothing here can
	block gameplay: the server wraps every call in pcall.
]]

local RunTelemetry = {}

RunTelemetry.BUDGET_PER_HOUR = 120
RunTelemetry.HOUR = 3600
RunTelemetry.MAX_BOSSES = 8
RunTelemetry.MAX_PATRONS = 8
RunTelemetry.MAX_BOUGHT_KEYS = 40

function RunTelemetry.new()
	return { bought = {}, boughtKeys = 0, bosses = {}, flushed = false }
end

-- A Patron bought this run, counted by (id, stake, Night).
function RunTelemetry.recordPatronBought(agg, patronId, stake, night)
	if type(patronId) ~= "string" or #patronId > 40 then
		return false
	end
	local key = patronId .. "|" .. tostring(math.floor(tonumber(stake) or 1)) .. "|" .. tostring(math.floor(tonumber(night) or 1))
	if not agg.bought[key] then
		if agg.boughtKeys >= RunTelemetry.MAX_BOUGHT_KEYS then
			return false
		end
		agg.boughtKeys = agg.boughtKeys + 1
		agg.bought[key] = { patron = patronId, stake = math.floor(tonumber(stake) or 1), night = math.floor(tonumber(night) or 1), count = 0 }
	end
	agg.bought[key].count = agg.bought[key].count + 1
	return true
end

-- A Boss Round ended (won or lost) using `handsUsed` hands. Each (boss, Night) is recorded once.
function RunTelemetry.recordBoss(agg, bossId, won, handsUsed, night)
	if type(bossId) ~= "string" or #bossId > 40 or #agg.bosses >= RunTelemetry.MAX_BOSSES then
		return false
	end
	for _, b in ipairs(agg.bosses) do
		if b.boss == bossId and b.night == night then
			return false
		end
	end
	agg.bosses[#agg.bosses + 1] = { boss = bossId, won = won == true, hands = math.max(0, math.floor(tonumber(handsUsed) or 0)), night = night }
	return true
end

-- Spends budget for `n` events from player's rolling hour. `budget` = { [userId] = { { t, n }, ... } }. Returns how many
-- of the n events may be sent now (0 to n).
function RunTelemetry.allow(budget, userId, now, n)
	n = math.max(0, math.floor(tonumber(n) or 0))
	local list = budget[userId]
	if not list then
		list = {}
		budget[userId] = list
	end
	local used = 0
	for i = #list, 1, -1 do
		if now - list[i].t >= RunTelemetry.HOUR then
			table.remove(list, i)
		else
			used = used + list[i].n
		end
	end
	local room = math.max(0, RunTelemetry.BUDGET_PER_HOUR - used)
	local granted = math.min(n, room)
	if granted > 0 then
		list[#list + 1] = { t = now, n = granted }
	end
	return granted
end

function RunTelemetry.forget(budget, userId)
	budget[userId] = nil
end

-- The events of one finished run, most important first: { { name, value, fields } }. Flushes only once per aggregator.
-- `ownedIds` = Patron ids at run end, `won` = the run was won.
function RunTelemetry.flush(agg, ownedIds, won)
	if agg.flushed then
		return {}
	end
	agg.flushed = true
	local events = {}
	for _, b in ipairs(agg.bosses) do
		events[#events + 1] = { name = "boss_result", value = b.hands, fields = { boss = b.boss, won = b.won and "yes" or "no", night = b.night } }
	end
	for i, id in ipairs(ownedIds or {}) do
		if i > RunTelemetry.MAX_PATRONS then break end
		events[#events + 1] = { name = "patron_end", value = 1, fields = { patron = id, won = won and "yes" or "no" } }
	end
	local keys = {}
	for key in pairs(agg.bought) do keys[#keys + 1] = key end
	table.sort(keys) -- stable order
	for _, key in ipairs(keys) do
		local b = agg.bought[key]
		events[#events + 1] = { name = "patron_bought", value = b.count, fields = { patron = b.patron, stake = b.stake, night = b.night } }
	end
	return events
end

-- Applies the hourly budget to a list of events and hands each allowed one to send(event). Returns the number sent.
function RunTelemetry.dispatch(events, budget, userId, now, send)
	local allowed = RunTelemetry.allow(budget, userId, now, #events)
	local sent = 0
	for i = 1, allowed do
		local ok, result = pcall(send, events[i])
		if ok and result ~= false then sent = sent + 1 end -- a send that answers false (no service) is not counted
	end
	return sent
end

return RunTelemetry
