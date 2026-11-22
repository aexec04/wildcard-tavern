--[[
	VolumeDetents.lua
	Rules for the Volume panel: the sliders feel a click at 0, 25, 50, 75 and 100 percent, and Reset puts the
	three sound settings back to their saved defaults. Pure data and functions, so it runs under plain Lua and is
	unit tested. Client/VolumePanel.lua and Client/VisualHelpers.makeSliderRow read it.
]]

local VolumeDetents = {}

VolumeDetents.STOPS = { 0, 25, 50, 75, 100 }
VolumeDetents.PULL = 3 -- a drag within 3 percent of a stop lands exactly on it

-- Sound settings that Reset restores (keys of PlayerProfile.SETTING_SPECS).
VolumeDetents.RESET_KEYS = { "musicVolume", "sfxVolume", "muted" }

VolumeDetents.RESET_LABEL = "Reset"
VolumeDetents.CONFIRM_MESSAGE = "Reset sound settings?\nMusic, SFX and Mute go back to how they started. Nothing else changes."
VolumeDetents.CONFIRM_YES = "Reset sound"
VolumeDetents.CONFIRM_NO = "Keep mine"

-- Percent (0 to 100) after the pull toward the nearest stop. Anything farther than PULL keeps its own whole number.
function VolumeDetents.snap(value)
	local v = math.floor((tonumber(value) or 0) + 0.5)
	if v < 0 then v = 0 elseif v > 100 then v = 100 end
	for _, stop in ipairs(VolumeDetents.STOPS) do
		if math.abs(v - stop) <= VolumeDetents.PULL then
			return stop
		end
	end
	return v
end

-- "35%" style text for the slider value, always a whole number.
function VolumeDetents.label(value)
	return tostring(math.floor((tonumber(value) or 0) + 0.5)) .. "%"
end

-- True when Reset would change something: `get(key)` returns the current setting, `defaults[key]` its default.
function VolumeDetents.needsReset(get, defaults)
	for _, key in ipairs(VolumeDetents.RESET_KEYS) do
		if get(key) ~= defaults[key] then
			return true
		end
	end
	return false
end

return VolumeDetents
