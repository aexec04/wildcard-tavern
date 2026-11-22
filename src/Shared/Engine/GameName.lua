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

-- The About panel in Settings: a framed card (it wears the equipped Card Set fill, edge and ink through PopupSkin.dark) holding the two lines.
-- LINE_H = heights of the name and the thanks line (16 px, the thanks wraps to two lines), PAD = clear space inside the frame.
M.ABOUT = { PAD = 10, LINE_H = { 26, 44 } }
function M.aboutPanelHeight()
	return M.ABOUT.PAD * 2 + M.ABOUT.LINE_H[1] + M.ABOUT.LINE_H[2]
end

-- The About lines shown at the foot of Settings: name with version, then a one line thanks. No links.
function M.aboutLines()
	return { M.NAME .. "  v" .. M.VERSION, M.THANKS }
end

return M
