-- Studio Play is silent by default. The decision is pure: only IsStudio and the
-- SoundService attribute StudioAudio (true = opt back in) matter. Never saved to the profile.
local StudioAudio = {}

function StudioAudio.shouldMute(isStudio, optIn)
	return isStudio == true and optIn ~= true
end

return StudioAudio
