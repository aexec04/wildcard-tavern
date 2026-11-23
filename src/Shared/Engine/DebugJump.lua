--[[
	Engine/DebugJump.lua
	Studio-only admin jumps that put the REAL screen on the real run state (the owners test by jumping, not by playing a run).
	The client (Client/DebugGoto) sends the raw key to the DebugJump remote; the server (Studio only, rate limited, marks the run as
	debug so it never reaches a leaderboard) calls DebugJump.parse then DebugJump.apply. Nothing here runs outside Studio.

	Keys (all lower case):
	  night:<1..12>        Night n, round 1, that Night's real target and boss
	  bossN:<bossId>       N = 2..12: the boss round of Night N with that boss and its real rule (boss1:<id> is the older table preview)
	  boon                 the Night boon pick (a real draft on Round Select, Night 2 or later)
	  reward               the choose a Patron reward (a real draft; the table is trimmed so there is room)
	  shop:<tips>          the Counter with that many Tips (a real shop visit)
	  tips:<n>             sets the Tips (0..9999) on the live run
	  recipes:<id,id,..>   holds those Recipes (house, menu or secret ids) so the Recipe tray shows them
	  patrons:<id,id,..>   seats those Patrons by id (patrons:<n> seats n Patrons, that older key is handled elsewhere)
	  sellpatron           seats one Patron on the Counter with 12 Tips, ready to sell
	  tag:<tagId>          makes that Tag the current round's skip Tag
	  victory              Night 8 boss cleared: the real Victory moment and Counter
	  endrun, endrun:win   the real Run Over screen (a lost run, or a won one) on the live run
]]

local DebugJump = {}

DebugJump.MAX_KEY = 120
DebugJump.MAX_NIGHT = 12
DebugJump.MAX_LIST = 12

local function exists(kind, id)
	local E = script.Parent
	if kind == "patron" then return E.Patrons and require(E.Patrons).getById(id) ~= nil end
	if kind == "tag" then return require(E.Tags).getById(id) ~= nil end
	if kind == "boss" then return require(E.BossRounds).getById(id) ~= nil end
	if kind == "recipe" then
		local R = require(E.Recipes)
		return R.getHouseRecipeById(id) ~= nil or R.getMenuRecipeById(id) ~= nil or R.getSecretRecipeById(id) ~= nil
	end
	return false
end

