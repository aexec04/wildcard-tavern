--[[
	Client/HintSkin.lua
	Tooltips, the guided hint and the Next goal banner wear the equipped Card Set: plate fill tinted toward the accent, accent edge, cream ink that
	keeps 7:1 (CosmeticSets.hintStyleOf). Classic restores the colours the caller passed in. Colours only, no layout, no tweens.

	HintSkin.bind(plate, stroke, labels, classic)
	  classic = { plate = Color3, edge = Color3, ink = Color3 } the original look; labels = TextLabels that take the ink
	  returns the apply function (it also runs now and on every skin change)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HintSkin = {}

function HintSkin.bind(plate, stroke, labels, classic)
	local function apply()
		local style
		pcall(function()
			local CS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
			style = CS.hintStyleOf(require(script.Parent.TavernKit).plateSetId())
		end)
		local fill, edge, ink = classic.plate, classic.edge, classic.ink
		if style then
			fill = Color3.fromRGB(style.plate[1], style.plate[2], style.plate[3])
			edge = Color3.fromRGB(style.edge[1], style.edge[2], style.edge[3])
			ink = Color3.fromRGB(style.ink[1], style.ink[2], style.ink[3])
		end
		if plate then plate.BackgroundColor3 = fill end
		if stroke then stroke.Color = edge end
		for _, l in ipairs(labels or {}) do
			if l and l.Parent and ink then l.TextColor3 = ink end
		end
	end
	apply()
	pcall(function() require(script.Parent.HudTheme).onSkin(function() if plate and plate.Parent then apply() end end) end)
	return apply
end

return HintSkin
