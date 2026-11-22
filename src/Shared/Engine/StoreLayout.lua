-- StoreLayout: the numbers of the Tavern Store panel (Client/StorePanel), so a test can check them at any screen size.
-- The panel is drawn 820 x 470 and shrunk by one UIScale to fit the screen; every control is a child of it.
local StoreLayout = {}

StoreLayout.PANEL_W, StoreLayout.PANEL_H = 820, 470
StoreLayout.FIT_W, StoreLayout.FIT_H = 860, 510 -- the screen the panel needs, margin included
StoreLayout.SCALE_MIN, StoreLayout.SCALE_MAX = 0.5, 1
StoreLayout.CARD_W, StoreLayout.CARD_H, StoreLayout.CARD_GAP = 180, 330, 14
StoreLayout.ROW_X, StoreLayout.ROW_Y, StoreLayout.ROW_PAD = 15, 78, 30 -- row left, top, and total side padding (15 each)
StoreLayout.BUTTON_H, StoreLayout.CLOSE_W, StoreLayout.CLOSE_BOTTOM = 44, 160, 12
StoreLayout.MAX_CARDS = 4

function StoreLayout.scale(screenW, screenH)
	local s = math.min(screenW / StoreLayout.FIT_W, screenH / StoreLayout.FIT_H)
	return math.max(StoreLayout.SCALE_MIN, math.min(StoreLayout.SCALE_MAX, s))
end

-- plate height in panel pixels that still measures 44 px on screen after the panel is shrunk by `scale`
function StoreLayout.touchH(scale)
	return math.max(StoreLayout.BUTTON_H, math.ceil(StoreLayout.BUTTON_H / math.max(0.01, scale or 1) - 0.0001))
end

-- width of a row of n cards
function StoreLayout.rowWidth(n)
	if n <= 0 then return 0 end
	return n * StoreLayout.CARD_W + (n - 1) * StoreLayout.CARD_GAP
end

-- rects inside the panel (panel pixels, before the UIScale): row, the Buy plate of a card (card relative), Close
function StoreLayout.rects(scale)
	local L = StoreLayout
	local bh = L.touchH(scale)
	return {
		row = { x = L.ROW_X, y = L.ROW_Y, w = L.PANEL_W - L.ROW_PAD, h = L.CARD_H },
		buy = { x = 18, y = L.CARD_H - 4 - bh, w = L.CARD_W - 36, h = bh },
		price = { x = 8, y = L.CARD_H - 76, w = L.CARD_W - 16, h = 20 },
		perks = { x = 10, y = 200, w = L.CARD_W - 20, h = 54 },
		close = { x = (L.PANEL_W - L.CLOSE_W) / 2, y = L.PANEL_H - L.CLOSE_BOTTOM - bh, w = L.CLOSE_W, h = bh },
	}
end

return StoreLayout
