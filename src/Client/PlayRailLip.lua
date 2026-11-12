--[[
	Client/PlayRailLip.lua
	Makes the hand sit IN the painted table instead of floating over it:
	  lipRect(p)            pure: the wood strip that covers the bottom 14 percent of the cards and the front half of the rail groove
	  install(root)         a "HandRailLip" wood strip in root (not in HandFrame: it is a UIListLayout parent), drawn above the cards
	  apply(lip, p, shown)  place it from PlayTableLayout.placement, nil hides it
	  addCardShadow(slot)   soft dark ellipse under a card (child of the card's slot, behind the card)
	  setShadow(slot, selected, lift)   stronger while selected, fades as the card lifts
]]

local PlayRailLip = {}

PlayRailLip.TUCK = 0.14 -- share of a card's height hidden behind the lip
PlayRailLip.CARD_H = 144 -- Engine/PlayTableLayout: cards are 144 px in the 176 px hand frame
PlayRailLip.WOOD = Color3.fromRGB(92, 58, 34) -- the table rail's base wood
PlayRailLip.Z = 20 -- above every card piece (all below 15), below the ghosts and popups

-- p = PlayTableLayout.placement result. Card bottoms sit on the middle of the rail groove (hand.y + HAND_H - CARD_PAD).
function PlayRailLip.lipRect(p)
	if not p then return nil end
	local cardBottom = p.hand.y + 176 - 16
	local top = math.floor(cardBottom - PlayRailLip.TUCK * PlayRailLip.CARD_H + 0.5)
	local bottom = math.floor(p.map.rail.y + p.map.rail.h + 0.5)
	local h = math.max(8, bottom - top)
	return { x = p.map.rail.x, y = top, w = p.map.rail.w, h = h }
end

-- The lip belongs to the play table only: it follows the hand and hides whenever the Counter, Round Select or Game Over covers it.
PlayRailLip.COVERS = { "Shop", "RoundSelect", "GameOver" }
function PlayRailLip.shouldShow(handVisible, coverVisible)
	return handVisible == true and coverVisible ~= true
end

function PlayRailLip.install(root)
	local lip = root:FindFirstChild("HandRailLip")
	if lip then return lip end
	lip = Instance.new("Frame")
	lip.Name = "HandRailLip"
	lip.BackgroundColor3 = PlayRailLip.WOOD
	lip.BorderSizePixel = 0
	lip.Active = false
	lip.ZIndex = PlayRailLip.Z
	lip.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = lip
	local grad = Instance.new("UIGradient") -- Color stops only
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 232, 205), Color3.fromRGB(190, 160, 130)) -- multiplies WOOD: a lit top fading to the rail's own tone, not near black
	grad.Rotation = 90
	grad.Parent = lip
	local edge = Instance.new("Frame") -- lighter top edge
	edge.Name = "TopEdge"
	edge.BackgroundColor3 = Color3.fromRGB(176, 128, 78)
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.Size = UDim2.new(1, 0, 0, 2)
	edge.ZIndex = PlayRailLip.Z + 1
	edge.Parent = lip
	lip.Parent = root
	return lip
end

function PlayRailLip.apply(lip, p, shown)
	local r = PlayRailLip.lipRect(p)
	if not (lip and r) then
		if lip then lip.Visible = false end
		return
	end
	lip.Position = UDim2.fromOffset(r.x, r.y)
	lip.Size = UDim2.fromOffset(r.w, r.h)
	lip.Visible = shown ~= false
end

function PlayRailLip.addCardShadow(slot)
	if slot:FindFirstChild("ContactShadow") then return end
	local s = Instance.new("Frame")
	s.Name = "ContactShadow"
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.new(0.5, 0, 1, 6) -- 6 px below the card's foot, on the felt
	s.Size = UDim2.new(0.9, 0, 0, 18)
	s.BackgroundColor3 = Color3.new(0, 0, 0)
	s.BackgroundTransparency = 0.7
	s.BorderSizePixel = 0
	s.Active = false
	s.ZIndex = 1 -- created before the card button, so the card draws over it
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = s
	s.Parent = slot
end

function PlayRailLip.setShadow(slot, selected, lift)
	if slot then slot:SetAttribute("Lifted", selected == true) end -- read by PlayMotion for the camera lean
	local s = slot and slot:FindFirstChild("ContactShadow")
	if not s then return end
	-- a lifted card's shadow shrinks and fades (numbers in Engine/PlayMotion.shadowFor)
	local tr, w = require(game:GetService("ReplicatedStorage").Shared.Engine.PlayMotion).shadowFor(selected == true)
	s.BackgroundTransparency = math.min(0.95, tr + (lift or 0) * 0.002)
	s.Size = UDim2.new(w, 0, 0, selected and 14 or 18)
end

return PlayRailLip
