--[[
	Client/Table3D/React.lua
	The table answers the score. A thump (every 2D screen shake of the play screen is one) dips the camera, makes the
	things on the table hop and brightens the lantern for a moment; a flickering light wanders a little all the time.
	Which props hop and how far, and how strong the light's answer is, come from the theme (Props[].hop,
	Lighting.react). Calm mode: no hop, no dip, steady light.

	React.start{ scene, theme, calm }
	React.thump(strength)   0..1
	React.flare(strength)   the payout: every light swells and falls back
]]

local RunService = game:GetService("RunService")
local Rig = require(script.Parent.Rig)

local React = {}

local deps = nil
local hops = {} -- { prop, t, dur, amp }
local glow = 0 -- the lantern's extra light, falling back to 0
local swell = 0 -- every light's extra, falling back to 0
local clock = 0

local function calm()
	return deps and deps.calm and deps.calm() == true
end

function React.thump(strength)
	if not deps or calm() then return end
	strength = math.clamp(strength or 0.3, 0, 1)
	Rig.kick(0.03 + 0.2 * strength)
	glow = math.max(glow, strength)
	for i, prop in ipairs(deps.scene.props) do
		if prop.hop > 0 then
			local amp = prop.hop * (0.3 + 0.7 * strength)
			local busy = false
			for _, h in ipairs(hops) do
				if h.prop == prop then
					busy = true
					if h.t > h.dur * 0.5 then h.t, h.amp = 0, amp end -- on its way down: it is knocked up again
				end
			end
			if not busy then
				hops[#hops + 1] = { prop = prop, t = -((i * 7) % 5) * 0.012, dur = 0.16 + 0.22 * math.sqrt(amp), amp = amp }
			end
		end
	end
end

function React.flare(strength)
	if not deps or calm() then return end
	swell = math.max(swell, math.clamp(strength or 0.6, 0, 1))
end

local function step(dt)
	clock = clock + dt
	local quiet = calm()
	local react = deps.theme.Lighting.react or {}
	glow = math.max(0, glow - dt * 3.2)
	swell = math.max(0, swell - dt * 1.6)
	for i, entry in ipairs(deps.scene.lights) do
		local level = 1
		if not quiet then
			if entry.flicker > 0 then
				local n = math.noise(clock * 2.3, i * 17.3) + 0.5 * math.noise(clock * 7.1, i * 5.7)
				level = level + n * (react.flicker or 0.15) * entry.flicker
			end
			if entry.lantern then
				level = level + glow * (react.thump or 0.4)
				if react.flash and entry.color then
					entry.light.Color = entry.color:Lerp(Color3.fromRGB(react.flash[1], react.flash[2], react.flash[3]), math.min(1, swell))
				end
			end
			level = level + swell * 0.45
		end
		entry.light.Brightness = entry.brightness * level
	end
	for i = #hops, 1, -1 do
		local h = hops[i]
		h.t = h.t + dt
		if h.t >= 0 then
			local u = h.t / h.dur
			local y = 0
			if u < 1 then
				y = h.amp * 4 * u * (1 - u)
			elseif u < 1.5 then -- one small second bounce
				local v = (u - 1) / 0.5
				y = h.amp * 0.22 * 4 * v * (1 - v)
			else
				table.remove(hops, i)
			end
			local lift = Vector3.new(0, y, 0)
			local parts, rest = h.prop.parts, h.prop.rest
			for k = 1, #parts do
				parts[k].CFrame = rest[k] + lift
			end
		end
	end
end

function React.start(d)
	deps = d
	RunService:BindToRenderStep("Table3DReact", Enum.RenderPriority.Camera.Value + 4, step)
end

return React
