--[[
	Client/ConceptTSkin.lua
	Applies the Concept T look (Engine/ConceptTSkin numbers) to the Shop, Collection and round clear screens.
	  ConceptTSkin.title(label)                       serif cream title with a dark outline, text never under 15 px
	  ConceptTSkin.pricePill(tag, price, affordable, z) painted plain pill plate, coin and number inside a price tag
	No tweens anywhere, so Calm mode and Reduce Motion are unchanged. A missing art id keeps the old look.
]]
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Skin = require(Engine:WaitForChild("ConceptTSkin"))
local Art = require(Engine:WaitForChild("ConceptTArt"))

local ConceptTSkin = {}

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

function ConceptTSkin.title(label, color)
	local font = Enum.Font[Skin.TITLE_FONT]
	if font then label.Font = font end
	label.TextColor3 = color and rgb(color) or rgb(Skin.TITLE_COLOR)
	label.TextStrokeColor3 = rgb(Skin.TITLE_STROKE)
	label.TextStrokeTransparency = 0.25
	label.TextTransparency = 0
	if label.TextSize < Skin.MIN_TEXT then label.TextSize = Skin.MIN_TEXT end
	return label
end

-- Draws the plain pill plate behind a price: returns the number label, or nil when no art is recorded.
function ConceptTSkin.pricePill(tag, price, affordable, z)
	local id = Art[Skin.PILL_ART]
	if not id or id == "" then return nil end
	for _, child in ipairs(tag:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("UIStroke") or child:IsA("UICorner") then child:Destroy() end
	end
	tag.BackgroundTransparency = 1
	local w, h = tag.Size.X.Offset, tag.Size.Y.Offset
	local L = Skin.priceLayout(w, h)
	local plate = Instance.new("ImageLabel")
	plate.Name = "ConceptTPill"
	plate.BackgroundTransparency = 1
	plate.Size = UDim2.fromScale(1, 1)
	plate.Image = id
	plate.ScaleType = Enum.ScaleType.Stretch
	plate.ZIndex = z
	plate.Parent = tag
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.Position = UDim2.fromOffset(L.coin.x, L.coin.y)
	coin.Size = UDim2.fromOffset(L.coin.w, L.coin.h)
	coin.BackgroundColor3 = Color3.fromRGB(246, 208, 96)
	coin.ZIndex = z + 1
	coin.Parent = tag
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0.5, 0); cc.Parent = coin
	local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(150, 100, 30); cs.Thickness = 2; cs.Parent = coin
	local n = Instance.new("TextLabel")
	n.Name = "Price"
	n.BackgroundTransparency = 1
	n.Position = UDim2.fromOffset(L.text.x, L.text.y)
	n.Size = UDim2.fromOffset(L.text.w, L.text.h)
	n.Font = Enum.Font.GothamBold
	n.TextSize = L.textSize
	n.Text = tostring(math.floor(price))
	n.TextColor3 = rgb(Skin.priceColor(affordable))
	n.TextStrokeColor3 = rgb(Skin.TITLE_STROKE)
	n.TextStrokeTransparency = 0.4
	n.TextTransparency = 0
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.ZIndex = z + 2
	n.Parent = tag
	return n
end

return ConceptTSkin
