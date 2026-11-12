-- Studio Play plays sound like a live server. The decision is pure: only IsStudio and the
-- SoundService attribute StudioAudio matter; StudioAudio = false mutes Studio. Never saved to the profile.
local StudioAudio = {}

function StudioAudio.shouldMute(isStudio, attr)
	return isStudio == true and attr == false
end

return StudioAudio
