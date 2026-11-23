--[[
	Engine/PanelOrigin.lua
	Where Back goes from a full screen page (Collection, Quests, Store and the other Tome pages). The page remembers its origin once, when the
	first page of a visit opens: "table" (mid round), "menu" or "map". Moving between pages with the tabs never changes it, and Back always
	returns there, never to the page before. Closing the pages leaves the screen underneath exactly as it was (round, music and hands intact).
	Pure state, no Roblox calls.
]]
local M = {}

M.SCREENS = { table = true, menu = true, map = true, roundSelect = true, shop = true }

function M.new()
	return { active = false, origin = nil }
end

-- A page opened. screen = the screen under it ("table", "menu", "map"). Only the first page of a visit records it.
function M.opened(st, screen)
	if not st.active then
		st.active = true
		st.origin = M.SCREENS[screen] and screen or "menu"
	end
	return st.origin
end

-- Every page closed: the next visit records its origin again.
function M.closed(st)
	st.active, st.origin = false, nil
end

-- What Back does: always close the pages and show the origin screen.
function M.backTarget(st)
	return { close = true, screen = st.origin or "menu" }
end

return M
