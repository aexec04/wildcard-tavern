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
	local follow = opts and opts.follow -- the page places the title itself: the plate wraps the label, padded, clamped to the panel
	function out.relayout()
		local sz = panel.AbsoluteSize
		if sz.X < 100 then return end
		if follow then
			local o = titleLabel.AbsolutePosition - panel.AbsolutePosition
			local x0 = math.max(TomeHeader.SIDE, o.X - TomeHeader.PAD)
			local x1 = math.min(sz.X - TomeHeader.SIDE, o.X + titleLabel.AbsoluteSize.X + TomeHeader.PAD)
			put(out.plates.title, { x = x0, y = o.Y - 2, w = math.max(0, x1 - x0), h = titleLabel.AbsoluteSize.Y + 4 })
			return
		end
		local L = TomeHeader.layout(sz.X, sz.Y, subLabel ~= nil)
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
