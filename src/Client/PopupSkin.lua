--[[
	Client/PopupSkin.lua
	Small popups (Confirm, Choice, Quit, Restart) wear the equipped Card Set: a dark wood panel takes the set fill, edge and cream ink, a
	parchment sheet takes the set paper tint and dark ink, both 7:1 (CosmeticSets.popupStyleOf). Classic restores what the caller passed in.
	Colours only: no layout, no tween, so Calm mode and Reduce motion need nothing extra. Plates come from TavernKit.setPlateButton at the call site.

	PopupSkin.dark(panel, stroke, labels, classic)   classic = { plate, edge }; labels = { { label, classicInk }, ... }
	PopupSkin.paper(sheet, gradient, stroke, labels, classic)   classic = { top, bottom, edge }; labels = { { label, classicInk }, ... }
	Both return the apply function (it runs now and again on every skin change).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PopupSkin = {}

local function style()
	local s
	pcall(function()
		local CS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
		s = CS.popupStyleOf(require(script.Parent.TavernKit).plateSetId())
	end)
	return s
end

local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local function inkAll(labels, set)
	for _, pair in ipairs(labels or {}) do
		local l = pair[1]
		if l and l.Parent then
			l.TextColor3 = set and c3(set) or pair[2]
			l.TextTransparency = 0
		end
	end
end

function PopupSkin.dark(panel, stroke, labels, classic)
	local function apply()
		local s = style()
		local d = s and s.dark
		if panel then panel.BackgroundColor3 = d and c3(d.fill) or classic.plate end
		if stroke then stroke.Color = d and c3(d.edge) or classic.edge end
		inkAll(labels, d and d.ink)
	end
	apply()
	pcall(function() require(script.Parent.HudTheme).onSkin(function() if panel and panel.Parent then apply() end end) end)
	return apply
end

function PopupSkin.paper(sheet, gradient, stroke, labels, classic)
	local function apply()
		local s = style()
		local p = s and s.paper
		if gradient then
			gradient.Color = ColorSequence.new(p and c3(p.top) or classic.top, p and c3(p.bottom) or classic.bottom)
		end
		if stroke then stroke.Color = p and c3(p.edge) or classic.edge end
		inkAll(labels, p and p.ink)
	end
	apply()
	pcall(function() require(script.Parent.HudTheme).onSkin(function() if sheet and sheet.Parent then apply() end end) end)
	return apply
end

return PopupSkin
