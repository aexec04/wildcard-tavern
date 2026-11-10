--[[
	tools/check_panel_overlap.lua  (Luau, run in Studio Play via the command bar or a harness; not part of the Lua test run)
	Lists every visible TextLabel or TextButton whose bounds touch the frame band of a SetSkinPlate, for all open panels.
	Paste into the command bar while Play is running, with a Card Set equipped and panels open.
]]

local Players = game:GetService("Players")
local Engine = game:GetService("ReplicatedStorage").Shared.Engine
local PanelBand = require(Engine.PanelBand)

local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local hits = 0
for _, plate in ipairs(gui:GetDescendants()) do
	if plate.Name == "SetSkinPlate" and plate:IsA("ImageLabel") and plate.Parent:IsA("GuiObject") and plate.Parent.Visible then
		local panel = plate.Parent
		local size = panel.AbsoluteSize
		local band = PanelBand.band(size.X, size.Y)
		for _, d in ipairs(panel:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible and d.AbsoluteSize.X > 0 then
				local x = d.AbsolutePosition.X - panel.AbsolutePosition.X
				local y = d.AbsolutePosition.Y - panel.AbsolutePosition.Y
				if PanelBand.intersectsBand(size.X, size.Y, band, x, y, d.AbsoluteSize.X, d.AbsoluteSize.Y) then
					hits += 1
					print(string.format("[overlap] %s on %s (band %d px): %q", d:GetFullName(), panel.Name, band, d.Text))
				end
			end
		end
	end
end
print("[overlap] done, " .. hits .. " text elements touch a frame band")
