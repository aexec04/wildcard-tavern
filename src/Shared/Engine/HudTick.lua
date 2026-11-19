--[[
	Shared/Engine/HudTick.lua
	Pure numbers (tested) for the Concept T HUD animation pass: a pill number pops when it changes, the gear turns on hover,
	the deck pile shakes and its count flips when a card is drawn. Client/HudTickFX plays them. Calm mode and Reduce motion
	return nil, so nothing tweens.

	HudTick.pop(oldText, newText, calm) -> nil | { scale, up, down }   only when the text really changed
	HudTick.gear(hovering, calm) -> nil | { rotation, dur }
	HudTick.deckShake(oldText, newText, calm) -> nil | { px, count, dur }   when the count went down (a draw)
]]

local M = {}

local function number(t)
	return tonumber(tostring(t or ""):match("%d+"))
end

function M.pop(oldText, newText, calm)
	if calm or oldText == nil or oldText == newText then return nil end
	return { scale = 1.14, up = 0.08, down = 0.14 }
end

function M.gear(hovering, calm)
	if calm then return nil end
	return { rotation = hovering and 28 or 0, dur = 0.25 }
end

function M.deckShake(oldText, newText, calm)
	if calm then return nil end
	local a, b = number(oldText), number(newText)
	if a == nil or b == nil or b >= a then return nil end
	return { px = 3, count = 3, dur = 0.06 }
end

return M
