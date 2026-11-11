--[[
	Client/PlayPaintGuard.lua
	pcall that is not silent: the painted play screen keeps its flat fallback when a step fails, but the error text is warned once
	per label (prefix [PlayPaint]) so Studio shows what broke.

	PlayPaintGuard.run(label, fn, ...) -> ok, result
]]

local PlayPaintGuard = {}

local told = {}

function PlayPaintGuard.run(label, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		local key = label .. "|" .. tostring(res)
		if not told[key] then
			told[key] = true
			warn("[PlayPaint] " .. label .. " failed: " .. tostring(res))
		end
	end
	return ok, res
end

return PlayPaintGuard
