-- Tavern Map hover and tap cards (Client/MapHover): the words and where the card sits.
--   MapTooltips.DECOR[key]      -> { title, line } for each doodle on the road
--   MapTooltips.NODE_LINE, FOG_NODE, FOG_DECOR, SPOT_NEW, SPOT_DONE   the fixed lines
--   MapTooltips.allLines()      -> every body line a card can show (with the "Cleared. " prefix where it applies)
--   MapTooltips.place(targetX, targetTop, targetH, canvasW, canvasH) -> { x, y, w, h } top-left of the card, always inside the canvas
-- Every line is one kind sentence of LINE_MAX characters or less, no dashes.
local M = {}

M.LINE_MAX = 60
M.CARD_W, M.CARD_H, M.GAP, M.EDGE = 250, 112, 8, 4
M.BODY_SIZE, M.BODY_W, M.BODY_H = 15, 226, 52 -- the body label inside the card: 3 lines of 15 px
M.CLEARED = "Cleared. "

M.NODE_LINE = "Tap for details and rewards."
M.FOG_NODE = "Something stirs in the fog."
M.FOG_DECOR = "Something is hidden in the fog."
M.SPOT_NEW = "Tap to open it for a reward."
M.SPOT_DONE = "You already found this."

M.DECOR = {
	signpost = { "Old Signpost", "Arrows point the way to the tavern." },
	pine_tree = { "Tall Pine", "A quiet spot to rest. Nothing is hidden here." },
	mushroom_ring = { "Mushroom Ring", "A fairy ring. Tavern folk say it brings luck." },
	windmill = { "Windmill", "Its sails turn all day for the tavern's flour." },
	lantern_post = { "Lantern Post", "Lit every evening for travellers." },
	cottage = { "Little Cottage", "A cosy stop with a warm window." },
	bridge = { "Stone Bridge", "Cross it to keep following the road." },
}
M.DECOR_FALLBACK = "A landmark on the road."

function M.allLines()
	local out = { M.NODE_LINE, M.FOG_NODE, M.FOG_DECOR, M.SPOT_NEW, M.SPOT_DONE, M.DECOR_FALLBACK }
	for _, info in pairs(M.DECOR) do out[#out + 1] = info[2] end
	out[#out + 1] = M.CLEARED .. M.SPOT_DONE
	return out
end

-- Above the target when there is room, else below it; always clamped inside the canvas with EDGE px to spare.
function M.place(targetX, targetTop, targetH, canvasW, canvasH)
	local x = math.max(M.EDGE, math.min(targetX - M.CARD_W / 2, canvasW - M.CARD_W - M.EDGE))
	local y = targetTop - M.CARD_H - M.GAP
	if y < M.EDGE then y = targetTop + targetH + M.GAP end
	y = math.max(M.EDGE, math.min(y, canvasH - M.CARD_H - M.EDGE))
	return { x = x, y = y, w = M.CARD_W, h = M.CARD_H }
end

return M
