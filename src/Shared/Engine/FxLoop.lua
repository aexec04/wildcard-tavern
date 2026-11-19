--[[
	Shared/Engine/FxLoop.lua
	Pure, tested registry behind Client/FxLoop: every looping effect (cat breath, room lights, confetti, boss pulse, card flights)
	registers one function here and a single Heartbeat connection steps them all, so there is no per element RenderStepped.

	local hub = FxLoop.new()
	local h = hub.add(fn, interval)   fn(dt, now) runs about every `interval` seconds (0 = every step); return true to finish
	h.cancel()                         removes it (safe to call twice)
	hub.step(dt, now)                  advances everything (the client calls this from one Heartbeat)
	hub.setPaused(reason, on)          any reason (hidden window, full screen overlay) pauses all effects; time is not banked
	hub.count() / hub.paused()
	An error inside fn is caught, the task is dropped, and the hub keeps stepping the rest.
]]

local M = {}

function M.new()
	local self = {}
	local tasks = {}
	local reasons = {}
	local nReasons = 0

	function self.add(fn, interval)
		local t = { fn = fn, interval = interval or 0, acc = 0, dead = false }
		tasks[#tasks + 1] = t
		return { cancel = function() t.dead = true end }
	end

	function self.count()
		local n = 0
		for _, t in ipairs(tasks) do if not t.dead then n = n + 1 end end
		return n
	end

	function self.setPaused(reason, on)
		local was = reasons[reason] == true
		if on and not was then reasons[reason] = true; nReasons = nReasons + 1
		elseif not on and was then reasons[reason] = nil; nReasons = nReasons - 1 end
	end

	function self.paused() return nReasons > 0 end

	function self.step(dt, now)
		if nReasons > 0 then return 0 end
		local ran = 0
		for i = 1, #tasks do
			local t = tasks[i]
			if not t.dead then
				t.acc = t.acc + dt
				if t.acc >= t.interval then
					local elapsed = t.acc
					t.acc = 0
					ran = ran + 1
					local ok, done = pcall(t.fn, elapsed, now)
					if not ok or done == true then t.dead = true end
				end
			end
		end
		-- compact once per step so finished effects never pile up
		local j = 0
		for i = 1, #tasks do
			if not tasks[i].dead then j = j + 1; tasks[j] = tasks[i] end
		end
		for i = #tasks, j + 1, -1 do tasks[i] = nil end
		return ran
	end

	return self
end

return M
