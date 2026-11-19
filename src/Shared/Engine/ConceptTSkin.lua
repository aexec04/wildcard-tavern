--[[
	Engine/ConceptTSkin.lua
	Tested numbers for the Concept T look on the Shop, Collection and round clear screens: one serif title style
	(Garamond, cream, dark outline) and one price pill drawn on the painted plain pill plate (ct_pill_plain).
	Pure data and math, no Roblox calls, so it runs in the test runner. Client/ConceptTSkin applies it.
]]

local ConceptTSkin = {}

ConceptTSkin.TITLE_FONT = "Garamond" -- Enum.Font name, the serif the title plates use
ConceptTSkin.TITLE_COLOR = { 250, 238, 212 } -- cream
ConceptTSkin.TITLE_STROKE = { 36, 22, 12 } -- dark outline
ConceptTSkin.TITLE_STROKE_THICKNESS = 2
ConceptTSkin.GOLD_TEXT = { 255, 214, 130 }
ConceptTSkin.PRICE_OK = { 255, 244, 214 } -- cream on the dark pill: above 4.5:1
ConceptTSkin.PRICE_BAD = { 255, 150, 130 } -- soft red, still above 4.5:1 on the dark pill
ConceptTSkin.PILL_ART = "ct_pill_plain"
ConceptTSkin.MIN_TEXT = 15

function ConceptTSkin.priceColor(affordable)
	return affordable == false and ConceptTSkin.PRICE_BAD or ConceptTSkin.PRICE_OK
end

-- Title size: never under MIN_TEXT, grows with the viewport height up to `maxSize`.
function ConceptTSkin.titleSize(base, viewportHeight)
	local scale = math.max(1, math.min(1.5, (viewportHeight or 720) / 720))
	return math.max(ConceptTSkin.MIN_TEXT, math.floor((base or 22) * scale))
end

-- Price pill rect inside a tag of w x h: the coin sits at the left, the number takes the rest, never under 15 px text.
function ConceptTSkin.priceLayout(w, h)
	local pad = math.max(4, math.floor(h * 0.18))
	local coin = math.max(12, math.floor(h - 2 * pad))
	return {
		coin = { x = pad, y = math.floor((h - coin) / 2), w = coin, h = coin },
		text = { x = pad * 2 + coin, y = 0, w = math.max(0, w - pad * 3 - coin), h = h },
		textSize = math.max(ConceptTSkin.MIN_TEXT, math.min(22, math.floor(h * 0.62))),
	}
end

-- Dialogs, Settings, hint bubbles and toasts: parchment sheet with dark ink, painted green plate buttons with cream text.
ConceptTSkin.PLATE_ART = "ct_btn_blank" -- the text-free green wood plate
ConceptTSkin.PLATE_GREEN = { 52, 112, 58 } -- darkest sampled tone of the plate, the worst case for the label
ConceptTSkin.PLATE_TEXT = { 255, 244, 214 }
ConceptTSkin.PAPER = { 238, 222, 186 }
ConceptTSkin.INK = { 46, 32, 20 }
ConceptTSkin.MIN_TOUCH = 40 -- plate buttons are never shorter than this
ConceptTSkin.DIALOG_TITLE_SIZE = 24

-- Button size for a plate: never under MIN_TOUCH tall, text at least MIN_TEXT.
function ConceptTSkin.plateSize(w, h)
	return math.max(w, 96), math.max(h, ConceptTSkin.MIN_TOUCH)
end

-- Frame kinds that cannot take a plate: a danger button keeps its red fill so it still reads as destructive.
function ConceptTSkin.usesPlate(kind)
	return kind ~= "danger"
end

local function lum(c)
	local function f(v)
		v = v / 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
end

function ConceptTSkin.contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

return ConceptTSkin
