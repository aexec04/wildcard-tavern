--[[
	Engine/SelfCheck.lua
	Visual regression guard: pure rules over plain descriptors of the visible text on a screen. Client/SelfCheck builds the
	descriptors from the live GuiObjects (Studio, DebugGoto "selfcheck"); tests feed it hand made ones.

	A node is { path, text, textTransparency, textColor = {r,g,b} 0..1, plateColor = {r,g,b} or nil, z, plateZ (highest ZIndex of
	the label's plate siblings, nil if none), rect = {x,y,w,h}, parentRect = {x,y,w,h} or nil }.

	check(nodes) -> { "warning text", ... } for:
	  - text transparency above 0.5
	  - contrast below 3:1 against the plate behind it
	  - the label ZIndex not above its plate children (a plate that draws over its own words)
	  - the label rect outside its parent rect (1 px of slack)
	  - two labels overlapping by more than 20 percent of the smaller one (a label and its own ancestor are never a pair)
]]

local M = {}

M.MAX_TRANSPARENCY = 0.5
M.MIN_CONTRAST = 3
M.MAX_OVERLAP = 0.2
M.SLACK = 1

local function lin(c)
	if c <= 0.03928 then return c / 12.92 end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end

function M.contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

local function overlapArea(a, b)
	local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if w <= 0 or h <= 0 then return 0 end
	return w * h
end

local function isAncestor(a, b) -- path a is a prefix of path b
	return #a < #b and b:sub(1, #a + 1) == a .. "."
end

function M.check(nodes)
	local out = {}
	local function warn(n, s) out[#out + 1] = string.format("%s: %s", n.path, s) end
	for _, n in ipairs(nodes) do
		if (n.textTransparency or 0) > M.MAX_TRANSPARENCY then
			warn(n, string.format("text transparency %.2f, above %.1f", n.textTransparency, M.MAX_TRANSPARENCY))
		elseif n.plateColor and n.textColor then
			local c = M.contrast(n.textColor, n.plateColor)
			if c < M.MIN_CONTRAST then warn(n, string.format("contrast %.2f:1 on its plate, under %d:1", c, M.MIN_CONTRAST)) end
		end
		if n.plateZ and n.z and n.plateZ >= n.z then
			warn(n, string.format("label ZIndex %d is not above its plate children (%d)", n.z, n.plateZ))
		end
		local r, p = n.rect, n.parentRect
		if r and p and (r.x < p.x - M.SLACK or r.y < p.y - M.SLACK or r.x + r.w > p.x + p.w + M.SLACK or r.y + r.h > p.y + p.h + M.SLACK) then
			warn(n, "label rect reaches outside its parent")
		end
	end
	for i = 1, #nodes do
		for j = i + 1, #nodes do
			local a, b = nodes[i], nodes[j]
			if a.rect and b.rect and (a.textTransparency or 0) <= M.MAX_TRANSPARENCY and (b.textTransparency or 0) <= M.MAX_TRANSPARENCY
				and not isAncestor(a.path, b.path) and not isAncestor(b.path, a.path) then
				local small = math.min(a.rect.w * a.rect.h, b.rect.w * b.rect.h)
				if small > 0 and overlapArea(a.rect, b.rect) / small > M.MAX_OVERLAP then
					out[#out + 1] = string.format("%s overlaps %s by more than %d percent", a.path, b.path, M.MAX_OVERLAP * 100)
				end
			end
		end
	end
	return out
end

return M
