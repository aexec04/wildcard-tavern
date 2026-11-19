--[[
	Shared/Engine/InputWatchdog.lua
	Pure model of the stuck input safety net. Anything that blocks input while it works (a screen fade cover, a held lock that
	no visible overlay owns) is armed with the time it started; if it is still armed after LIMIT seconds it is reported once
	so Client/InputWatchdogFX can release it. Nothing here touches the screen.

	local wd = InputWatchdog.new()
	wd:arm(id, now)      starts the clock (a second arm of the same id keeps the first start time)
	wd:clear(id)         the thing finished on its own
	wd:expired(now) -> list of ids that have been armed for LIMIT seconds or more; each is returned once and then forgotten
]]

local M = {}
M.__index = M
M.LIMIT = 6

function M.new(limit)
	return setmetatable({ since = {}, limit = limit or M.LIMIT }, M)
end

function M:arm(id, now)
	if self.since[id] == nil then self.since[id] = now end
end

function M:clear(id)
	self.since[id] = nil
end

function M:expired(now)
	local out = {}
	for id, t in pairs(self.since) do
		if now - t >= self.limit then out[#out + 1] = id end
	end
	table.sort(out)
	for _, id in ipairs(out) do self.since[id] = nil end
	return out
end

return M
