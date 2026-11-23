--[[
	Shared/Tests/LiveReadability.lua
	Test helper: reads a BUILT screen (a FakeGui tree) and lists what a player would struggle with, from the live instances and
	not from layout tables: text under 14 px (after UIScale), body text under 4.5 to 1 and 20 px+ headings under 3 to 1 against the
	plate that really sits behind the label, buttons under 44 px tall, rects off the screen, and text that cannot fit its own label.
	  audit(root, w, h, opts) -> { "finding text", ... }
	  opts.paintedOk(label)   true when a label may sit straight on a painted picture (it must then carry a dark stroke)
	  opts.skip(inst)         true to leave an instance out
]]

local Engine = script.Parent.Parent.Engine
local S = require(Engine.TavernStyle)
local TextFit = require(Engine.TextFit)

local M = {}

local function rgb(c)
	if c == nil or c.R == nil then return { 27, 42, 53 } end -- Roblox's own default text colour
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local DEFAULT_PLATE = { R = 163 / 255, G = 162 / 255, B = 165 / 255 } -- Roblox's own default plate colour when none is set

local function isGui(i)
	local c = i.ClassName
	return c == "Frame" or c == "TextLabel" or c == "TextButton" or c == "ImageLabel" or c == "ImageButton" or c == "ScrollingFrame"
end

local function shown(i)
	local p = i
	while p do
		if p.Visible == false then return false end
		p = p.Parent
	end
	return true
end

local function scaleOf(i)
	local k, p = 1, i
	while p do
		for _, c in ipairs(p:GetChildren()) do
			if c.ClassName == "UIScale" and c.Scale then k = k * c.Scale end
		end
		p = p.Parent
	end
	return k
end

local function path(i)
	local parts, p = {}, i
	while p and p.Parent do
		table.insert(parts, 1, p.Name)
		p = p.Parent
	end
	return table.concat(parts, ".")
end

-- the nearest ancestor (or the label itself) that paints a mostly solid plate; nil = it sits on a picture or the bare screen
local function plateOf(i)
	local p = i
	while p do
		if isGui(p) and (p.BackgroundTransparency or 0) <= 0.4 then return p end
		if p.ClassName == "ImageLabel" and p.Image and p.Image ~= "" and p ~= i then return nil end
		p = p.Parent
	end
	return nil
end

function M.audit(root, w, h, opts)
	opts = opts or {}
	local out = { seen = 0, buttons = 0 }
	local function add(i, why) out[#out + 1] = path(i) .. ": " .. why end
	-- a scrolling root may be taller than the window: a rect only has to sit inside its canvas, and reach it by scrolling
	local maxY = h
	if root.ClassName == "ScrollingFrame" and root.CanvasSize and root.CanvasSize.Y.Offset > h then maxY = root.CanvasSize.Y.Offset end
	for _, i in ipairs(root:GetDescendants()) do
		if isGui(i) and shown(i) and not (opts.skip and opts.skip(i)) then
			local pos, size = i.AbsolutePosition, i.AbsoluteSize
			local k = scaleOf(i)
			local isText = (i.ClassName == "TextLabel" or i.ClassName == "TextButton") and (i.Text or "") ~= "" and (i.TextTransparency or 0) < 1
			local isButton = i.ClassName == "TextButton" or i.ClassName == "ImageButton"
			if pos and size and size.X > 0 and size.Y > 0 then
				if isText then out.seen = out.seen + 1 end
				if isButton and (i.Text or "") ~= "" then out.buttons = out.buttons + 1 end
				local ps = i.Parent and i.Parent.AbsoluteSize
				-- a rect must be on the screen (scaled children are measured through their UIScale)
				if (isText or isButton) and (pos.X < -1 or pos.Y < -1 or pos.X + size.X * k > w + 1 or pos.Y + size.Y * k > maxY + 1) then
					add(i, string.format("off screen (%.0f,%.0f %.0fx%.0f at scale %.2f in %.0fx%.0f)", pos.X, pos.Y, size.X, size.Y, k, w, h))
				end
				if isButton and i.Visible ~= false and size.Y * k < 43.5 and i.Name ~= "CloseX" then
					add(i, string.format("touch target %.0f px tall (%.0f at scale %.2f), 44 needed", size.Y * k, size.Y, k))
				end
				if isText then
					local px = i.TextSize * k
					if px < 13.5 then add(i, string.format("text %.1f px, 14 needed", px)) end
					if not i.TextScaled and not i.TextWrapped and TextFit.width(i.Text, i.TextSize) > size.X + 2 then
						add(i, string.format("text \"%s\" at %d px needs about %.0f px, the label is %.0f", i.Text, i.TextSize, TextFit.width(i.Text, i.TextSize), size.X))
					end
					local plate = plateOf(i)
					local fg = rgb(i.TextColor3)
					if plate then
						local ratio = S.contrast(rgb(plate.BackgroundColor3 or DEFAULT_PLATE), fg)
						local need = px >= 20 and 3 or 4.5
						if ratio < need then add(i, string.format("contrast %.2f on %s, %.1f needed", ratio, path(plate), need)) end
					elseif not (opts.paintedOk and opts.paintedOk(i)) then
						add(i, "sits on a painted picture without a plate")
					end
				end
			end
		end
	end
	-- two sibling buttons never overlap (a share box that is meant to cover cells is a Frame, not a button)
	local function overlapCheck(node)
		local btns = {}
		for _, c in ipairs(node:GetChildren()) do
			if (c.ClassName == "TextButton" or c.ClassName == "ImageButton") and shown(c) and c.AbsoluteSize and c.AbsoluteSize.X > 0 then btns[#btns + 1] = c end
			overlapCheck(c)
		end
		for a = 1, #btns do
			for b = a + 1, #btns do
				local A, B = btns[a], btns[b]
				local ox = math.min(A.AbsolutePosition.X + A.AbsoluteSize.X, B.AbsolutePosition.X + B.AbsoluteSize.X) - math.max(A.AbsolutePosition.X, B.AbsolutePosition.X)
				local oy = math.min(A.AbsolutePosition.Y + A.AbsoluteSize.Y, B.AbsolutePosition.Y + B.AbsoluteSize.Y) - math.max(A.AbsolutePosition.Y, B.AbsolutePosition.Y)
				if ox > 1 and oy > 1 and not (opts.skip and (opts.skip(A) or opts.skip(B))) then add(A, "overlaps its sibling " .. B.Name) end
			end
		end
	end
	overlapCheck(root)
	return out
end

return M
