--[[
	Shared/Engine/CourtFaceArt.lua
	Which painted court figure a face card wears: K, Q and J in each suit (ConceptTCardArt, keys court_<k|q|j>_<suit>).
	The figure is the character only; the corner rank, the small suits and the pips stay code-drawn, so a wrong rank or
	suit can never be baked into a picture. A missing id returns "" and the card keeps its big suit symbol.
]]
local CourtFaceArt = {}

CourtFaceArt.SUITS = { ["♠"] = "spades", ["♥"] = "hearts", ["♦"] = "diamonds", ["♣"] = "clubs" }
CourtFaceArt.RANKS = { K = "k", Q = "q", J = "j" }

-- Card fractions (centre anchored). The ivory index sits at y 0.06 to 0.36 on the left and 0.825 to 0.94 on the right,
-- so the figure (square, Fit) stays between them.
CourtFaceArt.LAYOUT = { x = 0.54, y = 0.56, w = 0.70, h = 0.70 } -- the figure fills about 60 percent of the face like the reference; the corner index draws above it

function CourtFaceArt.key(rankText, suitText)
	local r, s = CourtFaceArt.RANKS[rankText], CourtFaceArt.SUITS[suitText]
	if not r or not s then return nil end
	return "court_" .. r .. "_" .. s
end

-- `map` is the generated ConceptTCardArt table. Returns "rbxassetid://<digits>" or "".
function CourtFaceArt.resolve(map, rankText, suitText)
	local key = CourtFaceArt.key(rankText, suitText)
	local raw = key and type(map) == "table" and map[key] or nil
	if type(raw) ~= "string" then return "" end
	local digits = raw:match("(%d+)$")
	if not digits or digits == "0" then return "" end
	return "rbxassetid://" .. digits
end

return CourtFaceArt
