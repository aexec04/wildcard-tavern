--[[
	Shared/Engine/SceneKeys.lua
	Pure helper: which gameplay scene (SceneArt key) belongs to a Night and round kind.
	Small round -> "<art>_a" (approach), Big round -> "<art>_b" (entrance), Boss round -> "<art>_in" (inside).
	<art> is the `art` field of JourneyMap.Nights for Nights 1-8. Endless Nights (9+) rotate
	through JourneyMap.EndlessScenes (the old tavern rooms): Night 9 is the first, Night 14 wraps to it again.
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

-- The location art name for a Night. Nights 1..#nights use their own location; later
-- (Endless) Nights rotate through `endless` (the old tavern rooms): Night 9 is the first.
function SceneKeys.artFor(night, nights, endless)
	nights = nights or JourneyMap.Nights
	endless = endless or JourneyMap.EndlessScenes
	local n = math.max(1, math.floor(night))
	if n <= #nights or #endless == 0 then
		return nights[((n - 1) % #nights) + 1].art
	end
	return endless[((n - #nights - 1) % #endless) + 1]
end

-- (night, roundKind) -> SceneArt key, e.g. (1, "boss") -> "front_porch_in".
function SceneKeys.keyFor(night, roundKind, nights, endless)
	local suffix = SceneKeys.SUFFIX[roundKind] or SceneKeys.SUFFIX.small
	return SceneKeys.artFor(night, nights, endless) .. suffix
end

-- Where the floor sits in each scene, as a fraction of the screen height (0 top, 1 bottom).
-- Characters (Client/CharacterStage.lua) stand with their feet on this line. Tune per scene
-- by adding "<art>_a|_b|_in" keys; anything missing uses `default`.
SceneKeys.FloorFractions = {
	default = 0.66,
}

function SceneKeys.floorFraction(key)
	local value = SceneKeys.FloorFractions[key]
	if type(value) ~= "number" then
		value = SceneKeys.FloorFractions.default
	end
	return math.min(0.85, math.max(0.5, value))
end

return SceneKeys
