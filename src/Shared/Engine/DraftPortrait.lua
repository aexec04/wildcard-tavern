--[[
	Engine/DraftPortrait.lua
	What the Patron pick ring (Client/ChoicePanel) draws for a Patron, as plain data so a test can check the same numbers.
	The plain Patron portraits are full tavern scenes, far too big for a 126 x 84 ring, so the ring shows the portrait window of
	the Concept T cut card instead (Engine/PatronCardCrop, scaled into the stored texture by PatronParchment.storedRect): no frame,
	no baked name ribbon, only the character. Without a cut card or crop it falls back to the plain portrait, fitted whole inside
	the clipping frame. No art at all returns nil and the ring keeps its emoji.
]]
local PatronParchment = require(script.Parent.PatronParchment)
local PatronArt = require(script.Parent.PatronArt)
local CardArt = require(script.Parent.ConceptTPatronArt)

local M = {}
M.RING_W, M.RING_H = 126, 84 -- the ring window in Client/ChoicePanel

local function usable(id)
	return type(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

-- { kind = "card", image, rect = { x, y, w, h }, scaleType = "Crop" } | { kind = "plain", image, scaleType = "Fit" } | nil
function M.spec(patronId)
	local id = tostring(patronId or "")
	local card = CardArt["ctp_" .. id]
	local rect = PatronParchment.storedRect(id)
	if usable(card) and rect then
		return { kind = "card", image = card, rect = rect, scaleType = "Crop" }
	end
	local plain = PatronArt[id]
	if usable(plain) then
		return { kind = "plain", image = plain, scaleType = "Fit" }
	end
	return nil
end

-- the face only: the top band of a window with the ring's 3 : 2 shape, so a name baked low in the art never shows in the ring
function M.faceRect(rect)
	if type(rect) ~= "table" then return rect end
	return { x = rect.x, y = rect.y, w = rect.w, h = math.min(rect.h, rect.w * M.RING_H / M.RING_W) }
end

-- the picture always fills its clipping frame exactly, so it can never spill past the frame or over the name plate
function M.rect(frameW, frameH)
	return { x = 0, y = 0, w = math.max(0, frameW), h = math.max(0, frameH) }
end

-- Studio only warning text when a drawn portrait is not inside its frame (nil when it fits)
function M.overflow(portraitX, portraitY, portraitW, portraitH, frameX, frameY, frameW, frameH)
	local tol = 1
	if portraitX < frameX - tol or portraitY < frameY - tol
		or portraitX + portraitW > frameX + frameW + tol or portraitY + portraitH > frameY + frameH + tol then
		return ("portrait %.0fx%.0f at %.0f,%.0f is outside frame %.0fx%.0f at %.0f,%.0f"):format(
			portraitW, portraitH, portraitX, portraitY, frameW, frameH, frameX, frameY)
	end
	return nil
end

return M
