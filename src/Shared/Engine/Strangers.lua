--[[
	Shared/Engine/Strangers.lua
	The Wandering Stranger: a rare second vendor in the Counter who sells exactly one Dealer's Bargain, a strong
	boost with a mild curse listed plainly on its card. Declining is always free.

	Appearance: 1 shop in 6 on normal runs, never Nights 1 and 2, never on ranked boards (Daily, Weekly, Seed) or in
	the tutorial. It is decided only by the run's stranger seed and the Night, so it is repeatable in tests.

	Effects are plain numeric fields summed by Strangers.field(state, field) and read by RunState:
		scorePct        percent added to the Mult of every scored hand
		handSizeDelta   cards in hand each round
		handsDelta      hands each round
		discardsDelta   discards each round
		tipsDelta       Tips on every round win (RunState keeps its 1 Tip floor)
	Blessings last the rest of the run. A curse lasts `nights` Nights, starting the Night after the deal. Every
	field is floored by RunState (hand size 1, hands 1, discards 0, reward 1) so a run can never become unwinnable.
]]

local Strangers = {}

Strangers.CHANCE_DENOMINATOR = 6
Strangers.FIRST_NIGHT = 3

Strangers.Bargains = {
	{
		id = "hot_pan", name = "The Hot Pan", icon = "\u{1F373}", price = 5, promptId = "stranger_hot_pan",
		blessingText = "+25 percent Mult on every hand", curseText = "One fewer Discard next Night",
		blessing = { field = "scorePct", value = 25 }, curse = { field = "discardsDelta", value = -1, nights = 1 },
	},
	{
		id = "long_table", name = "The Long Table", icon = "\u{1FA91}", price = 4, promptId = "stranger_long_table",
		blessingText = "One more card in hand every round", curseText = "Tips from round wins are 1 lower for 2 Nights",
		blessing = { field = "handSizeDelta", value = 1 }, curse = { field = "tipsDelta", value = -1, nights = 2 },
	},
	{
		id = "extra_hand", name = "The Extra Hand", icon = "\u{1F590}", price = 6, promptId = "stranger_extra_hand",
		blessingText = "One more Hand every round", curseText = "One fewer card in hand next Night",
		blessing = { field = "handsDelta", value = 1 }, curse = { field = "handSizeDelta", value = -1, nights = 1 },
	},
	{
		id = "sweet_deal", name = "The Sweet Deal", icon = "\u{1F36F}", price = 3, promptId = "stranger_sweet_deal",
		blessingText = "+15 percent Mult on every hand", curseText = "One fewer Hand next Night",
		blessing = { field = "scorePct", value = 15 }, curse = { field = "handsDelta", value = -1, nights = 1 },
	},
	{
		id = "fat_purse", name = "The Fat Purse", icon = "\u{1F45B}", price = 4, promptId = "stranger_fat_purse",
		blessingText = "Round wins pay 2 more Tips", curseText = "-10 percent Mult next Night",
		blessing = { field = "tipsDelta", value = 2 }, curse = { field = "scorePct", value = -10, nights = 1 },
	},
	{
		id = "night_owl", name = "The Night Owl", icon = "\u{1F989}", price = 5, promptId = "stranger_night_owl",
		blessingText = "Two more Discards every round", curseText = "One fewer card in hand for 2 Nights",
		blessing = { field = "discardsDelta", value = 2 }, curse = { field = "handSizeDelta", value = -1, nights = 2 },
	},
}

function Strangers.getById(id)
	for _, b in ipairs(Strangers.Bargains) do
		if b.id == id then return b end
	end
	return nil
end

local function hash(text)
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

-- Is the Stranger in the shop this visit? ctx = { ranked, tutorial }.
function Strangers.appears(seed, night, ctx)
	ctx = ctx or {}
	if ctx.ranked or ctx.tutorial or seed == nil then return false end
	if (night or 0) < Strangers.FIRST_NIGHT then return false end
	return hash("stranger|" .. tostring(seed) .. "|" .. tostring(night)) % Strangers.CHANCE_DENOMINATOR == 0
end

-- The one bargain on offer that visit.
function Strangers.offerFor(seed, night)
	local h = hash("bargain|" .. tostring(seed) .. "|" .. tostring(night))
	return Strangers.Bargains[(h % #Strangers.Bargains) + 1]
end

-- Starts a visit: returns the bargain on offer, or nil. Marks nothing; accept/decline are separate.
function Strangers.rollVisit(state, ctx)
	if state.strangerSeed == nil then return nil end
	if not Strangers.appears(state.strangerSeed, state.night, ctx) then return nil end
	return Strangers.offerFor(state.strangerSeed, state.night)
end

-- Takes the deal. Returns ok, message. The offer must be the one rolled for this visit (the server checks).
function Strangers.accept(state, bargainId)
	local b = Strangers.getById(bargainId)
	if not b then return false, "Unknown bargain" end
	if state.tips < b.price then return false, "Not enough tips" end
	state.tips = state.tips - b.price
	state.bargains = state.bargains or {}
	table.insert(state.bargains, { id = b.id, night = state.night })
	return true, b.name .. ": " .. b.blessingText .. ". Curse: " .. b.curseText .. "."
end

-- Sum of one effect field for the current Night.
function Strangers.field(state, field)
	local total = 0
	for _, deal in ipairs(state.bargains or {}) do
		local b = Strangers.getById(deal.id)
		if b then
			if b.blessing.field == field then
				total = total + b.blessing.value
			end
			if b.curse.field == field and state.night > deal.night and state.night <= deal.night + b.curse.nights then
				total = total + b.curse.value
			end
		end
	end
	return total
end

-- What the client may show for the shop: the offer card text, or nil.
function Strangers.view(offer)
	if not offer then return nil end
	return {
		id = offer.id, name = offer.name, icon = offer.icon, price = offer.price, promptId = offer.promptId,
		blessing = offer.blessingText, curse = offer.curseText,
	}
end

return Strangers
