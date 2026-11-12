--[[
	Client/FullScreenHud.lua
	While a full-screen scene (the Tavern Map) is open the corner icon dock is hidden (Engine/FullScreenRules.HIDE); everything else of the
	HUD sits under the opaque full-screen panel (its ZIndex is above the HUD). The dock itself is Client/CornerDock's: it is recomputed from
	the live Visible of the open pages, so whichever way a scene closed (Close, Escape, another popup replacing it) it comes back.

	enter(root, reason)   leave(root, reason)   isHidden()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("FullScreenRules"))

local FullScreenHud = {}

local state = Rules.new()

-- The dock itself is Client/CornerDock's: it shows or hides from the live Visible of the registered backdrops, so entering while another
-- page is open, or leaving in a different order, can never restore a stale "hidden".
local function refresh(root)
	pcall(function() require(script.Parent.CornerDock).refresh(root) end)
end

function FullScreenHud.enter(root, reason)
	Rules.enter(state, reason)
	root:SetAttribute("FullScreenOpen", true)
	refresh(root)
end

function FullScreenHud.leave(root, reason)
	Rules.leave(state, reason)
	if not Rules.hidden(state) then
		root:SetAttribute("FullScreenOpen", nil)
	end
	refresh(root)
end

function FullScreenHud.isHidden() return Rules.hidden(state) end

return FullScreenHud
