--[[
	Client/RowSkin.lua
	List rows (Leaderboards, Quests, Daily Rewards) wear the equipped Card Set: a dark set-tinted row plate with cream ink, a lighter row for "you"
	or "today", a muted second line, an accent rank badge and a claim chip (CosmeticSets.rowStyleOf, every pair 4.5:1 or more). Colours only: no
	layout, no tween. Rows are built fresh when a panel opens, so the style is read at build time.

	RowSkin.get() -> nil (classic) or { row, hot, ink, sub, edge, badge, badgeInk, chip, chipInk } as Color3
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RowSkin = {}

local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

function RowSkin.get()
	local out
	pcall(function()
		local CS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
		local st = CS.rowStyleOf(require(script.Parent.TavernKit).plateSetId())
		if st then
			out = {}
			for k, v in pairs(st) do out[k] = c3(v) end
		end
	end)
	return out
end

return RowSkin
