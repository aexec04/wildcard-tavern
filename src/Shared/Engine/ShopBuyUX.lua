--[[
	Engine/ShopBuyUX.lua
	The Counter's Buy plate and its "not enough Tips" answer, pure and tested. Client/ShopCards draws it.

	plateText(actionText, price, tips)   -> "Buy" when the player can pay, "Need N" (N = Tips still missing) when not
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
	if need > 0 then return string.format("Need %d", need) end
	return actionText or "Buy"
end

function M.shake(calm, fast)
	if calm or fast then return nil end
	return { offsets = { -6, 6, -4, 4, -2, 0 }, step = 0.05 }
end

return M
