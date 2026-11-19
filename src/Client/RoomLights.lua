--[[
	Client/RoomLights.lua
	Soft flickering lights and a few dust motes over a painted room (math and light spots in Engine/RoomLights.lua).

	RoomLights.attach(parent, { room = "flair", zIndex, visible = function() -> bool }) -> {
	  place(rect)   the room PICTURE's rect in parent pixels { x, y, w, h }; call it whenever the picture moves or resizes
	  destroy()
	}
	One 30 Hz Heartbeat per room, built once (pooled glows and motes, nothing created per frame), idle while visible() is false or the
	picture is not placed. Calm mode (reduceShake) leaves every light as a static glow and creates no motes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lights = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RoomLights"))
local Life = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TavernLife"))
local SoftGlow = require(script.Parent.SoftGlow)
local ClientSettings = require(script.Parent.ClientSettings)

local RoomLights = {}

local STEP = 1 / 30
local MOTE_SIZE = 3
local MOTE_COLOR = Color3.fromRGB(255, 226, 160)
local GLOW_COLOR = { candle = Color3.fromRGB(255, 190, 100), lantern = Color3.fromRGB(255, 196, 110), fire = Color3.fromRGB(255, 150, 70), window = Color3.fromRGB(255, 226, 170) }

local function isCalm()
	local calm = false
	pcall(function() calm = ClientSettings.get("reduceShake") == true end)
	return calm
end

function RoomLights.attach(parent, opts)
	local def = Lights.ROOMS[opts.room]
	local self = {}
	if not def then
		function self.place() end
		function self.destroy() end
		return self
	end
	local z = opts.zIndex or 1
	local rect = nil
	local glows = {}
	for i, spot in ipairs(def.spots) do
		local g = SoftGlow.build(parent, {
			name = "RoomLight" .. i, color = GLOW_COLOR[spot.kind] or GLOW_COLOR.lantern, peak = Lights.BASE[spot.kind],
			position = UDim2.fromOffset(0, 0), size = UDim2.fromOffset(10, 10), zIndex = z,
		})
		g.root.Visible = false
		glows[i] = { glow = g, spot = spot, last = -1 }
	end
	local motes = {}
	for i = 1, Lights.moteCount(opts.room) do
		local m = Instance.new("Frame")
		m.Name = "RoomMote" .. i
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Size = UDim2.fromOffset(MOTE_SIZE, MOTE_SIZE)
		m.BackgroundColor3 = MOTE_COLOR
		m.BackgroundTransparency = 1
		m.BorderSizePixel = 0
		m.Active = false
		m.Visible = false
		m.ZIndex = z
		m.Parent = parent
		motes[i] = m
	end

	local function frame(t, calm)
		for i, e in ipairs(glows) do
			local m = Lights.flicker(e.spot.kind, t, i, calm)
			if e.spot.kind == "fire" then m = m * Life.firePulse(t, calm) end -- slow 3 s breath, 0.9 to 1.0
			if m ~= e.last then -- skip the 32 ring writes when nothing changed (calm mode)
				e.last = m
				e.glow.setPeak(Lights.BASE[e.spot.kind] * m)
			end
		end
		for i, m in ipairs(motes) do
			local s = Lights.mote(i, #motes, t, def.shaft)
			m.Position = UDim2.fromOffset(rect.x + s.x * rect.w, rect.y + s.y * rect.h)
			m.BackgroundTransparency = 1 - 0.55 * math.max(0, s.alpha)
		end
	end

	function self.place(r)
		rect = r
		for _, e in ipairs(glows) do
			e.glow.root.Visible = r ~= nil
			if r then
				e.glow.root.Position = UDim2.fromOffset(r.x + e.spot.x * r.w, r.y + e.spot.y * r.h)
				e.glow.root.Size = UDim2.fromOffset(r.w * e.spot.size, r.w * e.spot.size)
			end
		end
		for _, m in ipairs(motes) do m.Visible = r ~= nil and not isCalm() end
		if r then frame(0, true) end
	end

	local conn = require(script.Parent.FxLoop).add(function()
		if not rect or not (opts.visible and opts.visible()) then return end
		local calm = isCalm()
		if calm then
			for _, m in ipairs(motes) do m.Visible = false end
			return
		end
		for _, m in ipairs(motes) do m.Visible = true end
		frame(os.clock(), false)
	end, STEP)

	function self.destroy()
		conn.cancel()
		for _, e in ipairs(glows) do e.glow.root:Destroy() end
		for _, m in ipairs(motes) do m:Destroy() end
	end
	return self
end

return RoomLights
