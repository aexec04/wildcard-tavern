-- The words on the Run Over share line after the Share button is pressed.
-- A Roblox game cannot write to the clipboard, so the line appears in a selectable box and the player copies it. For SECONDS after a
-- press the hint says the line is ready, then it goes back to the plain how to line. The words live here so they are tested.
--   ShareFeedback.hint(now, pressedAt) -> the hint text under the share line
--   ShareFeedback.buttonWord(now, pressedAt) -> "Share" before a press, "Line ready" for SECONDS after it
local M = {}

M.SECONDS = 2
M.MIN_BUTTON_H = 44
M.IDLE_BUTTON = "Share"
M.READY_BUTTON = "Line ready"
M.IDLE_HINT = "Select the line, then press Ctrl+C."
M.READY_HINT = "Line ready! Select it, then press Ctrl+C."

local function recent(now, pressedAt)
	return type(pressedAt) == "number" and type(now) == "number" and now >= pressedAt and now - pressedAt < M.SECONDS
end

function M.hint(now, pressedAt) return recent(now, pressedAt) and M.READY_HINT or M.IDLE_HINT end
function M.buttonWord(now, pressedAt) return recent(now, pressedAt) and M.READY_BUTTON or M.IDLE_BUTTON end

return M
