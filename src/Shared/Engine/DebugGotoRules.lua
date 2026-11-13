--[[
	Shared/Engine/DebugGotoRules.lua
	Pure parser for the Studio-only DebugGoto jump hook (Client/DebugGoto.lua). parse(value) returns
	{ kind = "menu" | "tome" | "news" | "round1" | "shop" | "spectate", page?, sub? } or nil, reason.
	Unknown values return nil so the client warns and does nothing.
]]

local DebugGotoRules = {}

-- tome page name -> OverlayManager opener id (Engine/PanelGroups page ids)
DebugGotoRules.TOME_PAGES = {
	collection = "collection", cardsets = "cosmeticSets", badges = "badges",
	legend = "legend", flair = "flair", stats = "stats",
}

DebugGotoRules.SEED_CODE = "DEBUG2" -- fixed run seed for round1 (6 chars, A-Z without I and O, digits 2-9)

-- Table screens reached by round1 then re-rendering a changed copy of the real state (no server hook needed).
DebugGotoRules.SYNTH = { shop = true, roundwin = true, gameover = true, boss1 = true, roundselect = true,
	haggle = true, road = true, runover = true, packroom = true, rarity = true }
-- values with a variant: haggle:good|bad, runover:win, rarity:<page>
DebugGotoRules.VARIANTS = { haggle = { good = true, bad = true }, runover = { win = true } }
-- play one effect on the play screen: wildcard (the True Wildcard banner and effect) and legendary (the Legendary banner and FlashFX)
DebugGotoRules.FX = { wildcard = true, legendary = true }

