-- Studio diagnostic: 0.6 s after a click, one line listing every hand card: index, picked and its on-screen Y.
-- Every picked card must sit lifted above the fan line of its neighbours.
local M = {}

function M.print(handFrame, clicked)
	if not handFrame then return end
	task.delay(0.6, function()
		local rows = {}
		for _, c in ipairs(handFrame:GetChildren()) do
			local idx = c:IsA("Frame") and c:GetAttribute("HandIndex")
			local b = idx and c:FindFirstChildOfClass("TextButton")
			if b then rows[#rows + 1] = { idx, c:GetAttribute("Picked") == true, math.floor(b.AbsolutePosition.Y), math.floor(c:GetAttribute("LiftY") or 0) } end
		end
		table.sort(rows, function(a, b) return a[1] < b[1] end)
		local parts = {}
		for _, r in ipairs(rows) do parts[#parts + 1] = string.format("%d:%s y=%d lift=%d", r[1], r[2] and "picked" or "-", r[3], r[4]) end
		print(string.format("[HandLift] after click %d: %s", clicked, table.concat(parts, " | ")))
	end)
end

return M
