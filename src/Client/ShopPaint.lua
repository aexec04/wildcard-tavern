--[[
	Client/ShopPaint.lua
	Painted frames for the Counter's small controls (Reroll and Haggle tags, the three tabs, the Next boss chip), through
	TavernKit.painted with the flat look as the fallback. Rules in Engine/ShopPaintRules. No tweens, so Calm mode is the same.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ShopPaintRules"))
local Kit = require(script.Parent.TavernKit)
local LayoutSwitch = require(script.Parent.LayoutSwitch)

local ShopPaint = {}

function ShopPaint.plate(host, kind, active)
	if not host or not host.Parent then return nil end
	local ok, img = pcall(Kit.painted, host, Rules.pieceFor(kind, active))
	return ok and img or nil
end

-- hover on a painted tag: the picture brightens a little (the flat fill colour is hidden under it)
function ShopPaint.hover(host, on)
	local img = host.Parent and host.Parent:FindFirstChild(host.Name .. "Paint")
	if img and img:IsA("ImageLabel") then img.ImageColor3 = on and Color3.fromRGB(255, 235, 205) or (img:GetAttribute("TintColor") or Color3.new(1, 1, 1)) end
end

-- the tab bar: layout off, tabs on their own slots, each wearing the green frame when active and the dark one otherwise
function ShopPaint.tabs(bar)
	if not bar then return end
	LayoutSwitch.off(bar)
	local tabs = {}
	for _, b in ipairs(bar:GetChildren()) do
		if b:IsA("TextButton") then tabs[#tabs + 1] = b end
	end
	table.sort(tabs, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	for i, b in ipairs(tabs) do
		local s = Rules.tabSlot(i, #tabs)
		b.AnchorPoint = Vector2.new(0, 0)
		b.Position = UDim2.new(s.xs, s.xo, 0, 0)
		b.Size = UDim2.new(s.ws, s.wo, 1, 0)
		if b.ZIndex < Rules.TAB_Z then b.ZIndex = Rules.TAB_Z end
		ShopPaint.plate(b, "tab", b:GetAttribute("TabActive") == true)
	end
end

return ShopPaint
