--[[
	Shared/Engine/DailyPlateLayout.lua
	Vertical rows of the Daily Rewards plate (Client/DailyRewardsPanel reads them). The streak line sits on its own row
	clear of the title band, then the day cards, and the "Next reward" and timer lines are centred in the space left
	above the bottom margin. Pure Lua.

	DailyPlateLayout.rows() -> { streak = {y,h}, ladder = {y,h}, next = {y,h}, countdown = {y,h}, bottom }
]]
local DailyPlateLayout = {}

DailyPlateLayout.PANEL_H = 360
DailyPlateLayout.BAND_BOTTOM = 56 -- TitleBand: 4 px inset plus its 52 px height
DailyPlateLayout.STREAK_GAP = 8
DailyPlateLayout.STREAK_H = 24
DailyPlateLayout.LADDER_H = 168
DailyPlateLayout.NEXT_H = 28
DailyPlateLayout.COUNT_H = 26
DailyPlateLayout.MARGIN = 16

function DailyPlateLayout.rows()
	local L = DailyPlateLayout
	local streakY = L.BAND_BOTTOM + L.STREAK_GAP
	local ladderY = streakY + L.STREAK_H + 10
	local free0 = ladderY + L.LADDER_H
	local free1 = L.PANEL_H - L.MARGIN
	local text = L.NEXT_H + L.COUNT_H
	local gap = math.max(0, math.floor((free1 - free0 - text) / 3))
	local nextY = free0 + gap
	return {
		streak = { y = streakY, h = L.STREAK_H },
		ladder = { y = ladderY, h = L.LADDER_H },
		next = { y = nextY, h = L.NEXT_H },
		countdown = { y = nextY + L.NEXT_H + gap, h = L.COUNT_H },
		bottom = L.PANEL_H - L.MARGIN,
	}
end

return DailyPlateLayout
