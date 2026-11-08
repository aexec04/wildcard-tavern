--[[
	Shared/Engine/SceneKeys.lua
	Pure helper: which gameplay scene (SceneArt key) belongs to a Night and round kind.
	Small round -> "<art>_a" (approach), Big round -> "<art>_b" (entrance), Boss round -> "<art>_in" (inside).
	<art> is the `art` field of JourneyMap.Nights. Endless Nights (past the last location) rotate
	through the locations: Night 9 is the first again, Night 16 the last.
]]

local JourneyMap = require(script.Parent.JourneyMap)

local SceneKeys = {}

SceneKeys.SUFFIX = { small = "_a", big = "_b", boss = "_in" }

-- Round number -> "small" | "big" | "boss" (the last round of a Night is the Boss).
function SceneKeys.roundKind(round, roundsPerNight)
	roundsPerNight = roundsPerNight or 3
	if round >= roundsPerNight then
		return "boss"
	elseif round <= 1 then
		return "small"
	end
	return "big"
end

-- The location art name for a Night (rotates past the last location).
function SceneKeys.artFor(night, nights)
	nights = nights or JourneyMap.Nights
	local count = #nights
	local index = ((math.max(1, math.floor(night)) - 1) % count) + 1
	return nights[index].art
end

-- (night, roundKind) -> SceneArt key, e.g. (1, "boss") -> "front_porch_in".
function SceneKeys.keyFor(night, roundKind, nights)
	local suffix = SceneKeys.SUFFIX[roundKind] or SceneKeys.SUFFIX.small
	return SceneKeys.artFor(night, nights) .. suffix
end

return SceneKeys
