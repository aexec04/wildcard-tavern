--[[
	Shared/Engine/RunOverWin.lua
	Pure text rules for the win side of the Run Over screen (Client/GameOver draws them). Nothing here touches the GUI.

	RunOverWin.headline(state)       "Tavern Champion" when the run cleared every Night, else "You beat Night N"; nil for a loss
	RunOverWin.isChampion(state)     true when a win reached the Night cap
	RunOverWin.isNewRecord(state)    true when a win's Night equals or passes the best Night on the profile
	RunOverWin.unlockPills(names)    up to 3 short pill words from the new unlock names ("and N more" folds into the last pill)
	RunOverWin.confettiBig(state)    true for a full clear (a bigger burst)
	RunOverWin.tipsSteps(state, calm)  the Tips count-up plan (Engine/Celebration.countSteps), nil in Calm mode
]]

local Celebration = require(script.Parent.Celebration)

local M = {}

M.MAX_PILLS = 3
M.PILL_MAX_CHARS = 28

local function whole(n)
	if type(n) ~= "number" or n ~= n or n < 0 then return 0 end
	return math.floor(math.min(n, 9e15))
end

function M.isChampion(state)
	if type(state) ~= "table" or state.wonRun ~= true then return false end
	local cap = whole(state.nightCap)
	return cap > 0 and whole(state.night) >= cap
end

function M.headline(state)
	if type(state) ~= "table" or state.wonRun ~= true then return nil end
	if M.isChampion(state) then return "Tavern Champion" end
	return string.format("You beat Night %d", math.max(1, whole(state.night)))
end

function M.isNewRecord(state)
	if type(state) ~= "table" or state.wonRun ~= true then return false end
	local stats = type(state.profileStats) == "table" and state.profileStats or {}
	local best = whole(stats.bestNightReached)
	return best > 0 and whole(state.night) >= best
end

function M.unlockPills(names)
	if type(names) ~= "table" then return {} end
	local out = {}
	for i, name in ipairs(names) do
		if type(name) == "string" and name ~= "" then
			if #out >= M.MAX_PILLS then break end
			out[#out + 1] = #name > M.PILL_MAX_CHARS and name:sub(1, M.PILL_MAX_CHARS) or name
		end
	end
	local extra = #names - #out
	if extra > 0 and #out > 0 then
		local last = out[#out]
		if #last > M.PILL_MAX_CHARS - 12 then last = last:sub(1, M.PILL_MAX_CHARS - 12) end
		out[#out] = string.format("%s +%d more", last, extra)
	end
	return out
end

function M.confettiBig(state) return M.isChampion(state) end

function M.tipsSteps(state, calm)
	return Celebration.countSteps(state and state.tips, calm)
end

return M
