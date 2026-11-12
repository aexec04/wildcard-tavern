--[[
	Client/FullScreenHud.lua
	While a full-screen scene (the Tavern Map) is open the corner icon dock is hidden (Engine/FullScreenRules.HIDE); everything else of the
	HUD sits under the opaque full-screen panel (its ZIndex is above the HUD). The first call remembers each piece's Visible and leave()
	puts it back exactly, whichever way the scene closed (Close, Escape, another popup replacing it).

	enter(root, reason)   leave(root, reason)   isHidden()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("FullScreenRules"))

local FullScreenHud = {}

local state = Rules.new()
local saved = {} -- [instance] = its Visible before the first enter

function FullScreenHud.enter(root, reason)
	local wasHidden = Rules.hidden(state)
	Rules.enter(state, reason)
	if wasHidden then return end
	for _, name in ipairs(Rules.HIDE) do
		local inst = root:FindFirstChild(name)
		if inst then
			saved[inst] = inst.Visible
			inst.Visible = false
		end
	end
	root:SetAttribute("FullScreenOpen", true)
end

function FullScreenHud.leave(root, reason)
	if not Rules.hidden(state) then return end
	Rules.leave(state, reason)
	if Rules.hidden(state) then
		for inst, was in pairs(saved) do
			if inst.Parent then inst.Visible = was end
		end
		saved = {}
		root:SetAttribute("FullScreenOpen", nil)
	end
end

function FullScreenHud.isHidden() return Rules.hidden(state) end

return FullScreenHud
