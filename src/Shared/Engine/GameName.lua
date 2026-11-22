--[[
	Shared/Engine/GameName.lua
	The player-facing game name. Repo, folder, place id, file names and DataStore keys keep the old
	working title; only text the player sees comes from here. TAGLINE is empty on purpose: the title
	shows the name alone (the genre description lives on the Roblox page).
]]

local M = {
	NAME = "The Gilded Knave",
	SHORT = "Gilded Knave",
	TAGLINE = "",
	VERSION = "0.9.0",
	THANKS = "Thanks for playing and for every Night you share with a friend.",
}

-- The About lines shown at the foot of Settings: name with version, then a one line thanks. No links.
function M.aboutLines()
	return { M.NAME .. "  v" .. M.VERSION, M.THANKS }
end

return M
