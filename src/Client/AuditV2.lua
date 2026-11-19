--[[
	Client/AuditV2.lua
	Studio only. Prints the Gameplay v2 audit (Engine/Gameplay2Audit) for five window sizes and for the live window, with the
	rect of every control, and warns on overlaps, off screen items, small touch targets and narrow hand cards. Never ships a
	change to the game: it only reads layouts. Run it from the Output command bar or with DebugGoto "audit:v2".

	AuditV2.run()  -> number of warnings
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Audit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Gameplay2Audit"))

local M = {}

function M.run()
	if not RunService:IsStudio() then return 0 end
	local sizes = {}
	for _, s in ipairs(Audit.SIZES) do sizes[#sizes + 1] = { s[1], s[2] } end
	pcall(function()
		local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChildWhichIsA("ScreenGui")
		if gui then sizes[#sizes + 1] = { math.floor(gui.AbsoluteSize.X), math.floor(gui.AbsoluteSize.Y) } end
	end)
	local total = 0
	for _, s in ipairs(sizes) do
		local lines, a = Audit.report(s[1], s[2])
		total = total + #a.warnings
		for i, line in ipairs(lines) do
			if i == 1 and #a.warnings > 0 then warn("[AuditV2] " .. line) else print("[AuditV2] " .. line) end
		end
	end
	print(string.format("[AuditV2] %d warning(s) across %d sizes", total, #sizes))
	return total
end

return M
