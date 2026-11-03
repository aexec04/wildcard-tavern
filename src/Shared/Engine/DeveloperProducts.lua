--[[
	Shared/Engine/DeveloperProducts.lua
	Lookups over the consumable Robux Developer Products. The catalog itself
	lives next to the Game Pass config, as GamePasses.DeveloperProducts (see
	that file for how to create a product and where its id goes).
]]

local GamePasses = require(script.Parent.GamePasses)

local DeveloperProducts = {}

DeveloperProducts.Definitions = GamePasses.DeveloperProducts

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
