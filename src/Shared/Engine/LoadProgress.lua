--[[
	Engine/LoadProgress.lua
	Pure rules for the launch loading screen (no Roblox). Real work reports in: ContentArt.preload reports
	"menu" and "gameplay" image batches, the hub reports menuShown(). The bar value is monotonic, clamped
	0 to 1, and reaches 1 only when the Menu is shown and every phase is complete.
	Weights: menu art 40 percent, gameplay art 40 percent, Menu visible 20 percent.
	LoadProgress.new() -> tracker { report(name, done, total), complete(name), menuShown(), value(), isReady() }
	LoadProgress.shared is the tracker ContentArt reports into.
	Display rules: ease(display, target, dt), fillWidth(innerW, display), stalled(now, lastProgressAt).
]]

local LoadProgress = {}

LoadProgress.WEIGHTS = { menu = 0.4, gameplay = 0.4 }
LoadProgress.MENU_WEIGHT = 0.2
LoadProgress.MIN_VISIBLE = 1.2 -- seconds: the screen never flashes
LoadProgress.ALMOST_AFTER = 8 -- seconds with no progress before "Almost there..."
LoadProgress.SKIP_AFTER = 25 -- seconds in total before "Still loading" and the Skip button
LoadProgress.FADE_TIME = 0.5
LoadProgress.TIP_EVERY = 3.5

local function clamp01(x)
	if x ~= x then return 0 end
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end
LoadProgress.clamp01 = clamp01

function LoadProgress.new()
	local self = { phases = {}, menu = false, best = 0 }

	function self.report(name, done, total)
		if LoadProgress.WEIGHTS[name] == nil then return end
		total = math.max(0, tonumber(total) or 0)
		done = math.max(0, tonumber(done) or 0)
		local p = self.phases[name] or { frac = 0, complete = false }
		local frac = (total <= 0) and 1 or clamp01(done / total)
		if frac > p.frac then p.frac = frac end -- never backward
		if total > 0 and done >= total then p.complete = true end
		self.phases[name] = p
	end

	function self.complete(name)
		if LoadProgress.WEIGHTS[name] == nil then return end
		self.phases[name] = { frac = 1, complete = true }
	end

	function self.menuShown() self.menu = true end

	function self.isReady()
		if not self.menu then return false end
		for name in pairs(LoadProgress.WEIGHTS) do
			local p = self.phases[name]
			if not (p and p.complete) then return false end
		end
		return true
	end

	function self.value()
		local v = 0
		for name, w in pairs(LoadProgress.WEIGHTS) do
			local p = self.phases[name]
			if p then v = v + w * p.frac end
		end
		if self.menu then v = v + LoadProgress.MENU_WEIGHT end
		v = clamp01(v)
		if not self.isReady() then v = math.min(v, 0.999) end -- 1 only when the Menu is shown and all phases are done
		if v > self.best then self.best = v end
		return self.best
	end

	return self
end

LoadProgress.shared = LoadProgress.new()

-- Displayed value eases toward the real one and never moves backward or past it.
function LoadProgress.ease(display, target, dt)
	display, target = clamp01(display), clamp01(target)
	if target <= display then return display end
	local k = 1 - math.exp(-math.max(0, dt) * 4)
	local nextValue = display + (target - display) * k
	-- always creep so a long wait never looks frozen: at least 0.4 percent per second while behind
	nextValue = math.max(nextValue, math.min(target, display + 0.004 * dt))
	return clamp01(nextValue)
end

-- Fill width in pixels inside a channel innerW wide: always inside the frame.
function LoadProgress.fillWidth(innerW, display)
	innerW = math.max(0, innerW or 0)
	return math.floor(innerW * clamp01(display) + 0.5)
end

function LoadProgress.stalled(now, lastProgressAt)
	return (now - lastProgressAt) >= LoadProgress.ALMOST_AFTER
end

-- Status line for the bar's value (tavern voice, no dashes).
function LoadProgress.status(value, stalledFlag, slowFlag)
	if slowFlag then return "Still loading, thanks for waiting" end
	if stalledFlag then return "Almost there..." end
	if value < 0.4 then return "Lighting the lanterns..." end
	if value < 0.8 then return "Shuffling the deck..." end
	return "Setting the tables..."
end

return LoadProgress
