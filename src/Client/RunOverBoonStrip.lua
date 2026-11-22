--[[
	Client/RunOverBoonStrip.lua
	The Run Over screen's Night boons strip (Engine/RunOverBoons for the words, Engine/RunOverLayout for the rects): a gold label, one row of
	44 px chips (painted boon art with the emoji as fallback, the equipped Card Set's plate and accent) and a two line name box. Tapping a
	chip names that boon in the box. Hidden when no boon was taken. No tween, so Calm mode and Reduce motion need nothing extra.

	RunOverBoonStrip.new(content, z)      -> strip, parented to the Run Over content frame, hidden
	strip.setTone(tone)                   tone = { gold, text } colours for the paper or the dark wood
	strip.show(view, r)                   view = RunOverBoons.view(...), r = RunOverLayout rects (boonsLabel, boons, boonName); nil view hides
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunOverBoons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RunOverBoons"))

local M = {}

local function place(obj, r)
	obj.Position = UDim2.fromOffset(math.floor(r.x + 0.5), math.floor(r.y + 0.5))
	obj.Size = UDim2.fromOffset(math.floor(r.w + 0.5), math.floor(r.h + 0.5))
end

local function text(parent, name, size, z)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Merriweather
	l.TextSize = size
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.Active = false
	l.ZIndex = z
	l.Visible = false
	l.Parent = parent
	return l
end

function M.new(content, z)
	z = z or 22
	local strip = {}
	local label = text(content, "BoonsLabel", 18, z)
	label.Font = Enum.Font.GothamBold
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local holder = Instance.new("Frame")
	holder.Name = "Boons"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Visible = false
	holder.ZIndex = z
	holder.Parent = content
	local nameLine = text(content, "BoonName", 16, z)
	local tone

	function strip.setTone(t)
		tone = t
		label.TextColor3 = t.gold
		nameLine.TextColor3 = t.text
	end

	function strip.show(view, r)
		for _, c in ipairs(holder:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		if not view or not r or not r.boons then
			label.Visible, holder.Visible, nameLine.Visible = false, false, false
			return
		end
		label.Text = view.label
		nameLine.Text = view.idle
		place(label, r.boonsLabel)
		place(holder, r.boons)
		place(nameLine, r.boonName)
		label.Visible, holder.Visible, nameLine.Visible = true, true, true
		if tone then strip.setTone(tone) end
		local ink
		pcall(function() ink = require(script.Parent.SetInk).get() end)
		local chipSize, gap, cols = r.boons.chip, r.boons.gap, r.boons.cols
		for i, chip in ipairs(view.chips) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local b = Instance.new("TextButton")
			b.Name = "Boon_" .. chip.id
			b.Position = UDim2.fromOffset(col * (chipSize + gap), row * (chipSize + gap))
			b.Size = UDim2.fromOffset(chipSize, chipSize)
			b.BackgroundColor3 = ink and ink.plate or Color3.fromRGB(40, 30, 22)
			b.AutoButtonColor = true
			b.Text = ""
			b.ZIndex = z + 1
			b.Parent = holder
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
			local s = Instance.new("UIStroke"); s.Color = ink and ink.accent or Color3.fromRGB(200, 160, 84); s.Thickness = 2
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = b
			local host = Instance.new("Frame")
			host.Name = "IconArtHost"
			host.BackgroundTransparency = 1
			host.Active = false
			host.Size = UDim2.fromScale(1, 1)
			host.ZIndex = z + 2
			host.Parent = b
			local glyph = text(host, "Glyph", 24, z + 2) -- the emoji stays until the painted icon loads
			glyph.Visible = true
			glyph.Size = UDim2.fromScale(1, 1)
			glyph.Font = Enum.Font.GothamBold
			glyph.TextXAlignment = Enum.TextXAlignment.Center
			glyph.TextYAlignment = Enum.TextYAlignment.Center
			glyph.TextColor3 = Color3.fromRGB(250, 240, 220)
			glyph.Text = chip.icon
			pcall(function() require(script.Parent.ArtIcon).apply(host, "boon_icons", chip.id, glyph, { cornerRadius = 8, zIndex = z + 3 }) end)
			b.MouseButton1Click:Connect(function()
				nameLine.Text = chip.line
			end)
		end
	end

	return strip
end

return M
