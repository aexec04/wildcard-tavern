--[[ Painted frame for an EMPTY Patron seat (Gameplay v2 table): the painted patron_slot picture (Engine/TavernStyle.PAINTED) behind the
faint ornament. An owned seat shows its own cut card, so the frame is hidden there. If the picture is missing or does not load the
flat quiet slot comes back (TavernKit.painted). No tweens. ]]
local M = {}

local ok, Kit = pcall(function() return require(script.Parent.TavernKit) end)
-- the painted seat face (PatronRow's SeatFacePicture) replaces this back panel when its picture id exists
local hasFacePic = false
pcall(function()
	local id = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ConceptTArt")).ct_seat_face
	hasFacePic = id ~= nil and id ~= ""
end)

-- Per Card Set (Client/SetInk): an accent outline around the seat and a set plate under the flat slot; classic draws neither.
local function setEdge(c, z)
	local ink = nil
	pcall(function() ink = require(script.Parent.SetInk).get() end)
	local edge = c.float:FindFirstChild("SetSeatEdge")
	if not ink then
		if edge then edge.Visible = false end
		return nil
	end
	if not edge then
		edge = Instance.new("Frame")
		edge.Name = "SetSeatEdge"
		edge.Size = UDim2.fromScale(1, 1)
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		edge.Active = false
		edge.ZIndex = (z or 1) + 3
		edge.Parent = c.float
		local ec = Instance.new("UICorner"); ec.CornerRadius = UDim.new(0, 8); ec.Parent = edge
		local es = Instance.new("UIStroke"); es.Name = "Edge"; es.Thickness = 2; es.Parent = edge
	end
	edge.Edge.Color = ink.accent
	edge.Visible = true
	return ink
end

-- c: the card record from PatronRow (c.float, c.body); empty: true when no Patron stands here; z: the card's base ZIndex.
function M.sync(c, empty, z)
	if not ok or not c or not c.float then return end
	local ink = setEdge(c, z)
	if hasFacePic then return end
	local back = c.float:FindFirstChild("SeatBack")
	if not back then
		if not empty then return end
		back = Instance.new("Frame")
		back.Name = "SeatBack"
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = Color3.fromRGB(56, 37, 25)
		back.BackgroundTransparency = 0.45
		back.BorderSizePixel = 0
		back.Active = false
		back.ZIndex = (z or 1) + 1
		back.Parent = c.float
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 8)
		rc.Parent = back
		pcall(function() Kit.painted(back, "patron_slot") end)
	end
	back.Visible = empty and true or false
	if ink then back.BackgroundColor3 = ink.plate else back.BackgroundColor3 = Color3.fromRGB(56, 37, 25) end
	if empty then c.body.BackgroundTransparency = 1 end
end

return M
