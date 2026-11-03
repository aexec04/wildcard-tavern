--[[
	Shared/Engine/DeveloperProducts.lua
	Catalog of consumable Robux Developer Products. Unlike a Game Pass
	(GamePasses.lua, owned forever), a Developer Product can be bought again
	and again, and the server grants it in MarketplaceService.ProcessReceipt.

	Every `productId` is a PLACEHOLDER (0) until the real product exists:
	Creator Dashboard -> your experience -> Monetization -> Developer
	Products -> Create. Set the name, icon and price there, then paste the
	numeric id it gives you into `productId` below.

	While productId is 0, the product can't be bought in the live game.
	Studio grants it free on request so it can be playtested (same idea as
	GamePasses' Studio bypass, see Server/init.server.lua).
]]

local DeveloperProducts = {}

DeveloperProducts.Definitions = {
	{
		-- One per run (RunState.canContinue). Using it marks the run
		-- revived, which moves it to the "Revived" Daily/Weekly boards and
		-- stops it counting toward high score records.
		id = "continue",
		productId = 0,
		name = "Continue",
		description = "Keep your run going on the round you lost, with fresh Hands.",
	},
}

function DeveloperProducts.getById(id)
	for _, product in ipairs(DeveloperProducts.Definitions) do
		if product.id == id then
			return product
		end
	end
	return nil
end

function DeveloperProducts.getByProductId(productId)
	if type(productId) ~= "number" or productId <= 0 then
		return nil
	end
	for _, product in ipairs(DeveloperProducts.Definitions) do
		if product.productId == productId then
			return product
		end
	end
	return nil
end

function DeveloperProducts.isConfigured(product)
	return product ~= nil and type(product.productId) == "number" and product.productId > 0
end

return DeveloperProducts
