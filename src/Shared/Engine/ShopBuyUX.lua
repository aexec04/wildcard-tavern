--[[
	Engine/ShopBuyUX.lua
	The Counter's Buy plate and its "not enough Tips" answer, pure and tested. Client/ShopCards draws it.

	plateText(actionText, price, tips)   -> "Buy" when the player can pay, "Need N more" (N = Tips still missing) when not
	shortBy(price, tips)                 -> Tips still missing, never negative
	shake(calm, fast)                    -> { offsets = {px...}, step = seconds } a small sideways shake, nil in Calm mode and on Fast
]]

local M = {}

local function num(n) return math.floor(tonumber(n) or 0) end

function M.shortBy(price, tips)
	return math.max(0, num(price) - num(tips))
end

function M.plateText(actionText, price, tips)
	if price == nil or tips == nil then return actionText or "Buy" end
	local need = M.shortBy(price, tips)
	if need > 0 then return string.format("Need %d more", need) end
	return actionText or "Buy"
end

-- The Reroll button: "Reroll 3" when affordable, "Reroll 3, 2 short" when the player is 2 Tips short.
function M.rerollText(cost, tips)
	local c = num(cost)
	if tips == nil then return string.format("Reroll %d", c) end
	local need = M.shortBy(c, tips)
	if need > 0 then return string.format("Reroll %d, %d short", c, need) end
	return string.format("Reroll %d", c)
end

-- The Reroll button's whole look: grey with a reason when the Tips are short, wood brown otherwise.
-- Only Tips are spent here, nothing random about the price.
function M.rerollView(cost, tips)
	local c = num(cost)
	local need = tips == nil and 0 or M.shortBy(c, tips)
	if need > 0 then
		return { affordable = false, text = M.rerollText(c, tips), reason = string.format("Need %d more Tips to reroll.", need),
			fill = { 92, 86, 80 }, textColor = { 185, 178, 168 } }
	end
	return { affordable = true, text = M.rerollText(c, tips), reason = nil, fill = { 118, 82, 48 }, textColor = { 250, 235, 200 } }
end

function M.shake(calm, fast)
	if calm or fast then return nil end
	return { offsets = { -6, 6, -4, 4, -2, 0 }, step = 0.05 }
end

return M
