--[[
	Store.lua
	The Tavern Store catalog and its grant rules. Fair monetization ONLY: every item is a cosmetic or a small
	convenience, nothing changes whether a run is won (no Patron slots, no targets, no extra Hands, no scoring).
	Pure Lua, no Roblox APIs, so grants and idempotency are unit tested; Server/init.server.lua owns the
	MarketplaceService calls.

	Real ids are PLACEHOLDERS (0) until the user creates the products in Creator Hub (see claude/ROADMAP.md for the
	list). A placeholder cannot be bought in the live game ("Coming soon"); Studio grants it free so it can be tested.

	Items:
	  starter_pack      Developer Product, ONE TIME: Gilded Ledger card back, Winter Evening Card Set, the Founding
	                    Guest title. Offered once, after the second run.
	  card_set_bundle   Developer Product, one time: the Festival Night and Closing Time Card Sets (their backs come with them).
	  vip               Game Pass (GamePasses "vip"): a gold star beside your name on boards and a second
	                    badge slot. Looks only (it used to bank Tips each day; Tips are run power, so that was removed).
	  continue          the existing One More Round product (GamePasses.DeveloperProducts), listed for information.

	Idempotency: a purchase id is remembered in the profile (profile.receiptIds), and a one-time item never grants twice.
]]

local GamePasses = require(script.Parent.GamePasses)
local TavernRank = require(script.Parent.TavernRank)

local Store = {}

Store.MAX_RECEIPTS = 100

Store.Items = {
	{
		id = "starter_pack", category = "cosmetic", kind = "product", productId = 0, oneTime = true, icon = "🎁", name = "Starter Pack",
		description = "A card back, a Card Set and a title to start your collection.",
		contents = { cardBacks = { "gilded_ledger" }, sets = { "winter_evening" }, titles = { "founding_guest" } },
		perks = { "Gilded Ledger card back", "Winter Evening Card Set", "Title: Founding Guest" },
	},
	{
		id = "card_set_bundle", category = "cosmetic", kind = "product", productId = 0, oneTime = true, icon = "🎴", name = "Card Set Bundle",
		description = "Two dressed-up tavern tables with their card backs.",
		contents = { sets = { "festival_night", "closing_time" } },
		perks = { "Festival Night Card Set", "Closing Time Card Set" },
	},
	{
		id = "vip", category = "cosmetic", kind = "pass", passId = "vip", icon = "⭐", name = "VIP",
		description = "A little sparkle for regulars. Looks and a second badge slot, no power.",
		perks = { "Gold star beside your name", "A second badge slot" },
	},
	{
		id = "continue", category = "convenience", kind = "product", productId = "continue", listOnly = true, icon = "🔁", name = "One More Round",
		description = "Replay a lost round once. Offered when a run ends.",
		perks = { "One free every day" },
	},
}

-- FLAIR PIECES (Engine/Flair.lua `store` options) and the SEASON PREMIUM TRACK (Engine/SeasonTrack.lua): items with a
-- `section` are shown in their own screens (Flair panel, Season panel), not in the main Store row. All cosmetic, one time,
-- placeholder product ids (0) until created in Creator Hub (see claude/LAUNCH.md and claude/ROADMAP.md).
local function flairItem(id, flairId, name, icon, what)
	return {
		id = id, category = "cosmetic", kind = "product", productId = 0, oneTime = true, icon = icon, name = name, section = "flair",
		description = "Flair for your table: " .. what .. ". Looks only, never changes your score.",
		contents = { flair = { flairId } }, perks = { name },
	}
