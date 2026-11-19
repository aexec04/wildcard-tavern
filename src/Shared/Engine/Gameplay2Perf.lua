--[[
	Engine/Gameplay2Perf.lua
	Gameplay v2 performance and accessibility rules as data a test can check against the source files.

	LIMIT                         live GuiObjects on screen the table must stay under (1,500)
	count(root, visibleOnly)      counts GuiObjects below root (a table with Children and ClassName, or a Roblox Instance); invisible
	                              branches are skipped when visibleOnly is true
	verdict(n)                    "ok" under the limit, "warn" from 80 percent of it, "over" at or above it
	MIN_TEXT                      the smallest text size the table draws (12)
	LOOP_FILES                    the table's effect files; each repeating effect in them must run on FxLoop, not its own loop or tween
	forbiddenLoop(src)            nil, or the first pattern in the source that starts a repeating effect outside FxLoop
]]

local M = {}

M.LIMIT = 1500
M.MIN_TEXT = 12

M.LOOP_FILES = {
	"src/Client/Gameplay2.lua", "src/Client/Gameplay2FeelFX.lua", "src/Client/Gameplay2ScoreFX.lua", "src/Client/Gameplay2SynergyFX.lua",
	"src/Client/Gameplay2MomentsFX.lua", "src/Client/GuidedHint.lua", "src/Client/PatronTierFX.lua", "src/Client/PatronJuiceFX.lua", "src/Client/Gameplay2FlairFX.lua", "src/Client/TavernLifeFX.lua", "src/Client/Gameplay2Life.lua",
}

local GUI = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, CanvasGroup = true, ViewportFrame = true }

function M.count(root, visibleOnly)
	local n = 0
	local function walk(node)
		for _, child in ipairs(node.GetChildren and node:GetChildren() or node.Children or {}) do
			local cls = child.ClassName
			local isGui = GUI[cls] == true
			if isGui then n = n + 1 end
			if not (visibleOnly and isGui and child.Visible == false) then walk(child) end
		end
	end
	walk(root)
	return n
end

function M.verdict(n)
	if n >= M.LIMIT then return "over" end
	if n >= math.floor(M.LIMIT * 0.8) then return "warn" end
	return "ok"
end

local PATTERNS = { "Heartbeat:Connect", "RenderStepped", "while true do", "-1, true", "-1, false", "math.huge, " }

function M.forbiddenLoop(src)
	for _, p in ipairs(PATTERNS) do
		if src:find(p, 1, true) then return p end
	end
	return nil
end

return M
