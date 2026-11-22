--[[
	Shared/Engine/StuckHint.lua
	One kind line when a round looks out of reach: no Discards left, one or two hands left, and the pace so far will not reach the Target.
	It shows once per round, never during the guided first hand or the tutorial, and needs no animation, so Calm mode and Reduce motion
	see exactly the same plate. Pure Lua; Client/StuckHintPlate draws it.

	StuckHint.check(state) -> nil | { key = "night-round", line1, line2 }
	StuckHint.shouldShow(shownKey, hint) -> bool   false for a hint already shown this round
]]

local M = {}

M.MAX_HANDS_LEFT = 2
M.SHOW_SECONDS = 8
M.LINE1 = "Tough round, you can still do it!"
M.LINE2 = "Try a stronger hand, like a Flush or a Straight."

function M.check(state)
	if type(state) ~= "table" then return nil end
	if state.guidedFirstHand == true or state.tutorial == true then return nil end
	local left = tonumber(state.handsRemaining)
	local discards = tonumber(state.discardsRemaining)
	local score = tonumber(state.roundScore)
	local target = tonumber(state.targetScore)
	local start = tonumber(state.roundStartHands)
	if not (left and discards and score and target and start) then return nil end
	if discards > 0 or left < 1 or left > M.MAX_HANDS_LEFT then return nil end
	if score >= target then return nil end
	local played = start - left
	if played < 1 then return nil end -- no pace to judge yet
	local projected = score + (score / played) * left
	if projected >= target then return nil end
	return { key = tostring(state.night) .. "-" .. tostring(state.round), line1 = M.LINE1, line2 = M.LINE2 }
end

function M.shouldShow(shownKey, hint)
	return hint ~= nil and hint.key ~= shownKey
end

return M
