--[[
	Client/SelfCheck.lua
	Studio only. Walks every shown TextButton, TextLabel and KitLabel under PlayerGui, describes each as a plain node and runs
	Engine/SelfCheck over them; warns once per finding. Open the screen first (table, Counter, Run Over, pause), then run
	DebugGoto "selfcheck". Reads only, never changes the game.

	SelfCheck.run() -> number of warnings
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SelfCheck"))

local M = {}

local function rgb(c) return { c.R, c.G, c.B } end
local function rectOf(g) return { x = g.AbsolutePosition.X, y = g.AbsolutePosition.Y, w = g.AbsoluteSize.X, h = g.AbsoluteSize.Y } end

local function shown(g) -- the object and every ancestor GuiObject or ScreenGui is visible
	local o = g
	while o and not o:IsA("PlayerGui") do
		if o:IsA("GuiObject") and not o.Visible then return false end
		if o:IsA("ScreenGui") and not o.Enabled then return false end
		o = o.Parent
	end
	return true
end

local function plateBehind(g) -- first opaque background on the label or an ancestor
	local o = g
	while o and o:IsA("GuiObject") do
		if o.BackgroundTransparency < 0.5 then return rgb(o.BackgroundColor3) end
		o = o.Parent
	end
	return nil
end

local function plateZ(g) -- highest ZIndex among the label's non-text siblings named like a plate or rim
	local top
	local p = g.Parent
	if not p then return nil end
	for _, s in ipairs(p:GetChildren()) do
		if s ~= g and s:IsA("GuiObject") and not s:IsA("TextLabel") and not s:IsA("TextButton") and s.Visible
			and (s.Name:find("Plate") or s.Name:find("Rim")) then
			top = math.max(top or -math.huge, s.ZIndex)
		end
	end
	return top
end

function M.nodes()
	local pg = game:GetService("Players").LocalPlayer.PlayerGui
	local nodes = {}
	for _, d in ipairs(pg:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) and d.AbsoluteSize.X > 0 then
			nodes[#nodes + 1] = {
				path = d:GetFullName(), text = d.Text, textTransparency = d.TextTransparency, textColor = rgb(d.TextColor3),
				plateColor = plateBehind(d), z = d.ZIndex, plateZ = plateZ(d), rect = rectOf(d),
				parentRect = d.Parent and d.Parent:IsA("GuiObject") and rectOf(d.Parent) or nil,
			}
		end
	end
	return nodes
end

function M.run()
	if not RunService:IsStudio() then return 0 end
	local nodes = M.nodes()
	local found = Rules.check(nodes)
	for _, line in ipairs(found) do warn("[SelfCheck] " .. line) end
	print(string.format("[SelfCheck] %d text objects checked, %d warning(s)", #nodes, #found))
	return #found
end

return M
