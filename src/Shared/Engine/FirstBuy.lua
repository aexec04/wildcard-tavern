--[[
	Shared/Engine/FirstBuy.lua
	The first Counter visit: one Patron offer the player can afford gets a gold outline, so the first buy is obvious.
	Pure Lua, display only: it never changes a purchase.

	FirstBuy.enabled(state)              -> bool   Night 1, at most one Patron owned, a seat free, the player has not bought yet
	FirstBuy.pick(offers, tips)          -> nil | index   the cheapest affordable Patron offer (first one on a tie)
]]

local M = {}

M.MAX_NIGHT = 1
M.MAX_OWNED = 1 -- the guided starter counts as one; after a second Patron the first buy is behind the player

function M.enabled(state)
	if type(state) ~= "table" or state.isTutorial == true then return false end
	if (tonumber(state.night) or 1) > M.MAX_NIGHT then return false end
	local owned = type(state.ownedPatrons) == "table" and #state.ownedPatrons or 0
	if owned > M.MAX_OWNED then return false end
	local limit = tonumber(state.patronLimit) or tonumber(state.maxPatrons)
	if limit and owned >= limit then return false end
	return true
end

function M.pick(offers, tips)
	if type(offers) ~= "table" then return nil end
	tips = tonumber(tips) or 0
	local best, bestPrice
	for i, offer in ipairs(offers) do
		local price = type(offer) == "table" and tonumber(offer.price) or nil
		if price and price <= tips and (bestPrice == nil or price < bestPrice) then
			best, bestPrice = i, price
		end
	end
	return best
end

return M
