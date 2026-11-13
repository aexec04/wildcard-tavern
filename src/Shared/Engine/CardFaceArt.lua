--[[
	Shared/Engine/CardFaceArt.lua
	Picks the neutral card face picture: the painted ivory face (PlaySceneArt card_face_ivory_b) when its
	Image id is recorded, else "" so the card draws its flat ivory fill. Never doubles the rbxassetid:// prefix.
]]
local CardFaceArt = {}

CardFaceArt.KEY = "card_face_ivory_b"
CardFaceArt.FLAT_IVORY = { 250, 245, 235 }

function CardFaceArt.resolve(map)
	local raw = type(map) == "table" and map[CardFaceArt.KEY] or nil
	if type(raw) ~= "string" then return "" end
	local digits = raw:match("(%d+)$")
	if not digits or digits == "0" then return "" end
	return "rbxassetid://" .. digits
end

return CardFaceArt