end
Store.Items[#Store.Items + 1] = flairItem("flair_rainbow_numbers", "rainbow_numbers", "Rainbow Numbers", "🌈", "rainbow score numbers")
Store.Items[#Store.Items + 1] = flairItem("flair_ribbon_trail", "ribbon_trail", "Ribbon Trail", "🎀", "ribbons follow your played cards")
Store.Items[#Store.Items + 1] = flairItem("flair_crown_finisher", "crown_finisher", "Crown Flash", "👑", "a crown flash on big hands")
Store.Items[#Store.Items + 1] = flairItem("flair_star_aura", "star_aura", "Star Aura", "🌟", "a star aura around your name")
Store.Items[#Store.Items + 1] = {
	id = "flair_bundle", category = "cosmetic", kind = "product", productId = 0, oneTime = true, icon = "🎁", name = "Flair Bundle", section = "flair",
	description = "All four Store Flair pieces at a lower price. Looks only, never changes your score.",
	contents = { flair = { "rainbow_numbers", "ribbon_trail", "crown_finisher", "star_aura" } },
	perks = { "Rainbow Numbers", "Ribbon Trail", "Crown Flash", "Star Aura" },
}
-- one premium pass per season (`seasonPremium` = the season id); bought once per season
Store.Items[#Store.Items + 1] = {
	id = "premium_harvest_moon", category = "cosmetic", kind = "product", productId = 0, oneTime = true, icon = "🌕", name = "Harvest Moon Premium", section = "season",
	seasonPremium = "harvest_moon", description = "A second reward row on every tier of the Harvest Moon season. Looks only.",
	perks = { "A Season Card Set", "Flair pieces", "A title and a unique tier 30 card back", "A Season Stamp on every other tier" },
}
Store.Items[#Store.Items + 1] = {
	id = "premium_winter_welcome", category = "cosmetic", kind = "product", productId = 0, oneTime = true, icon = "🧣", name = "Winter Welcome Premium", section = "season",
	seasonPremium = "winter_welcome", description = "A second reward row on every tier of the Winter Welcome season. Looks only.",
	perks = { "A Season Card Set", "Flair pieces", "A title and a unique tier 30 card back", "A Season Stamp on every other tier" },
}

function Store.getById(id)
	for _, item in ipairs(Store.Items) do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- The Developer Product item for a Roblox product id (placeholders with id 0 never match).
function Store.getByProductId(productId)
	if type(productId) ~= "number" or productId <= 0 then
		return nil
	end
	for _, item in ipairs(Store.Items) do
		if item.kind == "product" and item.productId == productId then
			return item
		end
	end
	return nil
end

-- The Roblox id behind an item (a product id, or the pass's gamePassId), 0 while it is a placeholder.
function Store.robloxId(item)
	if item.kind == "product" then
		if item.productId == "continue" then
			local dev = GamePasses.DeveloperProducts[1]
			return dev and dev.productId or 0
		end
		return item.productId or 0
	elseif item.kind == "pass" then
		local pass = GamePasses.getById(item.passId)
		return pass and pass.gamePassId or 0
	end
	return 0
end

function Store.isConfigured(item)
	return Store.robloxId(item) > 0
end

-- Is this item owned? Passes come from the server's ownership check (`ownedPasses[passId]`), products from the profile.
function Store.owned(profile, item, ownedPasses)
	if item.kind == "pass" then
		return ownedPasses ~= nil and ownedPasses[item.passId] == true
	end
	return item.oneTime == true and profile.storePurchases ~= nil and profile.storePurchases[item.id] == true
end

local function giveContents(profile, contents)
	for _, id in ipairs(contents.cardBacks or {}) do
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[id] = true
	end
	for _, id in ipairs(contents.sets or {}) do
		profile.ownedSetIds = profile.ownedSetIds or {}
		profile.ownedSetIds[id] = true
	end
	for _, id in ipairs(contents.titles or {}) do
		profile.rewardTitleIds = profile.rewardTitleIds or {}
		profile.rewardTitleIds[id] = true
	end
	for _, id in ipairs(contents.flair or {}) do
		require(script.Parent.Flair).grantOwned(profile, id)
	end
end

-- Grants a one-time product. Returns true when something was granted, false when it was already owned (the buyer
-- keeps what they have; nothing is granted twice).
function Store.grant(profile, itemId, day)
	local item = Store.getById(itemId)
	if not item or item.kind ~= "product" or not (item.contents or item.seasonPremium) then
		return false
	end
	profile.storePurchases = profile.storePurchases or {}
	if item.oneTime and profile.storePurchases[item.id] then
		return false
	end
	if item.contents then
		giveContents(profile, item.contents)
	end
	if item.seasonPremium then
		-- the premium pass of a season: marks it owned and claims every premium tier already reached (mid season buyers)
		require(script.Parent.SeasonTrack).grantPremium(profile, item.seasonPremium, day or math.floor(os.time() / 86400))
	end
	profile.storePurchases[item.id] = true
	return true
end

-- A season's premium pass can only be bought while that season runs (the server checks before prompting).
function Store.canBuy(item, day)
	if item and item.seasonPremium then
		local active = require(script.Parent.SeasonTrack).active(day or math.floor(os.time() / 86400))
		return active ~= nil and active.id == item.seasonPremium
	end
	return true
end

-- Handles a Developer Product receipt for a store item. Idempotent by purchase id. Returns:
--   "granted"  the purchase is done (new grant, or it was already given); acknowledge it
--   "unknown"  not a store product (let another handler look at it)
function Store.processReceipt(profile, productId, purchaseId)
	local item = Store.getByProductId(productId)
	if not item then
		return "unknown"
	end
	profile.receiptIds = profile.receiptIds or {}
	local key = tostring(purchaseId)
	for _, seen in ipairs(profile.receiptIds) do
		if seen == key then
			return "granted"
		end
	end
	Store.grant(profile, item.id)
	table.insert(profile.receiptIds, key)
	while #profile.receiptIds > Store.MAX_RECEIPTS do
		table.remove(profile.receiptIds, 1)
	end
	return "granted"
end

-- FAIR MONETIZATION AUDIT. Every Robux item is a "cosmetic" (looks only) or a "convenience" (saves time or a slot, never
-- changes whether a run is won). Tips, XP, Patron slots, Targets and scoring are never for sale. `Store.audit()` returns a list
-- of problems (empty when clean); a test runs it, so a pay to win item can not be added quietly.
Store.CATEGORIES = { cosmetic = true, convenience = true }
Store.PASS_CATEGORY = { fast_forward = "convenience", vip = "cosmetic", set_golden_gala = "cosmetic" } -- by GamePasses id
Store.DEV_PRODUCT_CATEGORY = { continue = "convenience" } -- by GamePasses.DeveloperProducts id (a once a day free retry is also given)
local ALLOWED_CONTENTS = { cardBacks = true, sets = true, titles = true, flair = true }

function Store.audit()
	local problems = {}
	for _, item in ipairs(Store.Items) do
		if not Store.CATEGORIES[item.category] then
			problems[#problems + 1] = item.id .. ": no category (cosmetic or convenience)"
		end
		for key in pairs(item.contents or {}) do
			if not ALLOWED_CONTENTS[key] then
				problems[#problems + 1] = item.id .. ": contents '" .. tostring(key) .. "' is not a cosmetic"
			end
		end
		local words = (item.description or "") .. " " .. table.concat(item.perks or {}, " ")
		if item.category == "cosmetic" and (words:find("Tips") or words:find("Patron slot") or words:find("Target") or words:find("Hands")) then
			problems[#problems + 1] = item.id .. ": a cosmetic item mentions Tips, slots, Targets or Hands"
		end
	end
	for _, pass in ipairs(GamePasses.Definitions) do
		if not Store.CATEGORIES[Store.PASS_CATEGORY[pass.id]] then problems[#problems + 1] = "pass " .. pass.id .. ": no category" end
	end
	for _, product in ipairs(GamePasses.DeveloperProducts) do
		if not Store.CATEGORIES[Store.DEV_PRODUCT_CATEGORY[product.id]] then problems[#problems + 1] = "product " .. product.id .. ": no category" end
	end
	return problems
end

-- Equips a badge into the second slot (VIP only). nil clears it. Returns ok.
function Store.equipSecondBadge(profile, badgeId, isVip, badgeOwned)
	if badgeId == nil then
		profile.equippedBadgeId2 = nil
		return true
	end
	if not isVip or type(badgeId) ~= "string" or not badgeOwned then
		return false
	end
	profile.equippedBadgeId2 = badgeId
	return true
end

-- What the Store panel draws. `inStudio`: a placeholder item can be taken free there.
-- Items of a section ("flair", "season") as rows, or the main Store items when `section` is nil.
-- A Flair item also counts as owned when every piece it gives is already yours (earned or bought another way).
function Store.view(profile, ownedPasses, inStudio, section)
	local rows = {}
	for _, item in ipairs(Store.Items) do
	if item.section == section then
		local owned = Store.owned(profile, item, ownedPasses)
		if not owned and item.contents and item.contents.flair then
			local Flair = require(script.Parent.Flair)
			owned = true
			for _, id in ipairs(item.contents.flair) do
				if not (profile.flairOwned and profile.flairOwned[id]) and not Flair.isOwned(profile, id) then owned = false end
			end
		end
		local configured = Store.isConfigured(item)
		rows[#rows + 1] = {
			id = item.id, kind = item.kind, icon = item.icon, name = item.name, description = item.description, perks = item.perks,
			robloxId = Store.robloxId(item), owned = owned, listOnly = item.listOnly == true,
			-- can be bought now: configured, or free in Studio
			available = not owned and not item.listOnly and (configured or inStudio == true),
			studioFree = not configured and inStudio == true,
			comingSoon = not configured and not inStudio and not item.listOnly,
		}
	end
	end
	return { items = rows, vip = ownedPasses ~= nil and ownedPasses.vip == true }
end

-- Cleans saved values.
function Store.cleanSaved(rawPurchases, rawReceipts, rawVipDay)
	local purchases = {}
	if type(rawPurchases) == "table" then
		for id, flag in pairs(rawPurchases) do
			local item = type(id) == "string" and Store.getById(id)
			if flag == true and item and item.oneTime then purchases[id] = true end
		end
	end
	local receipts = {}
	if type(rawReceipts) == "table" then
		for _, id in ipairs(rawReceipts) do
			if type(id) == "string" and #id <= 64 and #receipts < Store.MAX_RECEIPTS then receipts[#receipts + 1] = id end
		end
	end
	local day = nil
	if type(rawVipDay) == "number" and rawVipDay == rawVipDay and rawVipDay >= 0 then
		day = math.floor(rawVipDay)
	end
	return purchases, receipts, day
end

return Store
