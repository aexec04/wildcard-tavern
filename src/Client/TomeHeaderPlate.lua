--[[
	Client/TomeHeaderPlate.lua
	Draws the shared Tome page header (Engine/TomeHeader): a dark wood plate behind the page title and one behind its info line, with the
	text inset by 16 px. The plates sit under the labels (lower ZIndex), outside any UIListLayout parent, and follow the panel size.

	TomeHeaderPlate.attach(panel, pageId, titleLabel, subLabel) -> { relayout = fn, plates = { title, sub } }
	The labels keep their own Text, Font and colour; this only places them and draws the plates.
]]

local TomeHeader = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TomeHeader"))

local M = {}

local function plate(panel, name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.fromRGB(TomeHeader.PLATE[1], TomeHeader.PLATE[2], TomeHeader.PLATE[3])
	f.BackgroundTransparency = TomeHeader.PLATE_ALPHA
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(176, 132, 48)
	s.Thickness = 1
	s.Parent = f
	f.Parent = panel
	return f
end

local function put(frame, r)
	frame.Position, frame.Size = UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h)
end

function M.attach(panel, pageId, titleLabel, subLabel, opts)
	local page = TomeHeader.page(pageId)
	if not page then return nil end
	local z = math.min(titleLabel.ZIndex, subLabel and subLabel.ZIndex or titleLabel.ZIndex) - 1
	local out = { plates = {} }
	out.plates.title = plate(panel, "TomeTitlePlate", z)
	if subLabel then out.plates.sub = plate(panel, "TomeSubPlate", z) end
	titleLabel.TextColor3 = Color3.fromRGB(page.titleInk[1], page.titleInk[2], page.titleInk[3])
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextSize = math.max(titleLabel.TextSize, TomeHeader.MIN_TEXT)
	if subLabel then
		subLabel.TextColor3 = Color3.fromRGB(page.subInk[1], page.subInk[2], page.subInk[3])
		subLabel.TextSize = math.max(subLabel.TextSize, TomeHeader.MIN_TEXT)
		subLabel.TextXAlignment = Enum.TextXAlignment.Center
	end
	-- the equipped Card Set's plate fill, accent edge and cream ink at 7:1 (CosmeticSets.hintStyleOf); classic keeps the page colours above
	pcall(function()
		local HintSkin = require(script.Parent.HintSkin)
		local plateFill = Color3.fromRGB(TomeHeader.PLATE[1], TomeHeader.PLATE[2], TomeHeader.PLATE[3])
		local edge = Color3.fromRGB(176, 132, 48)
		HintSkin.bind(out.plates.title, out.plates.title:FindFirstChildOfClass("UIStroke"), { titleLabel },
			{ plate = plateFill, edge = edge, ink = Color3.fromRGB(page.titleInk[1], page.titleInk[2], page.titleInk[3]) })
		if subLabel then
			HintSkin.bind(out.plates.sub, out.plates.sub:FindFirstChildOfClass("UIStroke"), { subLabel },
				{ plate = plateFill, edge = edge, ink = Color3.fromRGB(page.subInk[1], page.subInk[2], page.subInk[3]) })
		end
	end)
	local follow = opts and opts.follow -- the page places the title itself: the plate wraps the label, padded, clamped to the panel
	function out.relayout()
		local sz = panel.AbsoluteSize
		if sz.X < 100 then return end
		if follow then
			local o = titleLabel.AbsolutePosition - panel.AbsolutePosition
			local x0 = math.max(TomeHeader.SIDE, o.X - TomeHeader.PAD)
			local x1 = math.min(sz.X - TomeHeader.SIDE - 36, o.X + titleLabel.AbsoluteSize.X + TomeHeader.PAD) -- the round close X sits over the right end, so the plate stops 36 px short on both sides
			x0 = math.max(x0, TomeHeader.SIDE + 36)
			put(out.plates.title, { x = x0, y = o.Y - 2, w = math.max(0, x1 - x0), h = titleLabel.AbsoluteSize.Y + 4 })
			return
		end
		local L = TomeHeader.layout(sz.X, sz.Y, subLabel ~= nil)
		if true then -- every size (phone and tablet showed it): the round close X sits over the plates' right end, so both plates give up the same 36 px each side
			local inset = 36
			for _, r in ipairs({ L.title, L.sub }) do r.x, r.w = r.x + inset, math.max(0, r.w - 2 * inset) end
		end
		put(out.plates.title, L.title)
		put(titleLabel, TomeHeader.textRect(L.title))
		if subLabel and L.sub then
			put(out.plates.sub, L.sub)
			put(subLabel, TomeHeader.textRect(L.sub))
		end
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(out.relayout)
	if follow then titleLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(out.relayout) end
	out.relayout()
	return out
end

return M
