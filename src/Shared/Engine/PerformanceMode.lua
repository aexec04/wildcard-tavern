--[[
	Engine/PerformanceMode.lua
	Performance mode (Settings > Display): a switch for low end devices. It turns off the edge vignettes, the stacked soft glows and
	particle effects. It is its own setting (`performanceMode`) and does not touch Calm mode; the two can be on together.

	PerformanceMode.on(settings)             true when the switch is on
	PerformanceMode.vignettes(settings)      false under Performance mode (Client/SmoothVignette draws nothing)
	PerformanceMode.glows(settings)          false under Performance mode (Client/SoftGlow draws nothing)
	PerformanceMode.particles(settings)      false under Performance mode (Engine/Accessibility.particleCount returns 0)
	PerformanceMode.BUDGET_MS                a screen build slower than this (150 ms) is reported
	PerformanceMode.slow(samples)            { { name, ms } ... } of the samples over budget, slowest first
	PerformanceMode.line(name, ms)           the Studio line for one timed build
]]

local M = {}

M.BUDGET_MS = 150

function M.on(settings)
	return type(settings) == "table" and settings.performanceMode == true
end
function M.vignettes(settings) return not M.on(settings) end
function M.glows(settings) return not M.on(settings) end
function M.particles(settings) return not M.on(settings) end

function M.slow(samples)
	local out = {}
	for _, s in ipairs(samples or {}) do
		if type(s.ms) == "number" and s.ms > M.BUDGET_MS then out[#out + 1] = { name = s.name, ms = s.ms } end
	end
	table.sort(out, function(a, b) return a.ms > b.ms end)
	return out
end

function M.line(name, ms)
	local over = ms > M.BUDGET_MS
	return string.format("[Build] %s %d ms%s", tostring(name), math.floor(ms + 0.5), over and " OVER 150 ms" or "")
end

return M
