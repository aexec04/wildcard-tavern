--[[
	Client/ScreenCheck.lua
	Studio only (DebugGoto "screencheck"). Open the Counter or the Menu first. Prints the live rect and text size of every visible
	watched label or button (Engine/ScreenCheck.WATCH) and warns for text under 18 px and for watched pieces that overlap. Reads only.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ScreenCheck"))

local M = {}

local function visible(g)
	local o = g
	while o and not o:IsA("PlayerGui") do
		if o:IsA("GuiObject") and not o.Visible then return false end
		if o:IsA("ScreenGui") and not o.Enabled then return false end
		o = o.Parent
	end
	return true
end

function M.run()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local items = {}
	for _, d in ipairs(pg:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.AbsoluteSize.X > 0 and d.TextTransparency < 1 and Rules.isWatched(d.Text) and visible(d) then
			items[#items + 1] = {
				name = d.Name, text = d.Text, size = d.TextSize, watched = true, group = d:FindFirstAncestorWhichIsA("GuiButton") or d,
				rect = { x = d.AbsolutePosition.X, y = d.AbsolutePosition.Y, w = d.AbsoluteSize.X, h = d.AbsoluteSize.Y },
			}
		end
	end
	-- the Menu title and the Notice Board plates: live rects (screen px) at this window size
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	for _, d in ipairs(pg:GetDescendants()) do
		if (d.Name == "MenuTitle" or d.Name == "WordmarkImage" or d.Name == "RankBar" or d.Name == "NextGoalBanner" or d.Name == "NewsBanner") and d:IsA("GuiObject") and visible(d) and d.AbsoluteSize.X > 0 then
			print(string.format("[ScreenCheck] menu %s x%d y%d %dx%d at %dx%d", d.Name, d.AbsolutePosition.X, d.AbsolutePosition.Y, d.AbsoluteSize.X, d.AbsoluteSize.Y, vp and vp.X or 0, vp and vp.Y or 0))
		end
	end
	-- [MenuCheck]: only when the Menu is up; every Menu piece must exist, be visible and not be 0 wide or tall
	local menuWarns = 0
	local menuRoot = pg:FindFirstChild("MenuRoot", true)
	if menuRoot and visible(menuRoot) then
		local pieces = {}
		for _, spec in ipairs(Rules.MENU_PIECES) do
			local best
			for _, d in ipairs(menuRoot:GetDescendants()) do
				if d:IsA("GuiObject") then
					local hit = false
					if spec.names then
						for _, n in ipairs(spec.names) do if d.Name == n then hit = true end end
					elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and string.lower(d.Text) == spec.text then
						hit = true
					end
					if hit and (not best or (visible(d) and d.AbsoluteSize.X > 0)) then best = d end
					if hit and visible(d) and d.AbsoluteSize.X > 0 then break end
				end
			end
			pieces[#pieces + 1] = { label = spec.label, w = best and best.AbsoluteSize.X or 0, h = best and best.AbsoluteSize.Y or 0, visible = best ~= nil and visible(best) }
		end
		local mLines, mWarns = Rules.menuCheck(pieces)
		print("[MenuCheck] " .. table.concat(mLines, "; "))
		for _, w in ipairs(mWarns) do warn("[MenuCheck] " .. w) end
		menuWarns = #mWarns
	end
	local lines, warns = Rules.report(items)
	for _, l in ipairs(lines) do print("[ScreenCheck] " .. l) end
	for _, w in ipairs(warns) do warn("[ScreenCheck] " .. w) end
	print(string.format("[ScreenCheck] %d watched pieces, %d warnings", #items, #warns))
	return #warns + menuWarns
end

return M
