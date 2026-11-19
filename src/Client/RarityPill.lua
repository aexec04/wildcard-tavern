--[[
	Client/RarityPill.lua
	The rarity label under a Patron card as real UI: a fully rounded Frame, a 1.5 px stroke in the tier colour, a flat fill with a
	Color-only gradient, the tier word in a serif with a dark outline and the shape marker inside at the left. No image, so nothing
	is stretched or blurry. Parented to the card's slot (survives a clone), static, no tweens. Numbers: Engine/RarityPillSpec.

	RarityPill.set(slot, tier, cardW, name) -> Frame    name defaults to "CTLabel"; the pill is centred under the card
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spec = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RarityPillSpec"))

local M = {}

local function rgb(c) return Color3.fromRGB(c[1], c[2], c[3]) end

function M.set(slot, tier, cardW, name)
	name = name or "CTLabel"
	local s = Spec.spec(tier, cardW)
	local pill = slot:FindFirstChild(name)
	if pill and not pill:IsA("Frame") then pill:Destroy(); pill = nil end -- an older image label
	if not pill then
		pill = Instance.new("Frame")
		pill.Name = name
		pill.BorderSizePixel = 0
		pill.Active = false
		pill.ZIndex = 12
		pill.Parent = slot
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = pill
		local st = Instance.new("UIStroke"); st.Thickness = Spec.STROKE; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = pill
		local g = Instance.new("UIGradient"); g.Rotation = 90; g.Parent = pill -- Color only, never Transparency
		local t = Instance.new("TextLabel")
		t.Name = "Word"
		t.BackgroundTransparency = 1
		t.TextTransparency = 0
		t.TextStrokeTransparency = 0.25
		t.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
		t.TextScaled = false
		t.ZIndex = 13
		t.Parent = pill
	end
	local fill = rgb(s.fill)
	pill.BackgroundColor3 = fill
	pill.BackgroundTransparency = 0
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 1, 2)
	pill.Size = UDim2.fromOffset(s.w, s.h)
	pill.Visible = true
	pill:FindFirstChildOfClass("UIStroke").Color = rgb(s.stroke)
	pill:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(fill:Lerp(Color3.new(1, 1, 1), 0.12), fill:Lerp(Color3.new(0, 0, 0), 0.12))
	local t = pill:FindFirstChild("Word")
	t.Font = Enum.Font.GothamBold
	pcall(function() t.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold) end)
	t.TextSize = s.textSize
	t.TextColor3 = rgb(s.ink)
	t.Text = s.word
	t.Position = UDim2.fromOffset(s.text.x, 0)
	t.Size = UDim2.fromOffset(s.text.w, s.h)
	pcall(function() require(script.Parent.RarityShape).set(pill, tier, s.marker.px, s.marker.x) end)
	return pill
end

return M
