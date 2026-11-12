--[[
	Shared/Engine/Announcer.lua
	The pure rules for the centre of the screen: only ONE transient message is visible at a time (Client/Announcer.lua runs it). Tested in
	EngineTests ("Announcer"). Time is passed in, so the rules need no clock.

	A message: { id, kind, priority, duration, stateKey?, maxWait?, text? }
	    Round Complete (kind "round_complete") 3, True Wildcard and Legendary lock in 3, Night begins next 1, flavor lines 0.
	    A message with priority below 3 that waits longer than 2 s (maxWait) is DROPPED, and so is any waiting message whose stateKey no
	    longer matches the round state (the moment moved on). Priority 3 messages are never dropped for waiting: a Round Complete always
	    shows, after the one that is up.

	Announcer.new()
	a:submit(msg, now)         queue a message
	a:addFlavor(text)          merge a flavor line into the Round Complete that is up or queued (one small ink line under its total);
	                           false when there is none, then the caller submits it as a priority 0 message of its own
	a:setState(key)            the round state key; waiting messages made for another state are dropped on the next tick
	a:done(id, now)            the presenter finished early (a click closed the plate)
	a:tick(now)                list of { op = "hide" | "drop" | "show", msg, reason? } in the order to apply them
	a:current() / a:pendingCount() / a:isIdle()
	Announcer.GAP              0.25 s between two messages
]]

local Announcer = {}

Announcer.GAP = 0.25
Announcer.MAX_WAIT = 2.0
Announcer.NEVER_DROP_FROM = 3 -- priority at or above this is never dropped for waiting

function Announcer.new()
	local a = { cur = nil, queue = {}, gapUntil = 0, seq = 0, stateKey = nil }

	function a:submit(msg, now)
		self.seq = self.seq + 1
		local m = {}
		for k, v in pairs(msg) do m[k] = v end
		m.seq = self.seq
		m.queuedAt = now
		if m.maxWait == nil and (m.priority or 0) < Announcer.NEVER_DROP_FROM then m.maxWait = Announcer.MAX_WAIT end
		self.queue[#self.queue + 1] = m
		return m
	end

	function a:addFlavor(text)
		if self.cur and self.cur.kind == "round_complete" and not self.cur.flavor then
			self.cur.flavor = text
			return self.cur, true -- already on screen: the presenter adds the line
		end
		for _, m in ipairs(self.queue) do
			if m.kind == "round_complete" and not m.flavor then
				m.flavor = text
				return m, false
			end
		end
		return nil
	end

	function a:setState(key)
		self.stateKey = key
	end

	-- take a waiting message back (a presenter that stopped waiting for its turn); a message that is up ends at once
	function a:cancel(id, now)
		for i, m in ipairs(self.queue) do
			if m.id == id then
				table.remove(self.queue, i)
				return true
			end
		end
		if self.cur and self.cur.id == id then
			self.cur.endsAt = now
			return true
		end
		return false
	end

	function a:done(id, now)
		if self.cur and self.cur.id == id then
			self.cur.endsAt = now
		end
	end

	function a:tick(now)
		local ops = {}
		if self.cur and now >= (self.cur.endsAt or (self.cur.startedAt + (self.cur.duration or 2))) then
			ops[#ops + 1] = { op = "hide", msg = self.cur }
			self.cur = nil
			self.gapUntil = now + Announcer.GAP
		end
		-- drop what waited too long or belongs to a moment that is over
		local keep = {}
		for _, m in ipairs(self.queue) do
			local reason
			if m.maxWait and now - m.queuedAt > m.maxWait then
				reason = "waited"
			elseif m.stateKey ~= nil and self.stateKey ~= nil and m.stateKey ~= self.stateKey then
				reason = "stale"
			end
			if reason then
				ops[#ops + 1] = { op = "drop", msg = m, reason = reason }
			else
				keep[#keep + 1] = m
			end
		end
		self.queue = keep
		if not self.cur and #self.queue > 0 and now >= self.gapUntil then
			local best = 1
			for i = 2, #self.queue do
				local m, b = self.queue[i], self.queue[best]
				if (m.priority or 0) > (b.priority or 0) or ((m.priority or 0) == (b.priority or 0) and m.seq < b.seq) then best = i end
			end
			local m = table.remove(self.queue, best)
			m.startedAt = now
			m.endsAt = nil
			self.cur = m
			ops[#ops + 1] = { op = "show", msg = m }
		end
		return ops
	end

	function a:current() return self.cur end
	function a:pendingCount() return #self.queue end
	function a:isIdle() return self.cur == nil and #self.queue == 0 end

	return a
end

return Announcer
