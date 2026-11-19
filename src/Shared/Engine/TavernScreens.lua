--[[
	Engine/TavernScreens.lua
	Which TavernKit look each remaining screen wears: the table scene behind it and the kind of every main button (green primary or
	brown secondary, never a third style). Pure data so Client/TavernScreens and the tests read one table.

	SCREENS[name] = { scene = TableSceneArt key, tint = {r,g,b} image darkening, buttons = { <instance name> = "primary" | "secondary" } }
	kindOf(screen, buttonName) -> "primary" | "secondary" | nil
	kinds(screen)              -> the set of button kinds the screen uses (at most two)
]]

local M = {}

-- tint darkens the picture so cream text on top stays at 4.5:1 (the scenes are candlelit, not dark)
M.SCREENS = {
	counter = {
		scene = "table_counter", tint = { 150, 140, 130 },
		buttons = { NextRound = "primary", Reroll = "secondary" },
	},
	runover = {
		scene = "table_runover", tint = { 130, 120, 112 },
		buttons = {
			PlayAgain = "primary", ContinueButton = "secondary", BackToTavern = "secondary", ShareResult = "secondary",
			ChallengeFriend = "secondary", InviteFriends = "secondary", SaveBadge = "secondary", WinCard = "secondary",
		},
	},
	boss = { scene = "table_boss", tint = { 150, 140, 130 }, buttons = {} },
}

-- Next Round on the Counter: a bright primary green plate, cream 24 px text on a solid dark outline, brighter on hover, never dimmed
M.NEXT_ROUND = { fill = { 62, 148, 70 }, hover = { 84, 176, 92 }, stroke = { 18, 40, 14 }, textSize = 24 }

-- the Patron tooltip plate: TavernKit plate colours (Engine/TavernStyle) instead of its own brown
M.TOOLTIP = { fill = "plateFill", trim = "goldTrim", trimThickness = 2 }

function M.kindOf(screen, name)
	local s = M.SCREENS[screen]
	return s and s.buttons[name] or nil
end

function M.kinds(screen)
	local out = {}
	local s = M.SCREENS[screen]
	if s then for _, k in pairs(s.buttons) do out[k] = true end end
	return out
end

return M
