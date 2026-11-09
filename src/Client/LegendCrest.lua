--[[
	Client/LegendCrest.lua
	Shows Legend prestige (Engine/Legend.lua) on the player's name medallion in the sidebar: a gold crest and the level in
	front of the name from Legend level 1, and a brighter, thicker gold aura ring around the headshot from level 2.
	Display only; called from render() with the latest state inside a pcall. It only touches the "PlayerName" label and
	the medallion's "Disc" ring by name, so it simply does nothing when they are not built yet.
]]

local LegendCrest = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local BRIGHT = Color3.fromRGB(255, 226, 140)

-- root: the ScreenGui (or any ancestor of the sidebar).
function LegendCrest.update(root, state)
	local view = state and state.legend
	local level = view and view.level or 0
	local nameLabel = root:FindFirstChild("PlayerName", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		local base = nameLabel:GetAttribute("BaseName")
		local lastShown = nameLabel:GetAttribute("LegendShown")
		if base == nil or (lastShown ~= nil and nameLabel.Text ~= lastShown) then
			base = nameLabel.Text -- first sight, or another module renamed it
			nameLabel:SetAttribute("BaseName", base)
		end
		local text = level > 0 and ("👑" .. level .. " " .. base) or base
		nameLabel:SetAttribute("LegendShown", text)
		if nameLabel.Text ~= text then
			nameLabel.Text = text
		end
	end
	local disc = root:FindFirstChild("Disc", true)
	local rim = disc and disc:FindFirstChildOfClass("UIStroke")
	if rim then
		local aura = view and view.aura == true
		rim.Color = aura and BRIGHT or GOLD
		rim.Thickness = aura and 5 or 3
	end
end

return LegendCrest
