--[[
	Shared/Engine/ProgressionFeel.lua
	Pure numbers and words (tested) for how progress feels: the rank-up toast, the unlock list on the Run Over screen and the
	Daily Challenge line. Client/CornerToast, Client/UnlockToast and Client/GameOver use it.

	  ProgressionFeel.toast(kind, calm) -> { hold, rise, cue }   rank toasts rise 16 px and hold 2.5 s; calm mode: no rise
	  ProgressionFeel.unlockLine(names) -> "New: A, B and 2 more" (nil when there is nothing new)
	  ProgressionFeel.dailyLine(rewardText, streak) -> "Daily Challenge: <reward>  Streak 3"
]]

local M = {}

M.RISE = 16
M.HOLD = 2.5
M.CUE = "shop_buy"
M.MAX_NAMES = 3

function M.toast(kind, calm)
	if kind ~= "rank" then return nil end
	return { hold = M.HOLD, rise = (not calm) and M.RISE or 0, cue = M.CUE }
end

function M.unlockLine(names)
	if type(names) ~= "table" or #names == 0 then return nil end
	if #names <= M.MAX_NAMES then
		return "New: " .. table.concat(names, ", ")
	end
	return string.format("New: %s and %d more", table.concat(names, ", ", 1, M.MAX_NAMES - 1), #names - (M.MAX_NAMES - 1))
end

function M.dailyLine(rewardText, streak)
	local s = math.floor(tonumber(streak) or 0)
	local out = "Daily Challenge"
	if type(rewardText) == "string" and rewardText ~= "" then out = out .. ": " .. rewardText end
	if s > 0 then out = out .. string.format("  Streak %d", s) end
	return out
end

return M
