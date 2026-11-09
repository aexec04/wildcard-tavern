-- One-time optional prompt after the first win: offers Roblox experience notifications (so the player gets
-- reminders to come back). The server sets state.followPrompt (a sequence number) exactly once per player
-- profile, right after the first win (Engine/FirstRewards.followDue), so this never asks twice.
--
-- ExperienceNotificationService is a client service. Everything is pcall'd: if the service is missing or the
-- player cannot be asked (CanPromptOptInAsync false), nothing happens. The prompt waits until the run is no
-- longer being played, so it never interrupts a hand. Display only; there is no gameplay effect.
local FollowPrompt = {}

local lastSeq = 0
local pendingSeq = nil

-- Tries to show the prompt. Returns true when it was shown.
local function tryPrompt()
	local ok, service = pcall(function()
		return game:GetService("ExperienceNotificationService")
	end)
	if not ok or not service then
		return false
	end
	local canAsk = false
	local okCan = pcall(function()
		canAsk = service:CanPromptOptInAsync() == true
	end)
	if not (okCan and canAsk) then
		return false
	end
	return (pcall(function()
		service:PromptOptIn()
	end))
end

-- Called from render() with every state push.
function FollowPrompt.update(state)
	if type(state) ~= "table" then
		return
	end
	local seq = state.followPrompt
	if type(seq) == "number" and seq > lastSeq then
		lastSeq = seq
		pendingSeq = seq
	end
	-- wait for a calm moment: not while hands are being played
	if pendingSeq and state.phase ~= "playing" then
		pendingSeq = nil
		task.spawn(function()
			task.wait(2) -- let the victory or game over screen settle first
			pcall(tryPrompt)
		end)
	end
end

return FollowPrompt
