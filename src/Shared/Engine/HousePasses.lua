--[[
	HousePasses.lua
	Our Voucher equivalent -- permanent, once-per-run upgrades that show up
	as an occasional single "Voucher" slot in the shop (not every visit --
	see the server's VOUCHER_CHANCE), separate from the Patron offers and
	Pack offers. Unlike Recipes (consumable, used once and gone) these are
	persistent: buying one just sets `state.housePasses[id] = true` forever
	for the rest of the run, and whichever RunState helper cares
	(patronSlotLimit, patronPrice, packPrice, rerollCost, startRound's
	discard/hand math) checks for it directly.

	A few (Grand Opening) also have an immediate one-time `onBuy(state)`
	effect, applied once at purchase in addition to being recorded.
]]

local HousePasses = {}

HousePasses.Definitions = {
	{
		id = "extra_seating", name = "Extra Seating", icon = "🪑", price = 10,
		description = "Permanently +1 Patron table slot.",
	},
	{
		id = "regulars_discount", name = "Regulars' Discount", icon = "🏷️", price = 8,
		description = "Patron prices are 2 Tips cheaper (minimum 1).",
	},
	{
		id = "wholesale_pricing", name = "Wholesale Pricing", icon = "📦", price = 8,
		description = "Pack prices are 2 Tips cheaper (minimum 1).",
	},
	{
		id = "late_kitchen", name = "Late Kitchen", icon = "🍳", price = 10,
		description = "Permanently +1 Discard every round.",
	},
	{
		id = "double_shift", name = "Double Shift", icon = "⏰", price = 12,
		description = "Permanently +1 Hand every round.",
	},
	{
		id = "frequent_visitor", name = "Frequent Visitor Card", icon = "🎟️", price = 6,
		description = "Rerolling the shop costs 2 Tips less (minimum 1).",
	},
	{
		id = "grand_opening", name = "Grand Opening Special", icon = "🎊", price = 5,
		description = "Immediately earn 15 Tips.",
		onBuy = function(state)
			state.tips = state.tips + 15
		end,
	},
}

function HousePasses.getById(id)
	for _, pass in ipairs(HousePasses.Definitions) do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

return HousePasses
