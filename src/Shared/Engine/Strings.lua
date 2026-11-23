--[[
	Shared/Engine/Strings.lua
	Player facing text keyed by id, English only, so a later translation pass has one table to copy. Pure Lua, no Roblox APIs.
	Strings.get(id) -> the text; an unknown id returns the id itself so a typo shows up on screen and never errors.
	Moved here so far: the Settings hint lines and section blurbs (Client/Settings.lua). Wording is unchanged.
]]

local Strings = {}

Strings.en = {
	["settings.calm.hint"] = "Turns on Reduce Motion, Reduce Flashing and Reduce Screen Shake together.",
	["settings.reduceMotion.hint"] = "Calmer scenes with less movement.",
	["settings.reduceFlashing.hint"] = "No screen flashes or fast pulses, fewer sparkles.",
	["settings.fastScoring.hint"] = "Halves the time the score takes to count up. Same numbers.",
	["settings.reduceShake.hint"] = "Turns off the screen shake on big hits.",
	["settings.largerText.hint"] = "Large makes text 15 percent bigger where there is room.",
	["settings.colorblindSuits.hint"] = "Gives each suit its own color and a corner letter.",
	["settings.animSpeed.hint"] = "How fast hands score. Fast Forward owners get extra speed.",
	["settings.performanceMode.hint"] = "For slower devices: turns off the edge shading, soft glows and sparkles.",
	["settings.roundHints.hint"] = "Short hint plates in the first rounds. Turn off to hide them.",
	["settings.confirmDiscard.hint"] = "Asks before your selected cards are discarded.",
	["settings.allowSpectators.hint"] = "Friends in your server can watch your run. Turn off to stop them.",
	["settings.holdConfirm.hint"] = "How long to hold buttons that cannot be undone.",
	["settings.sound.title"] = "Music and Sound Effects",
	["settings.sound.blurb"] = "Sliders for music and effects, and Mute.",
	["settings.tutorial.blurb"] = "Walk through the first hands again. You can skip it at any time.",
	["settings.hints.blurb"] = "Show the short tips again as you meet each part of the game.",
}

function Strings.get(id)
	local text = Strings.en[id]
	if text == nil then return tostring(id) end
	return text
end

return Strings
