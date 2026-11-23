--[[
	Shared/Engine/DebugGotoRules.lua
	Pure parser for the Studio-only DebugGoto jump hook (Client/DebugGoto.lua). parse(value) returns
	{ kind = "menu" | "tome" | "news" | "round1" | "shop" | "spectate" | "sweep" | "map", page?, sub? } or nil, reason.
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

-- one step jumps that open an existing overlay by its OverlayManager opener id
DebugGotoRules.OPENERS = {
	daily = "dailyRewards", ["daily:done"] = "dailyLeaderboard", weekly = "dailyLeaderboard", settings = "settings",
}

-- every admin jump key, for the header comment and the tests
DebugGotoRules.ADMIN_KEYS = { "freshsave", "daily", "daily:done", "weekly", "seed", "store", "store:<tab>", "season", "collection", "collection:<tab>",
	"cardset:<id>", "settings", "share", "tavernmap:night=<n>" }

-- A StringValue only fires Changed when the text changes, so jumping to the same key twice needs the value cleared first.
-- Returns the values to assign in order: { "", value } when it is the same as the current one, else { value }.
-- parse("") answers nil, so the clearing step does nothing on the client.
function DebugGotoRules.assignSteps(current, value)
	if current == value then return { "", value } end
	return { value }
end

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
		s.bossModifier = { id = data.boss.id, name = data.boss.name, description = data.boss.description,
			handSizeDelta = data.boss.handSizeDelta }
		-- the synthetic jump keeps round1's dealt hand, so apply the boss's hand-size penalty to it here (never below 5)
		local delta = data.boss.handSizeDelta or 0
		if delta < 0 and type(s.hand) == "table" then
			local keep = math.max(5, #s.hand + delta)
			local trimmed = {}
			for i = 1, math.min(keep, #s.hand) do trimmed[i] = s.hand[i] end
			s.hand = trimmed -- a copy: the synthetic state is shallow, the live hand stays untouched
		end
		if #(s.ownedPatrons or {}) == 0 then -- round1 has no Patrons yet: seat up to 5 so the row shows faces, not empty seats
			s.ownedPatrons = {}
			for _, p in ipairs(data.allPatrons or data.patrons or {}) do
				if #s.ownedPatrons >= 5 then break end
				s.ownedPatrons[#s.ownedPatrons + 1] = { id = p.id, name = p.name, description = p.description }
			end
		end
		s.isBossRound = true
		s.round = 3 -- the boss is the last round of a Night: the stage, portrait and plate only act from there
		s.phase = "playing"
	end
	return s
end

-- reference design size the layouts are authored against
DebugGotoRules.BASE_W, DebugGotoRules.BASE_H = 1920, 957

-- UIScale that makes the 1920x957 design fit a w x h viewport (never above 1)
-- sweep: visits these jumps in order, SWEEP_SECONDS each, printing "[DebugGoto] sweep <screen>" so a chat session can capture each one.
-- Each step is a normal DebugGoto value; "label" is what the log line names. patrons:5 and the table screens need round1 reached first.
DebugGotoRules.SWEEP_SECONDS = 6
DebugGotoRules.SWEEP = {
	{ label = "menu", value = "menu" },
	{ label = "round1", value = "round1" },
	{ label = "round1 patrons:5", value = "patrons:5" },
	{ label = "boss1", value = "boss1" },
	{ label = "runover", value = "runover" },
	{ label = "runover:win", value = "runover:win" },
	{ label = "tome:collection", value = "tome:collection" },
	{ label = "counter", value = "shop" },
}

function DebugGotoRules.scaleFor(w, h)
	return math.min(1, w / DebugGotoRules.BASE_W, h / DebugGotoRules.BASE_H)
end

-- scale:WxH frame size: the asked size, never larger than the window
function DebugGotoRules.frameFor(w, h, vpW, vpH)
	return math.min(w, vpW or w), math.min(h, vpH or h)
end

-- a top-level GameUI object that fills the screen (scale 1 or near, small pixel offsets) is the one scale:WxH resizes
function DebugGotoRules.isFullScreenSize(xs, xo, ys, yo)
	return xs >= 0.95 and ys >= 0.95 and math.abs(xo) <= 64 and math.abs(yo) <= 64
end

-- Screens a set suffix is meant for (one per screen to check per set): menu, haggle, round1, boss1, map, store, season, collection.
DebugGotoRules.SET_SCREENS = { "menu", "haggle", "round1", "boss1", "map", "store", "season", "collection", "boon" }

-- Any jump may end in :<cardSetId> (haggle:winter_evening, haggle:good:golden_gala, boss1:dune_market, menu:meadow_picnic, map:harbor_lights ...).
-- The suffix is split off first, the rest parses as before, and the target gets setId so the client previews that set for the room, shop,
-- keeper, plates, menu and boss table through the Card Sets Preview path. The id must be a real Card Set (checked here, not in the client).
function DebugGotoRules.splitSet(value)
	if type(value) ~= "string" then return value, nil end
	local text = value:lower():gsub("%s+", "")
	local head, tail = text:match("^(.+):([a-z0-9_]+)$")
	if head and tail then
		local okC, CS = pcall(require, script.Parent.CosmeticSets)
		if okC and type(CS) == "table" and CS.getById and CS.getById(tail) then return head, tail end
	end
	return value, nil
end

function DebugGotoRules.parse(value)
	local head, setId = DebugGotoRules.splitSet(value)
	if setId and head == "equip" then return { kind = "equip", setId = setId } end
	if setId and head == "cardset" then return { kind = "round1", setId = setId } end -- cardset:<id>: the table with that Card Set previewed
	if setId then
		local target, why = DebugGotoRules.parseCore(head)
		if not target then return nil, why end
		target.setId = setId
		return target
	end
	return DebugGotoRules.parseCore(value)
end

function DebugGotoRules.parseCore(value)
	if type(value) ~= "string" or value == "" then
		return nil, "empty value"
	end
	local text = value:lower():gsub("%s+", "")
	if text == "equip" then return nil, "equip needs a card set id (equip:<setId>)" end
	if text == "menu" or text == "news" or text == "round1" or text == "spectate" then
		return { kind = text }
	end
	if text == "freshsave" then return { kind = "freshsave" } end -- a brand new profile (Studio-only server remote) then the menu
	local opener = DebugGotoRules.OPENERS[text]
	if opener then return { kind = "opener", opener = opener, key = text } end
	if text == "seed" then return { kind = "round1" } end -- the fixed-seed run (DebugGotoRules.SEED_CODE)
	if text == "share" then return { kind = "synth", which = "runover", variant = "win" } end -- the win screen holds the Invite and Share lines
	local tavernNight = text:match("^tavernmap:night=(%d+)$")
	if tavernNight then
		local n = tonumber(tavernNight)
		if n < 1 or n > 8 then return nil, "map night must be 1 to 8" end
		return { kind = "map", night = n }
	end
	local tabPage, tab = text:match("^(%a+):([%a_]+)$")
	if (tabPage == "store" or tabPage == "collection") and tab ~= "" then
		return { kind = "tome", page = tabPage, sub = tab }
	end
	if text == "boon" then -- the Night boon picker with three sample boons (boon:<setId> previews it in that Card Set)
		return { kind = "boon" }
	end
	if text == "map" then -- the real Tavern Map overlay (the same opener as the Journey corner button)
		return { kind = "map" }
	end
	local mapNight = text:match("^map:night=(%d+)$")
	if mapNight then
		local n = tonumber(mapNight)
		if n < 1 or n > 8 then return nil, "map night must be 1 to 8" end
		return { kind = "map", night = n }
	end
	if text == "store" then -- the Tavern Store panel, opened from the Menu like the Tome pages
		return { kind = "tome", page = "store" }
	end
	if text == "season" then -- the Season track panel (same opener path as store)
		return { kind = "tome", page = "season" }
	end
	if text == "collection" then -- short for tome:collection
		return { kind = "tome", page = "collection" }
	end
	if DebugGotoRules.SYNTH[text] then
		return { kind = "synth", which = text }
	end
	-- real run jumps (night:<n>, bossN:<id>, reward, shop:<tips>, recipes:<ids>, victory, endrun ...): Engine/DebugJump, Studio-only server remote
	do
		local op = require(script.Parent.DebugJump).parse(text)
		if op then return { kind = "jump", key = text, op = op.op } end
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
	if text == "sweep" or text == "sweep:stop" then
		return { kind = "sweep", stop = text == "sweep:stop", seconds = DebugGotoRules.SWEEP_SECONDS }
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
	-- boss1:<bossId> shows that Boss Round on the play screen (boss1 alone shows the first one). The caller checks the id.
	local bossId = text:match("^boss1:([%w_]+)$")
	if bossId then
		return { kind = "synth", which = "boss1", variant = bossId }
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
	-- audit:v2 prints the Gameplay v2 rect table and warnings for five window sizes (Studio only, Client/AuditV2)
	if text == "audit:v2" then return { kind = "audit" } end
	-- selfcheck walks the visible text of the open screen for dim, low contrast, mislayered, clipped or overlapping labels
	if text == "selfcheck" then return { kind = "selfcheck" } end
	-- tablecheck prints each table piece against the 1672 x 941 reference rects (Studio only, Client/TableCheck)
	if text == "tablecheck" then return { kind = "tablecheck" } end
	if text == "decorcheck" then return { kind = "decorcheck" } end -- felt, inlay, rail and deck rects of the live table (Client/DecorCheck)
	if text == "screencheck" then return { kind = "screencheck" } end -- Counter and Menu rects and text sizes (Client/ScreenCheck)
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
	-- equip:<cardSetId> really equips that set (Studio only server remote), so the true equipped path can be checked
	if parts[1] == "equip" and #parts == 2 and parts[2]:match("^[a-z0-9_]+$") then
		return { kind = "equip", setId = parts[2] }
	end
	-- round1:<cardSetId> starts round 1 with that Card Set shown as a local preview (ids are snake_case, checked by the client)
	if parts[1] == "round1" and #parts == 2 and parts[2]:match("^[a-z0-9_]+$") then
		return { kind = "round1", setId = parts[2] }
	end
	-- round1:mod=<blessingId>, round1:tag=<tagId>, or both joined by a comma (round1:mod=open_hands,tag=tip_jar)
	if parts[1] == "round1" and #parts == 2 and parts[2]:find("=", 1, true) then
		local out = { kind = "round1" }
		for item in parts[2]:gmatch("[^,]+") do
			local key, id = item:match("^(%a+)=([a-z0-9_]+)$")
			if (key ~= "mod" and key ~= "tag") or out[key .. "Id"] then
				return nil, "bad round1 option " .. item
			end
			out[key .. "Id"] = id
		end
		return out
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
-- wantedModId (optional): answer a blessing choice with that option when it is offered, else the first option.
function DebugGotoRules.round1Step(state, wantedModId)
	if type(state) ~= "table" then return nil end
	if type(state.choice) == "table" and type(state.choice.options) == "table" and state.choice.options[1] then
		if wantedModId and state.choice.kind == "modifier" then
			for _, option in ipairs(state.choice.options) do
				if option.id == wantedModId then return "choice", option.id end
			end
		end
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