local function ids(text, kind)
	local list = {}
	for id in text:gmatch("[^,]+") do
		if not id:match("^[a-z0-9_]+$") then return nil end
		if not exists(kind, id) then return nil end
		list[#list + 1] = id
		if #list > DebugJump.MAX_LIST then return nil end
	end
	return #list > 0 and list or nil
end

-- -> { op = ..., ... } or nil, reason. Never errors on any input.
function DebugJump.parse(key)
	if type(key) ~= "string" or key == "" or #key > DebugJump.MAX_KEY then return nil, "bad key" end
	local text = key:lower():gsub("%s+", "")
	if text == "boon" or text == "reward" or text == "victory" or text == "sellpatron" then return { op = text } end
	if text == "endrun" then return { op = "endrun", win = false } end
	if text == "endrun:win" then return { op = "endrun", win = true } end
	local n = text:match("^night:(%d+)$")
	if n then
		n = tonumber(n)
		if n < 1 or n > DebugJump.MAX_NIGHT then return nil, "night must be 1 to " .. DebugJump.MAX_NIGHT end
		return { op = "night", night = n }
	end
	local tips = text:match("^tips:(%d+)$")
	if tips then return { op = "tips", tips = math.min(9999, tonumber(tips)) } end
	local shopTips = text:match("^shop:(%d+)$")
	if shopTips then return { op = "shop", tips = math.min(9999, tonumber(shopTips)) } end
	local bn, bid = text:match("^boss(%d+):([a-z0-9_]+)$")
	if bn then
		bn = tonumber(bn)
		if bn < 2 or bn > DebugJump.MAX_NIGHT then return nil, "bossN needs N 2 to " .. DebugJump.MAX_NIGHT end
		if not exists("boss", bid) then return nil, "unknown boss " .. bid end
		return { op = "boss", night = bn, bossId = bid }
	end
	local r = text:match("^recipes:([a-z0-9_,]+)$")
	if r then
		local list = ids(r, "recipe")
		if list then return { op = "recipes", ids = list } end
		return nil, "bad recipe list"
	end
	local p = text:match("^patrons:([a-z0-9_,]+)$")
	if p and not p:match("^%d+$") then
		local list = ids(p, "patron")
		if list then return { op = "patrons", ids = list } end
		return nil, "bad patron list"
	end
	local tag = text:match("^tag:([a-z0-9_]+)$")
	if tag then
		if not exists("tag", tag) then return nil, "unknown Tag " .. tag end
		return { op = "tag", tagId = tag }
	end
	return nil, "unknown jump " .. text
end

-- true when the client should send this key to the server instead of parsing it as an older jump
function DebugJump.isJump(key)
	return (DebugJump.parse(key)) ~= nil
end

local function find(list, id)
	for _, def in ipairs(list or {}) do
		if def.id == id then return def end
	end
	return nil
end

local function seat(state, Patrons, patronIds)
	state.ownedPatrons = {}
	for _, id in ipairs(patronIds) do
		local def = Patrons.getById(id)
		if not def then return false, "unknown Patron " .. id end
		state.ownedPatrons[#state.ownedPatrons + 1] = def
	end
	return true
end

local function jumpTo(session, state, RunState, night, round)
	state.night, state.round = night, round
	state.roundOver, state.runOver, state.wonRun = false, false, false
	state.pendingPack = nil
	RunState.startRound(state)
	session.phase = "playing"
	session.choice = nil
end

--[[
	apply(session, op, deps) -> ok, message.
	session = the server session ({ state, phase, choice, ... }); deps = { RunState, RunChoice, Patrons, Recipes, Tags, BossRounds, openShop }.
]]
function DebugJump.apply(session, op, deps)
	if type(session) ~= "table" or type(session.state) ~= "table" or type(op) ~= "table" then return false, "no run" end
	local state, RunState = session.state, deps.RunState
	state.usedDebug = true
	local which = op.op
	if which == "tips" then
		state.tips = op.tips
		return true, "tips " .. op.tips
	elseif which == "night" then
		jumpTo(session, state, RunState, op.night, 1)
		return true, "night " .. op.night
	elseif which == "boss" then
		local boss = deps.BossRounds.getById(op.bossId)
		if not boss then return false, "unknown boss " .. op.bossId end
		-- start round 1 of the Night (a fresh Night state), then move to the boss round with the chosen boss
		jumpTo(session, state, RunState, op.night, 1)
		state.round = state.config.roundsPerNight
		state.nightBossModifier = boss
		state.bossesFaced = state.bossesFaced or {}
		RunState.startRound(state)
		state.nightBossModifier = boss -- startRound only re-picks at round 1, kept explicit
		state.bossModifier = boss
		state.targetScore = RunState.targetForRound(state, state.round)
		return true, "boss " .. boss.id .. " on night " .. op.night
	elseif which == "recipes" then
		local limit = RunState.recipeSlotLimit(state)
		state.houseRecipeInventory, state.menuRecipeInventory, state.secretRecipeInventory = {}, {}, {}
		local held = 0
		for _, id in ipairs(op.ids) do
			if held >= limit then break end
			if find(deps.Recipes.HouseRecipes, id) then table.insert(state.houseRecipeInventory, id)
			elseif find(deps.Recipes.MenuRecipes, id) then table.insert(state.menuRecipeInventory, id)
			elseif find(deps.Recipes.SecretRecipes, id) then table.insert(state.secretRecipeInventory, id)
			else return false, "unknown Recipe " .. id end
			held = held + 1
		end
		return true, "recipes " .. held
	elseif which == "patrons" then
		return seat(state, deps.Patrons, op.ids)
	elseif which == "tag" then
		local tag = deps.Tags.getById(op.tagId)
		if not tag then return false, "unknown Tag " .. op.tagId end
		state.currentRoundSkipTag = tag
		return true, "tag " .. op.tagId
	elseif which == "shop" or which == "sellpatron" or which == "victory" then
		state.pendingPack = nil
		state.roundOver, state.runOver = true, false
		if which == "victory" then
			state.night, state.round = state.config.nightCap, state.config.roundsPerNight
			state.wonRun = true
		end
		if which == "sellpatron" and #state.ownedPatrons == 0 then
			local first = deps.Patrons.Definitions[1]
			if first then state.ownedPatrons = { first } end
		end
		state.tips = (which == "shop") and op.tips or math.max(state.tips or 0, 12)
		session.phase = "shop"
		session.choice = nil
		deps.openShop(session)
		return true, which
	elseif which == "boon" or which == "reward" then
		state.night = math.max(2, state.night or 1)
		state.round = 1
		state.roundOver, state.runOver, state.pendingPack = false, false, nil
		if which == "reward" then
			local limit = RunState.patronSlotLimit(state)
			while #state.ownedPatrons >= limit do table.remove(state.ownedPatrons) end
			session.choice = deps.RunChoice.rewardDraft(state, true)
		else
			session.choice = deps.RunChoice.boonDraft(state, true)
		end
		if not session.choice then return false, which .. " has nothing to offer" end
		session.phase = "roundSelect"
		return true, which
	elseif which == "endrun" then
		state.runOver, state.roundOver = true, true
		state.wonRun = op.win == true
		if op.win then
			state.night = math.max(state.night or 1, state.config.nightCap)
			-- a real winning score for the final round, so the Run Over line reads "Final score: 5.2K / 4K", never 0 / target
			local target = math.max(1, math.floor(tonumber(state.targetScore) or 1))
			state.targetScore = target
			state.roundScore = math.max(math.floor(tonumber(state.roundScore) or 0), math.ceil(target * 1.3))
		end
		session.phase = "gameover"
		session.choice = nil
		return true, op.win and "endrun win" or "endrun"
	end
	return false, "unknown op"
end

return DebugJump