-- shallow copy of `state` turned into the named screen; `data` = { patrons = {def...}, packs = {def...}, boss = def }
function DebugGotoRules.synth(which, state, data)
	local s = {}
	for k, v in pairs(state) do s[k] = v end
	data = data or {}
	if which == "shop" or which == "roundwin" then
		s.phase = "shop"
		s.hand = {}
		s.lastRoundReward = which == "roundwin" and 9 or 0
		s.shopOffers, s.packOffers = {}, {}
		for i, p in ipairs(data.patrons or {}) do
			if i > 2 then break end
			s.shopOffers[#s.shopOffers + 1] = { id = p.id, name = p.name, description = p.description, price = 4 + i }
		end
		for i, p in ipairs(data.packs or {}) do
			if i > 2 then break end
			s.packOffers[#s.packOffers + 1] = { id = p.id, name = p.name, icon = p.icon, description = p.description, price = 3 + i }
		end
		s.tips = math.max(s.tips or 0, 12)
	elseif which == "haggle" then
		-- the Counter with a Wandering Stranger on offer: a good offer (short curse) or a bad one (a long curse picks the second scroll)
		s.phase = "shop"
		s.hand = {}
		s.shopOffers, s.packOffers = {}, {}
		for i, p in ipairs(data.patrons or {}) do
			if i > 2 then break end
			s.shopOffers[#s.shopOffers + 1] = { id = p.id, name = p.name, description = p.description, price = 4 + i }
		end
		s.tips = math.max(s.tips or 0, 20)
		local bad = data.variant == "bad"
		s.stranger = { id = "debug_purse", name = "The Fat Purse", icon = "\u{1F45B}", price = 4,
			blessing = bad and "Sharper hands" or "A big bonus this round",
			curse = bad and "Lose all your Tips at the start of every single round" or "-1 hand" }
	elseif which == "road" then
		-- the Choose your road screen with three sample stops
		s.phase = "roundSelect"
		s.night = math.max(s.night or 1, 3)
		s.worldChoices = data.roads or {}
		s.worldRoute = nil
		s.compassCharges = 1
	elseif which == "runover" then
		-- the merged Run Over screen with every field filled
		s.phase = "gameover"
		s.wonRun = data.variant == "win"
		s.night, s.round = s.wonRun and 8 or 5, 3
		s.roundScore, s.targetScore, s.tips = 604, 3174, 12
		s.continueOffer = "free"
		s.revived = false
		s.nextUnlock = { label = "Fast Hands at 3 wins" }
		local patrons = {}
		for i, p in ipairs(data.patrons or {}) do
			if i > 6 then break end
			patrons[#patrons + 1] = { id = p.id, name = p.name, icon = p.icon }
		end
		s.runSummary = { won = s.wonRun, night = s.night, round = s.round, bestHand = { name = "Full House", score = 1280 }, handsPlayed = 22,
			route = data.route or { { id = "dusty_road", name = "Dusty Road" }, { id = "meadow", name = "Meadow Gate" }, { id = "harbor", name = "Harbor Steps" } },
			routeIds = {}, patrons = patrons, rarity = s.wonRun and "legendary" or "rare", titleText = "Wandering Guest",
			blessing = { name = "Generous House", curse = "Prices rise by 1" }, badgeSaved = false, stake = 1, endlessBestByStake = {} }
	elseif which == "packroom" then
		-- a full table (5 of 5 Patrons), 20 Tips and an open Patron pack: Confirm on a pick opens the Make room step
		s.phase = "shop"
		s.hand = {}
		s.tips = 20
		s.patronSlotLimit = s.patronSlotLimit or 5
		s.ownedPatrons = {}
		local all = data.allPatrons or {}
		for i = 1, s.patronSlotLimit do
			local p = all[i]
			if p then s.ownedPatrons[#s.ownedPatrons + 1] = { id = p.id, name = p.name, description = p.description } end
		end
		local items = {}
		for i = s.patronSlotLimit + 1, #all do
			local p = all[i]
			items[#items + 1] = { id = p.id, name = p.name, icon = p.icon, description = p.description, category = "patron" }
			if #items >= 3 then break end
		end
		s.pendingPack = { packId = "buffoon_pack", category = "patron", pickCount = 1, items = items, paidPrice = 6 }
		s.shopOffers, s.packOffers = {}, {}
	elseif which == "rarity" then
		-- the first-Patron draft with a Patron of each tier that exists, three per page (rarity:2 for the next three)
		local tiers = data.tierPatrons or {}
		local page = math.max(1, data.page or 1)
		local options = {}
		for i = (page - 1) * 3 + 1, math.min(#tiers, page * 3) do
			local p = tiers[i]
			options[#options + 1] = { id = p.id, name = p.name, icon = p.icon, line1 = p.description or "", line2 = "" }
		end
		s.choice = { kind = "patron", title = "Choose your first Patron", text = "Debug: one Patron per rarity tier (page " .. page .. ").", icon = "?", options = options }
	elseif which == "gameover" then
		s.phase = "gameover"
	elseif which == "boss1" and data.boss then
		s.bossModifier = { id = data.boss.id, name = data.boss.name, description = data.boss.description }
		s.isBossRound = true
		s.round = 3 -- the boss is the last round of a Night: the stage, portrait and plate only act from there
		s.phase = "playing"
	end
	return s
end

-- reference design size the layouts are authored against
DebugGotoRules.BASE_W, DebugGotoRules.BASE_H = 1920, 957

-- UIScale that makes the 1920x957 design fit a w x h viewport (never above 1)
function DebugGotoRules.scaleFor(w, h)
	return math.min(1, w / DebugGotoRules.BASE_W, h / DebugGotoRules.BASE_H)
end

function DebugGotoRules.parse(value)
	if type(value) ~= "string" or value == "" then
		return nil, "empty value"
	end
	local text = value:lower():gsub("%s+", "")
	if text == "menu" or text == "news" or text == "round1" or text == "spectate" then
		return { kind = text }
	end
	if DebugGotoRules.SYNTH[text] then
		return { kind = "synth", which = text }
	end
	if text == "drawer:closed" or text == "drawer:open" then
		return { kind = "drawer", closed = text == "drawer:closed" }
	end
	local bs = text:match("^beatslow:(%a+)$")
	if bs == "on" or bs == "off" or bs == "freeze" then
		return { kind = "beatslow", mode = bs }
	end
	local pn = text:match("^patrons:(%d+)$")
	if pn then
		return { kind = "patrons", count = math.min(8, tonumber(pn)) }
	end
	if text == "playhand" or text == "playhand:keep" then
		return { kind = "playhand", keep = text == "playhand:keep" }
	end
	if text == "perf" then
		return { kind = "perf" }
	end
	if text == "loading" then
		return { kind = "loading", percent = 60 }
	end
	local pct = text:match("^loading:(%d+)$")
	if pct then
		return { kind = "loading", percent = math.min(100, tonumber(pct)) }
	end
	if DebugGotoRules.FX[text] then
		return { kind = "fx", effect = text }
	end
	-- haggle:good | haggle:bad | runover:win | rarity:<page 1..9>
	local name, variant = text:match("^(%a+):([%w]+)$")
	if name and DebugGotoRules.VARIANTS[name] and DebugGotoRules.VARIANTS[name][variant] then
		return { kind = "synth", which = name, variant = variant }
	end
	if name == "rarity" and variant:match("^%d$") and tonumber(variant) >= 1 then
		return { kind = "synth", which = "rarity", page = tonumber(variant) }
	end
	-- sfx:<cueName> plays that cue once, sfx:ladder an 8 step pitch ladder (Studio audition, Client/Sound.auditionCue)
	local sfxName = text:match("^sfx:([%w_]+)$")
	if sfxName then
		return { kind = "sfx", cue = sfxName }
	end
	-- scale:<w>x<h> shrinks GameUI to that viewport (Studio only), scale:off restores it
	if text == "scale:off" then
		return { kind = "scale", off = true }
	end
	local sw, sh = text:match("^scale:(%d+)x(%d+)$")
	if sw then
		local w, h = tonumber(sw), tonumber(sh)
		if w < 200 or h < 200 or w > 7680 or h > 4320 then
			return nil, "scale size out of range " .. value
		end
		return { kind = "scale", w = w, h = h, scale = DebugGotoRules.scaleFor(w, h) }
	end
	local parts = {}
	for part in text:gmatch("[^:]+") do
		parts[#parts + 1] = part
	end
	-- round1:<cardSetId> starts round 1 with that Card Set shown as a local preview (ids are snake_case, checked by the client)
	if parts[1] == "round1" and #parts == 2 and parts[2]:match("^[a-z0-9_]+$") then
		return { kind = "round1", setId = parts[2] }
	end
	if parts[1] == "tome" and #parts >= 2 and #parts <= 3 then
		local opener = DebugGotoRules.TOME_PAGES[parts[2]]
		if opener then
			return { kind = "tome", page = opener, sub = parts[3] }
		end
		return nil, "unknown tome page " .. parts[2]
	end
	return nil, "unknown value " .. value
end

-- What to answer to a table state while round1 is being reached.
-- Returns "choice", optionId (pick the first option), "select" (start the round) or nil.
function DebugGotoRules.round1Step(state)
	if type(state) ~= "table" then return nil end
	if type(state.choice) == "table" and type(state.choice.options) == "table" and state.choice.options[1] then
		return "choice", state.choice.options[1].id
	end
	if state.phase == "roundSelect" then return "select" end
	return nil
end

-- The round1 jump has a fixed step order: start (StartSeedRun, menu hidden, GameRoot shown, tutorial overlay hidden)
-- -> choice (the first option, as many times as the server asks) -> select (the first Round Select card) -> hand.
-- stepOf(state) names where the table is; handCount(state) is the number of dealt cards once the round is playing, else nil.
DebugGotoRules.ROUND1_ORDER = { "start", "choice", "select", "hand" }

function DebugGotoRules.stepOf(state)
	if type(state) ~= "table" then return "start" end
	if type(state.choice) == "table" and type(state.choice.options) == "table" and state.choice.options[1] then return "choice" end
	if state.phase == "roundSelect" then return "select" end
	if state.phase == "playing" and type(state.hand) == "table" and #state.hand > 0 then return "hand" end
	return "start"
end

function DebugGotoRules.handCount(state)
	if DebugGotoRules.stepOf(state) == "hand" then return #state.hand end
	return nil
end

-- seconds to wait for the whole chain before warning which step it stopped at
DebugGotoRules.ROUND1_TIMEOUT = 12

return DebugGotoRules
