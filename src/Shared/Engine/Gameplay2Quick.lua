--[[
	Engine/Gameplay2Quick.lua
	Gameplay v2: the two quick controls in the top left corner of the table, Mute and Calm, pure and tested. Everything else stays
	behind Settings. Client/Gameplay2.lua draws them as real kit buttons on Gameplay2Layout.rects (r.mute, r.calm).

	view(settings)      -> { mute = { text, kind, on }, calm = { text, kind, on } }   kind is "primary" (green) when ON, "secondary" (brown) when off
	muteWrites(settings) -> { muted = not muted }
	calmWrites(settings) -> the three Calm writes (reduceMotion, reduceFlashing, reduceShake) flipped together, as the Settings Calm Mode switch does
	The words are "Mute" and "Calm" so state never rides on colour alone: the button text reads "Muted" and "Calm On" when active.
]]

local SettingsLayout = require(script.Parent:WaitForChild("SettingsLayout"))

local M = {}

local function isOn(v) return v == true end

function M.calmOn(settings)
	return SettingsLayout.calmValue({ reduceMotion = isOn(settings.reduceMotion), reduceFlashing = isOn(settings.reduceFlashing), reduceShake = isOn(settings.reduceShake) })
end

function M.view(settings)
	settings = settings or {}
	local muted, calm = isOn(settings.muted), M.calmOn(settings)
	return {
		mute = { text = muted and "Muted" or "Mute", kind = muted and "primary" or "secondary", on = muted },
		calm = { text = calm and "Calm On" or "Calm", kind = calm and "primary" or "secondary", on = calm },
	}
end

function M.muteWrites(settings)
	return { muted = not isOn((settings or {}).muted) }
end

function M.calmWrites(settings)
	return SettingsLayout.calmWrites(not M.calmOn(settings or {}))
end

return M
