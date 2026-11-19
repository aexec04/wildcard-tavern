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
-- (bright warm green 0.30,0.62,0.30; the text keeps a dark outline for 4.5:1 and the plate a thin gold edge)
M.NEXT_ROUND = { fill = { 77, 158, 77 }, hover = { 100, 186, 100 }, stroke = { 18, 40, 14 }, edge = { 232, 184, 74 }, text = { 250, 240, 220 }, textSize = 24 }

-- the Patron tooltip plate: TavernKit plate colours (Engine/TavernStyle) instead of its own brown
M.TOOLTIP = { fill = "plateFill", trim = "goldTrim", trimThickness = 2 }

-- ZIndex layers under ZIndexBehavior.Global: the picture and the set's border and rim sit BELOW every control, so nothing can tint
-- a button (Next Round read as dim green because the scene, added after it at the same ZIndex 6, drew on top of it)
M.LAYERS = { scene = 4, decor = 5, controls = 10 }
M.DECOR_NAMES = { SetSkinBorder = true, InnerRim = true, TavernScene = true }

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
