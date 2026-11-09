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
		flavorText = "The carpenter added a bench. Everyone scooted over.",
	},
	{
		id = "regulars_discount", name = "Regulars' Discount", icon = "🏷️", price = 8,
		description = "Patron prices are 2 Tips cheaper (minimum 1).",
		flavorText = "Friendly faces get friendly prices.",
	},
	{
		id = "wholesale_pricing", name = "Wholesale Pricing", icon = "📦", price = 8,
		description = "Pack prices are 2 Tips cheaper (minimum 1).",
		flavorText = "Buying in bulk means more crates in the cellar.",
	},
	{
		id = "late_kitchen", name = "Late Kitchen", icon = "🍳", price = 5,
		description = "Permanently +1 Discard every round.",
		flavorText = "The cook keeps the stove warm a little longer.",
	},
	{
		id = "double_shift", name = "Double Shift", icon = "⏰", price = 12,
		description = "Permanently +1 Hand every round.",
		flavorText = "Two cooks in the kitchen means twice the plates.",
	},
	{
		id = "frequent_visitor", name = "Frequent Visitor Card", icon = "🎟️", price = 6,
		description = "Rerolling the shop costs 2 Tips less (minimum 1).",
		flavorText = "One more punch and the next shuffle is cheaper.",
	},
	{
		id = "grand_opening", name = "Grand Opening Special", icon = "🎊", price = 5,
		description = "Immediately earn 15 Tips.",
		flavorText = "Ribbons, balloons and a jar full of coins.",
		onBuy = function(state)
			state.tips = state.tips + 15
		end,
	},
	{
		id = "pantry_shelf", name = "Pantry Shelf", icon = "🗄️", price = 9,
		description = "Permanently +1 Recipe slot.",
		flavorText = "A deeper shelf means room for one more jar.",
	},
	{
		id = "tip_stand", name = "Tip Stand", icon = "🪙", price = 10,
		description = "Earn 1 extra Tip for every round you win.",
		flavorText = "A little dish by the door fills up fast.",
	},
	{
		id = "card_cart", name = "Card Cart", icon = "🛒", price = 12,
		description = "Permanently draw 1 more card each round.",
		flavorText = "Rolls a fresh stack to every table.",
	},
	{
		id = "savings_account", name = "Savings Account", icon = "🏦", price = 8,
		description = "Raises the round-win interest cap by 3 Tips.",
		flavorText = "The coin box has a bigger lid now.",
	},
	{
		id = "warm_welcome", name = "Warm Welcome", icon = "🎈", price = 12,
		description = "Boss Round targets are 10% lower.",
		flavorText = "Even the grumpiest guest cheers up at the door.",
	},
	{
		id = "boss_prep", name = "Boss Prep", icon = "📋", price = 8,
		description = "+1 Discard in every Boss Round.",
		flavorText = "A checklist taped inside the kitchen door.",
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
