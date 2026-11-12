--[[
	Shared/Engine/ScrollOfferLayout.lua
	The Wandering Stranger's offer as a tavern scroll (Client/ShopHaggle.lua): the painted scroll shop_offer_scroll_a (or _b for a bad offer) IS
	the card. Everything is mapped from the 1024x1536 picture through one scale, so text never touches the rods or the seal at any size.
	Measured on art-wip/shop_scene/shop_offer_scroll_{a,b}.png (debug overlays shop_offer_scroll_*_layout.png): the flat sheet between the
	rolls, a text-safe rect inside it, the seal and the two rolls. Pure Lua, tested in EngineTests ("ScrollOfferLayout").

	ScrollOfferLayout.PICTURES.a / .b       { w, h, sheet, safe, seal, topRoll, bottomRoll } in picture pixels
	ScrollOfferLayout.layout(key, maxW, maxH)   nil when the scroll would be too small to read, else
	    { key, scale, w, h, safe, medallion, title, body, blessing, curse, accept, decline } in card pixels (origin at the card's top left)
	ScrollOfferLayout.pick(offer)           "a" or "b": b for a bad offer (the curse outweighs the blessing)
	ScrollOfferLayout.MIN_SCALE             below this the card is too small for 15 px text: the old flat card shows
	ScrollOfferLayout.TEXT_TITLE, TEXT_BODY  22 and 16 px
]]

local ScrollOfferLayout = {}

ScrollOfferLayout.TEXT_TITLE, ScrollOfferLayout.TEXT_BODY, ScrollOfferLayout.TEXT_BUTTON = 22, 16, 16
ScrollOfferLayout.MIN_SCALE = 0.34

-- picture pixels (1024 x 1536). sheet = the flat paper between the rolls, safe = where text may go (inside the wavy edges, clear of the
-- seal), seal = the wax seal's box, topRoll / bottomRoll = the rolled ends with their rods.
ScrollOfferLayout.PICTURES = {
	a = { w = 1024, h = 1536, sheet = { x = 176, y = 300, w = 680, h = 860 }, safe = { x = 214, y = 336, w = 596, h = 760 },
		seal = { x = 446, y = 1136, w = 144, h = 150 }, topRoll = { x = 150, y = 150, w = 724, h = 150 }, bottomRoll = { x = 150, y = 1160, w = 724, h = 140 } },
	b = { w = 1024, h = 1536, sheet = { x = 142, y = 220, w = 740, h = 1040 }, safe = { x = 190, y = 260, w = 644, h = 940 },
		seal = { x = 436, y = 1206, w = 150, h = 150 }, topRoll = { x = 140, y = 100, w = 744, h = 120 }, bottomRoll = { x = 130, y = 1260, w = 764, h = 120 } },
}

-- the picture's own aspect (the opaque art, not the empty canvas): where the scroll sits in the 1024 x 1536 canvas
ScrollOfferLayout.ART = { a = { x = 42, y = 165, w = 940, h = 1136 }, b = { x = 28, y = 98, w = 966, h = 1282 } }

function ScrollOfferLayout.pick(offer)
	-- a bad offer is one whose curse is the longer line (the Stranger's Dealer's Bargains pair a blessing with a curse)
	if type(offer) == "table" and type(offer.curse) == "string" and type(offer.blessing) == "string" and #offer.curse > #offer.blessing + 8 then
		return "b"
	end
	return "a"
end

local function rect(x, y, w, h) return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = math.floor(w + 0.5), h = math.floor(h + 0.5) } end

function ScrollOfferLayout.layout(key, maxW, maxH)
	local P = ScrollOfferLayout.PICTURES[key]
	local art = ScrollOfferLayout.ART[key]
	if not P then return nil end
	-- only the opaque art is shown (the canvas margin is transparent), so the card is the art's box and every rect is relative to it
	local scale = math.min(maxW / art.w, maxH / art.h)
	if scale < ScrollOfferLayout.MIN_SCALE then return nil end
	local function m(r) return rect((r.x - art.x) * scale, (r.y - art.y) * scale, r.w * scale, r.h * scale) end
	local out = { key = key, scale = scale, w = math.floor(art.w * scale + 0.5), h = math.floor(art.h * scale + 0.5) }
	out.safe = m(P.safe)
	out.seal = m(P.seal)
	local S = out.safe
	local gap = math.max(6, math.floor(8 * scale / 0.4 + 0.5))
	-- the Stranger in a brass ringed medallion at the top of the sheet, centred
	local md = math.floor(math.min(S.w * 0.3, S.h * 0.2))
	out.medallion = { x = S.x + math.floor((S.w - md) / 2), y = S.y, w = md, h = md }
	local y = out.medallion.y + md + gap
	out.title = { x = S.x, y = y, w = S.w, h = ScrollOfferLayout.TEXT_TITLE * 2 + 8 }
	y = y + out.title.h + gap
	-- the buttons are the bottom band of the safe area, above the seal
	local bh = 36
	local btnY = S.y + S.h - bh
	local bw = math.floor((S.w - gap) / 2)
	out.accept = { x = S.x, y = btnY, w = bw, h = bh }
	out.decline = { x = S.x + S.w - bw, y = btnY, w = bw, h = bh }
	-- blessing then curse share the space between the title and the buttons
	local bodyH = btnY - gap - y
	out.body = { x = S.x, y = y, w = S.w, h = bodyH }
	-- two stacked lines, each as tall as its text needs (up to two wrapped lines), 12 px apart, centred in the space
	local lineH = math.min(math.floor((bodyH - 12) / 2), ScrollOfferLayout.TEXT_BODY * 2 + 10)
	local blockH = lineH * 2 + 12
	local top = y + math.max(0, math.floor((bodyH - blockH) / 2))
	out.blessing = { x = S.x, y = top, w = S.w, h = lineH }
	out.curse = { x = S.x, y = top + lineH + 12, w = S.w, h = lineH }
	return out
end

return ScrollOfferLayout
