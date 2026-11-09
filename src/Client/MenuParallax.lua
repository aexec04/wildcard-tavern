--[[
	Client/MenuParallax.lua
	Smooth cursor parallax for the Menu (numbers in Engine/MenuLayout.lua, math is unit tested there).
	Layers shift opposite to the cursor by different amounts (far backdrop, mid hotspots, near title and foreground), the
	title tilts about 1.5 degrees, and nothing ever moves more than 32px. Touch and phone have no cursor, so they get a slow
	idle drift of about 6px. Calm mode (Reduce Shake / Reduce Motion) holds everything still at its base position.

	new{ screenGui, layers = { { inst, base = UDim2, px = number, tilt = bool? } }, onStep = function(nx, ny, t, calm)?, calm = fn }
	returns { start(), stop() }. The frame step only runs while the Menu is open.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MenuLayout"))

local MenuParallax = {}

function MenuParallax.new(opts)
	local screenGui, layers, calm = opts.screenGui, opts.layers, opts.calm
	local sx, sy = 0, 0 -- smoothed cursor, -1 to 1
	local conn
	local t0 = os.clock()

	local function place(layer, dx, dy, tiltDegrees)
		layer.inst.Position = layer.base + UDim2.fromOffset(dx, dy)
		if layer.tilt then layer.inst.Rotation = tiltDegrees end
	end

	local function step(dt)
		local isCalm = calm()
		local t = os.clock() - t0
		local nx, ny = 0, 0
		if not isCalm then
			if UserInputService.MouseEnabled then
				local m = UserInputService:GetMouseLocation()
				local size = screenGui.AbsoluteSize
				if size.X > 0 and size.Y > 0 then
					nx = Layout.clamp(m.X / size.X * 2 - 1, -1, 1)
					ny = Layout.clamp(m.Y / size.Y * 2 - 1, -1, 1)
				end
			else
				nx, ny = Layout.idleCursor(t)
			end
		end
		local a = 1 - (1 - Layout.Parallax.lerp) ^ math.min(4, dt * 60)
		sx += (nx - sx) * a
		sy += (ny - sy) * a
		local tiltDegrees = Layout.tilt(sx, isCalm)
		for _, layer in ipairs(layers) do
			local dx, dy = Layout.parallaxOffset(sx, sy, layer.px, isCalm)
			place(layer, dx, dy, tiltDegrees)
		end
		if opts.onStep then opts.onStep(sx, sy, t, isCalm) end
	end

	local api = {}
	function api.start()
		if conn then return end
		conn = RunService.RenderStepped:Connect(step)
	end
	function api.stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		sx, sy = 0, 0
		for _, layer in ipairs(layers) do place(layer, 0, 0, 0) end
	end
	return api
end

return MenuParallax
