--[[
	Client/BossGlyph.lua
	Draws a drawn rule icon (Engine/BossRuleGlyphs, shapes only) inside the boss rule chip's icon label, or clears it again.
	Static: no tween, so Calm mode and Reduce motion need nothing. The label keeps its letter icon for every other boss.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Glyphs = require(Engine:WaitForChild("BossRuleGlyphs"))

local M = {}

-- icon: the BossIcon TextLabel. Returns true when a drawn glyph is showing (the label text is then blank on a dark plate).
function M.apply(icon, bossId, edge)
	local old = icon:FindFirstChild("Glyph")
	if old then old:Destroy() end
	local g = Glyphs.get(bossId)
	if not g then
		local oldStroke = icon:FindFirstChild("GlyphEdge")
		if oldStroke then oldStroke:Destroy() end
		return false
	end
	icon.Text = ""
	icon.BackgroundColor3 = Color3.fromRGB(Glyphs.PLATE[1], Glyphs.PLATE[2], Glyphs.PLATE[3])
	local stroke = icon:FindFirstChild("GlyphEdge")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "GlyphEdge"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 1.5
		stroke.Parent = icon
	end
	if edge then stroke.Color = Color3.fromRGB(edge[1], edge[2], edge[3]) end
	local holder = Instance.new("Frame")
	holder.Name = "Glyph"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = icon.ZIndex + 1
	holder.Parent = icon
	for _, s in ipairs(g.shapes) do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Active = false
		f.BackgroundColor3 = Color3.fromRGB(s.color[1], s.color[2], s.color[3])
		f.Size = UDim2.fromScale(s.w, s.h)
		f.Position = UDim2.fromScale(s.x, s.y)
		f.Rotation = s.rot or 0
		f.ZIndex = icon.ZIndex + 2
		if s.kind == "round" then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
		end
		f.Parent = holder
	end
	return true
end

return M
