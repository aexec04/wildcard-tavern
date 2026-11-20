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

-- c: the card record from PatronRow (c.float, c.body); empty: true when no Patron stands here; z: the card's base ZIndex.
function M.sync(c, empty, z)
	if not ok or not c or not c.float or hasFacePic then return end
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
	if empty then c.body.BackgroundTransparency = 1 end
end

return M
