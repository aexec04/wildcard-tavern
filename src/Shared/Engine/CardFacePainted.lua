--[[
	Shared/Engine/CardFacePainted.lua
	Which fully painted card face a card wears: all 52 in the Concept T style (ConceptTCardFaces, keys <rank>_<suit>,
	rank a, 2 to 10, j, q, k and suit spades, hearts, diamonds, clubs). The picture carries its own rank, suit and pips.
	A missing id returns "" and CardFace keeps the code-drawn face (corner index, real pip layout, court figure).
	Used only on the Classic Tavern (ivory alone) skin and never with Colorblind Suits, which needs its own suit letter.
]]
local CardFacePainted = {}

CardFacePainted.SUITS = { ["♠"] = "spades", ["♥"] = "hearts", ["♦"] = "diamonds", ["♣"] = "clubs" }
CardFacePainted.RANKS = { A = "a", J = "j", Q = "q", K = "k" }
for n = 2, 10 do CardFacePainted.RANKS[tostring(n)] = tostring(n) end

function CardFacePainted.key(rankText, suitText)
	local r, s = CardFacePainted.RANKS[tostring(rankText)], CardFacePainted.SUITS[suitText]
	if not r or not s then return nil end
	return r .. "_" .. s
end

-- `map` is the generated ConceptTCardFaces table. Returns "rbxassetid://<digits>" or "".
function CardFacePainted.resolve(map, rankText, suitText)
	local key = CardFacePainted.key(rankText, suitText)
	local raw = key and type(map) == "table" and map[key] or nil
	if type(raw) ~= "string" then return "" end
	local digits = raw:match("(%d+)$")
	if not digits or digits == "0" then return "" end
	return "rbxassetid://" .. digits
end

return CardFacePainted
