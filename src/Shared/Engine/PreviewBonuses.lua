--[[
	Shared/Engine/PreviewBonuses.lua
	The one short line under the hand preview that names every active mark and Night boon bonus of the selected cards, for example
	"Gilded x2, Lucky, Warm Welcome +10%". Pure and tested; the numbers themselves are already inside the preview score.

	PreviewBonuses.line(view, cardIndices) -> string of 60 characters or less, or nil when nothing extra applies
	PreviewBonuses.rect(stage, text, plate) -> { x, y, w, h } a 20 px strip under the Score plate, nil when there is no room
]]

local Card = require(script.Parent.Card)
local NightBoons = require(script.Parent.NightBoons)

local PreviewBonuses = {}

PreviewBonuses.MAX_CHARS = 60
PreviewBonuses.H = 20
PreviewBonuses.CHAR_W = 8

local function boonPart(view)
	local def = NightBoons.active(view)
	if not def then return nil end
	local isFirstHand = view.roundStartHands ~= nil and view.handsRemaining == view.roundStartHands
	local pct = NightBoons.scorePct(view, isFirstHand)
	if pct <= 0 then return nil end
	return string.format("%s +%d%%", def.name, math.floor(pct))
end

function PreviewBonuses.line(view, cardIndices)
	if type(view) ~= "table" or type(view.hand) ~= "table" then return nil end
	local counts = {}
	local seen = {}
	for _, index in ipairs(cardIndices or {}) do
		local card = not seen[index] and view.hand[index]
		seen[index] = true
		if card and card.mark and Card.Marks[card.mark] then
			counts[card.mark] = (counts[card.mark] or 0) + 1
		end
	end
	local parts = {}
	for _, id in ipairs(Card.MarkOrder) do
		local n = counts[id]
		if n then parts[#parts + 1] = n > 1 and string.format("%s x%d", Card.Marks[id].name, n) or Card.Marks[id].name end
	end
	local boon = boonPart(view)
	if boon then parts[#parts + 1] = boon end
	if #parts == 0 then return nil end
	local text = table.concat(parts, ", ")
	while #text > PreviewBonuses.MAX_CHARS and #parts > 1 do -- drop the last part rather than cut a word
		table.remove(parts)
		text = table.concat(parts, ", ")
	end
	if #text > PreviewBonuses.MAX_CHARS then text = text:sub(1, PreviewBonuses.MAX_CHARS - 3) .. "..." end
	return text
end

-- The strip sits in the stage under the Score plate; nil when the plate leaves no 20 px of room before the stage ends.
-- `plate` = the live Score plate rect { y, h } (already pushed down by the preview strip).
function PreviewBonuses.rect(stage, text, plate)
	if not text or text == "" or not plate then return nil end
	local y = plate.y + plate.h + 2
	if y + PreviewBonuses.H > stage.y + stage.h then return nil end
	local w = math.min(stage.w, math.max(120, #text * PreviewBonuses.CHAR_W + 24))
	return { x = stage.x + math.floor((stage.w - w) / 2), y = y, w = w, h = PreviewBonuses.H }
end

return PreviewBonuses
