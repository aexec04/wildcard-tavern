--[[
	Engine/Ambience.lua
	Pure rules for the quiet tavern bed: its volume (0.12, ducked to 0.06 while a hand scores), silent when Mute is on or the SFX
	slider is 0, and paused while the window is hidden. The sound id lives in SoundIds.Ambience (empty = silent no-op).
]]

local M = {}

M.BASE = 0.12
M.DUCKED = 0.06

-- Per Card Set beds. Every set shares the quiet tavern bed today; a set may add its own loop here as { id, volume }. Whatever a set
-- asks for is clamped under the music default (PlayerProfile musicVolume 0.35) and under MAX_BED, so no set bed can drown the music.
M.MUSIC_DEFAULT = 0.35
M.MAX_BED = 0.2
M.SetBeds = {}

function M.setBed(setId, tavernBed)
	local bed = M.SetBeds[setId] or tavernBed or { id = "", volume = M.BASE }
	local v = tonumber(bed.volume) or M.BASE
	v = math.max(0, math.min(v, M.MAX_BED, M.MUSIC_DEFAULT))
	return { id = bed.id or "", volume = v }
end

-- Volume for the bed, 0 when it should not be heard.
function M.volume(muted, sfxVolume, scoring, focused)
	if muted or focused == false then return 0 end
	local slider = math.max(0, math.min(1, tonumber(sfxVolume) or 1))
	return (scoring and M.DUCKED or M.BASE) * slider
end

-- Should the Sound instance be playing right now.
function M.shouldPlay(id, muted, focused)
	return type(id) == "string" and id ~= "" and not muted and focused ~= false
end

return M
