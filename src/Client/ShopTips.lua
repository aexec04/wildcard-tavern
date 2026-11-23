--[[
	Client/ShopTips.lua
	Where a Counter PACK tooltip opens. Each pack card hands Tooltip.attach a placer from packPlacer(). Tooltip calls it on
	every frame the tip is shown; it reads the LIVE rects (pack slots, offer slots and their name plates, the Counter's
	controls) and asks the pure TooltipSpec.placeBeside for a spot beside the pack row. Nothing is looked up by instance
	name: the rows and controls are handed in, so a renamed row can never silently fall back to "above the pack".

	packPlacer(src) -> function(pos, size, tip, screen) -> x, y, note
	  src.packRow()   the pack row (a Frame, or nil)
	  src.offerRow()  the offer row (a Frame, or nil)
	  src.controls()  GuiObjects to stay clear of: Haggle, Reroll, Next Round, the tabs, the boss chip (ShopStage.keepOut)
	  pos, size       the hovered button's AbsolutePosition and AbsoluteSize
	  tip, screen     the tooltip's size and the screen size
	  note            a function returning the Studio-only warn text (side, tip, every rect that was used)

	No Roblox constructors are used here, only property reads, so the file also loads in the local test runner.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TooltipSpec = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TooltipSpec"))

local ShopTips = {}

-- Printed in the Studio warn on every pack hover; a console without this tag means Studio is not running this code.
ShopTips.VERSION = "v4"

local function rectOf(g)
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	return { X = p.X, Y = p.Y, W = s.X, H = s.Y }
end

local function shown(g)
	return g.Visible and g.AbsoluteSize.X > 0 and g.AbsoluteSize.Y > 0
end

-- Slot rects of a card row (cards, sold spots, empty seats) and, when asked, the name plate inside each card.
function ShopTips.slots(row, withPlates)
	local slots, plates = {}, {}
	if row and row.Parent then
		for _, c in ipairs(row:GetChildren()) do
			if c:IsA("GuiObject") and shown(c) then
				slots[#slots + 1] = rectOf(c)
				if withPlates then
					local plate = c:FindFirstChild("Banner", true)
					if plate and plate:IsA("GuiObject") and shown(plate) then plates[#plates + 1] = rectOf(plate) end
				end
			end
		end
	end
	return slots, plates
end

-- Rects of the given controls and of their GuiObject children (the Haggle and Reroll tags hang below their button).
function ShopTips.controlRects(list)
	local out = {}
	for _, g in ipairs(list or {}) do
		if g and g.Parent and g:IsA("GuiObject") and g.Visible then
			if shown(g) then out[#out + 1] = rectOf(g) end
			for _, c in ipairs(g:GetChildren()) do
				if c:IsA("GuiObject") and shown(c) then out[#out + 1] = rectOf(c) end
			end
		end
	end
	return out
end

local function fmt(r)
	return string.format("%d,%d %dx%d", math.floor(r.X), math.floor(r.Y), math.floor(r.W), math.floor(r.H))
end

local function fmtAll(list)
	local parts = {}
	for i, r in ipairs(list) do parts[i] = fmt(r) end
	return table.concat(parts, "; ")
end

-- An open pack's card tip: centred under the card's Keep or Seat pill (PILL_DROP px below the slot), never over the pill.
-- slot is the card slot's rect {X, Y, W, H}; tip and screen are {X, Y} sizes. Above the card when there is no room below.
ShopTips.PILL_DROP = 4 + 34 + 8
function ShopTips.belowPill(slot, tip, screen)
	local x = slot.X + slot.W / 2 - tip.X / 2
	x = math.max(4, math.min(x, screen.X - tip.X - 4))
	local y = slot.Y + slot.H + ShopTips.PILL_DROP
	if y + tip.Y > screen.Y - 4 then y = math.max(4, slot.Y - tip.Y - 8) end
	return x, y
end

function ShopTips.packPlacer(src)
	return function(pos, size, tip, screen)
		local packs = ShopTips.slots(src.packRow and src.packRow())
		local offers, plates = ShopTips.slots(src.offerRow and src.offerRow(), true)
		local controls = ShopTips.controlRects(src.controls and src.controls())
		local blockers = {}
		for _, list in ipairs({ offers, plates, controls }) do
			for _, r in ipairs(list) do blockers[#blockers + 1] = r end
		end

		-- the hovered pack's slot: the one holding the centre of the (possibly lifted) button
		local hit = { X = pos.X, Y = pos.Y, W = size.X, H = size.Y }
		local card = hit
		local cx, cy = hit.X + hit.W / 2, hit.Y + hit.H / 2
		for _, p in ipairs(packs) do
			if cx >= p.X and cx <= p.X + p.W and cy >= p.Y and cy <= p.Y + p.H then
				card = p
				break
			end
		end
		if #packs == 0 then packs = { hit } end

		local x, y, info = TooltipSpec.placeBeside(card, packs, blockers, { X = tip.X, Y = tip.Y }, { X = screen.X, Y = screen.Y })
		return x, y, function()
			return string.format("%s side=%s clear=%s slid=%s tip=%s packs=[%s] offers=[%s] plates=[%s] controls=[%s]",
				ShopTips.VERSION, info.side, tostring(info.area == 0), tostring(info.slid),
				fmt({ X = x, Y = y, W = tip.X, H = tip.Y }), fmtAll(packs), fmtAll(offers), fmtAll(plates), fmtAll(controls))
		end
	end
end

return ShopTips
