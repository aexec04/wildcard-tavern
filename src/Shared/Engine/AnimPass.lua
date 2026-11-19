--[[
	Shared/Engine/AnimPass.lua
	Pure numbers (tested) for the last animation pass items: the Round banner bar shine sweep, the hand name slam (squash and
	settle), the shop card flip in (one by one), menu fades and slides, and the deck count flip. Client/AnimPassFX plays them.
	Calm mode and Reduce motion pass calm = true and get nil from every function, so nothing tweens.

	AnimPass.barShine(oldP, newP, calm) -> nil | { width, dur }     only when the bar grew (fractions of the bar width)
	AnimPass.nameSlam(calm, big) -> nil | { from, squash, down, settle }
	AnimPass.cardFlip(index, calm) -> nil | { delay, dur, from }    index counts from 1 within one shelf
	AnimPass.menuFade(calm) -> nil | { dur, from }                   the menu grows from `from` to 1 while it appears
	AnimPass.countFlip(oldText, newText, calm) -> nil | { half }    text swaps at the middle of the flip
]]

local M = {}

M.CARD_STEP = 0.12
M.CARD_MAX_DELAY = 0.72

function M.barShine(oldP, newP, calm)
	if calm or type(oldP) ~= "number" or type(newP) ~= "number" or newP <= oldP then return nil end
	return { width = 0.22, dur = 0.7 }
end

function M.nameSlam(calm, big)
	if calm then return nil end
	return { from = big and 1.6 or 1.4, squash = 1.12, down = 0.13, settle = 0.17 } -- 0.3 s in all
end

function M.cardFlip(index, calm)
	if calm then return nil end
	local i = math.max(1, math.floor(tonumber(index) or 1))
	return { delay = math.min((i - 1) * M.CARD_STEP, M.CARD_MAX_DELAY), dur = 0.22, from = 0.05 }
end

function M.menuFade(calm)
	if calm then return nil end
	return { dur = 0.25, from = 0.97 }
end

function M.countFlip(oldText, newText, calm)
	if calm or oldText == nil or oldText == newText then return nil end
	return { half = 0.08 }
end

return M
