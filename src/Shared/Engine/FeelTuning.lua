--[[
	Engine/FeelTuning.lua
	The gameplay feel numbers in one place (tested): hand card hover and select lift, the ease, the Patron beat and the name slam.
	The hub's HOVER_LIFT and SELECTED_LIFT and the 0.08 s ease in refreshCardVisual follow these; AnimPass.nameSlam sums to SLAM_TOTAL.
	All of it is skipped in Calm mode and Reduce motion (tweenTo and the beats already honour them).
]]
local FeelTuning = {
	HOVER_LIFT = 10,
	SELECTED_LIFT = 24, -- a picked card rises 24 px; the stage sits above the hand, so it never reaches the Patron pills (tested at three sizes)
	NEIGHBOUR_SPREAD = 6, -- Gameplay v2: the two cards next to the hovered one slide 6 px away
	HOVER_EASE = 0.08,
	PATRON_PULSE = 0.25,
	SLAM_TOTAL = 0.3,
}
return FeelTuning
