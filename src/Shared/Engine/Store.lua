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
	  vip               Game Pass (GamePasses "vip"): a gold star beside your name on boards, +3 Tips banked each day
	                    (capped), and a second badge slot. Looks and a tiny daily gift only.
	  continue          the existing One More Round product (GamePasses.DeveloperProducts), listed for information.

	Idempotency: a purchase id is remembered in the profile (profile.receiptIds), and a one-time item never grants twice.
]]

local GamePasses = require(script.Parent.GamePasses)
local TavernRank = require(script.Parent.TavernRank)

local Store = {}

Store.MAX_RECEIPTS = 100
Store.VIP_DAILY_TIPS = 3

Store.Items = {
	{
		id = "starter_pack", kind = "product", productId = 0, oneTime = true, icon = "🎁", name = "Starter Pack",
		description = "A card back, a Card Set and a title to start your collection.",
		contents = { cardBacks = { "gilded_ledger" }, sets = { "winter_evening" }, titles = { "founding_guest" } },
		perks = { "Gilded Ledger card back", "Winter Evening Card Set", "Title: Founding Guest" },
	},
	{
		id = "card_set_bundle", kind = "product", productId = 0, oneTime = true, icon = "🎴", name = "Card Set Bundle",
		description = "Two dressed-up tavern tables with their card backs.",
		contents = { sets = { "festival_night", "closing_time" } },
		perks = { "Festival Night Card Set", "Closing Time Card Set" },
	},
	{
		id = "vip", kind = "pass", passId = "vip", icon = "⭐", name = "VIP",
		description = "A little sparkle for regulars. Looks and a tiny daily gift, no power.",
		perks = { "Gold star beside your name", "+3 Tips every day", "A second badge slot" },
	},
	{
		id = "continue", kind = "product", productId = "continue", listOnly = true, icon = "🔁", name = "One More Round",
		description = "Replay a lost round once. Offered when a run ends.",
		perks = { "One free every day" },
	},
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
end

-- Grants a one-time product. Returns true when something was granted, false when it was already owned (the buyer
-- keeps what they have; nothing is granted twice).
function Store.grant(profile, itemId)
	local item = Store.getById(itemId)
	if not item or item.kind ~= "product" or not item.contents then
		return false
	end
	profile.storePurchases = profile.storePurchases or {}
	if item.oneTime and profile.storePurchases[item.id] then
		return false
	end
	giveContents(profile, item.contents)
	profile.storePurchases[item.id] = true
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

-- VIP daily gift: +VIP_DAILY_TIPS banked Tips once per UTC day (capped with the other banked Tips). Returns Tips given.
function Store.claimVipDaily(profile, day)
	if type(day) ~= "number" or profile.vipBonusDay == day then
		return 0
	end
	profile.vipBonusDay = day
	local before = profile.pendingStartTips or 0
	profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, before + Store.VIP_DAILY_TIPS)
	return profile.pendingStartTips - before
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
function Store.view(profile, ownedPasses, inStudio)
	local rows = {}
	for _, item in ipairs(Store.Items) do
		local owned = Store.owned(profile, item, ownedPasses)
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
