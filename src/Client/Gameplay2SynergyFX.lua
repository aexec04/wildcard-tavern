--[[
	Client/Gameplay2SynergyFX.lua
	Draws Engine/Gameplay2Synergy on the Gameplay v2 table: a thin gold thread across the gap between two neighbouring Patron cards
	that share a theme, with the tag's icon on it when the gap is wide enough. Static frames (no tween), so Calm mode is the same.
	Display only; nothing is sent to the server.

	update(layer, rects, ownedIds)   draws or hides the threads; pieces are pooled inside the layer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Gameplay2Synergy"))

local M = {}

local GOLD = Color3.fromRGB(246, 196, 70)
local Z = 3 -- above the scene, under the Patron cards and the pills

local function piece(layer, i)
	local f = layer:FindFirstChild("SynergyThread" .. i)
	if f then return f end
	f = Instance.new("Frame")
	f.Name = "SynergyThread" .. i
	f.BorderSizePixel = 0
	f.BackgroundColor3 = GOLD
	f.BackgroundTransparency = 1 - Rules.THREAD_ALPHA
	f.Active = false
	f.ZIndex = Z
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = f
	local l = Instance.new("TextLabel")
	l.Name = "Tag"
	l.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	l.BackgroundTransparency = 0.1
	l.BorderSizePixel = 0
	l.Font = Enum.Font.GothamBold
	l.TextSize = 14
	l.TextColor3 = GOLD
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.Active = false
	l.ZIndex = Z + 1
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(1, 0); lc.Parent = l
	local ls = Instance.new("UIStroke"); ls.Color = GOLD; ls.Thickness = 1; ls.Transparency = 0.4; ls.Parent = l
	l.Parent = f
	f.Parent = layer
	return f
end

function M.update(layer, rects, ownedIds)
	local links = Rules.links(ownedIds or {})
	local used = 0
	for _, link in ipairs(links) do
		local t = Rules.thread(rects, link)
		if t then
			used = used + 1
			local f = piece(layer, used)
			f.Visible = true
			f.Position = UDim2.fromOffset(t.x, t.y)
			f.Size = UDim2.fromOffset(t.w, t.h)
			local l = f.Tag
			if t.label then
				l.Visible = true
				l.Text = link.icon or ""
				l.Position = UDim2.fromOffset(t.label.x - t.x, t.label.y - t.y)
				l.Size = UDim2.fromOffset(t.label.w, t.label.h)
			else
				l.Visible = false
			end
		end
	end
	for i = used + 1, 8 do
		local f = layer:FindFirstChild("SynergyThread" .. i)
		if f then f.Visible = false else break end
	end
end

return M
