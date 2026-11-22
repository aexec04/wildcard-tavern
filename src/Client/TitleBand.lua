--[[
	Client/TitleBand.lua
	A slim title strip for popups in the equipped Card Set's colours (fill tinted toward the accent, accent edge). Classic keeps the popup as it
	was: the strip is hidden. Colours come from CosmeticSets.titleBandOf (cream title text keeps 7:1 on the fill). No tweens.

	TitleBand.attach(panel, opts) -> the band Frame (Name "SetTitleBand"); opts.height (52), opts.z (panel.ZIndex), opts.inset (4)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TitleBand = {}

TitleBand.HEIGHT = 52

function TitleBand.attach(panel, opts)
	opts = opts or {}
	local existing = panel:FindFirstChild("SetTitleBand")
	if existing then return existing end
	local inset = opts.inset or 4
	local band = Instance.new("Frame")
	band.Name = "SetTitleBand"
	band.Position = UDim2.fromOffset(inset, inset)
	band.Size = UDim2.new(1, -inset * 2, 0, opts.height or TitleBand.HEIGHT)
	band.BorderSizePixel = 0
	band.Active = false
	band.ZIndex = opts.z or panel.ZIndex
	band.Visible = false
	band.Parent = panel
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 8)
	round.Parent = band
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = band

	local function apply()
		local ok, c = pcall(function()
			local CS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
			return CS.titleBandOf(require(script.Parent.TavernKit).plateSetId())
		end)
		if ok and c then
			band.BackgroundColor3 = Color3.fromRGB(c.fill[1], c.fill[2], c.fill[3])
			stroke.Color = Color3.fromRGB(c.edge[1], c.edge[2], c.edge[3])
			band.BackgroundTransparency = 0
			band.Visible = true
		else
			band.Visible = false
		end
	end
	apply()
	pcall(function() require(script.Parent.HudTheme).onSkin(function() if band.Parent then apply() end end) end)
	return band
end

return TitleBand
