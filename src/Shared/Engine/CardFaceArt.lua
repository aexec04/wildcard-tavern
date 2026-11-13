--[[
	Shared/Engine/CardFaceArt.lua
	Picks the neutral card face picture: the painted ivory face (PlaySceneArt card_face_ivory_b) when its
	Image id is recorded, else "" so the card draws its flat ivory fill. Never doubles the rbxassetid:// prefix.
]]
local CardFaceArt = {}

CardFaceArt.KEY = "card_face_ivory_b"
CardFaceArt.FLAT_IVORY = { 250, 245, 235 }

-- The 1024x1536 picture has an opaque near-white checker margin about 54 px wide outside its gold border (measured
-- from art-wip/play_scene/card_face_ivory_b.png); drawing it whole shows pale square blocks at the card corners.
-- The ImageLabel shows only the inside of this crop.
CardFaceArt.SIZE = { 1024, 1536 }
CardFaceArt.CROP = 60
CardFaceArt.CORNER_RADIUS = 6

function CardFaceArt.rect()
	local c, s = CardFaceArt.CROP, CardFaceArt.SIZE
	return { x = c, y = c, w = s[1] - 2 * c, h = s[2] - 2 * c }
end

function CardFaceArt.resolve(map)
	local raw = type(map) == "table" and map[CardFaceArt.KEY] or nil
	if type(raw) ~= "string" then return "" end
	local digits = raw:match("(%d+)$")
	if not digits or digits == "0" then return "" end
	return "rbxassetid://" .. digits
end

-- True when a set skin should show the ivory face alone: a neutral skin (Classic Tavern or any set without its
-- own face style) and a recorded face id. Such a skin draws no SetSkinPaper, SetSkinCourt or SetSkinFrame.
function CardFaceArt.ivoryAlone(skin, faceId)
	return type(skin) == "table" and skin.neutral == true and type(faceId) == "string" and faceId ~= ""
end

return CardFaceArt
