--[[
	Shared/Engine/Minigames.lua
	The four map minigames (claude/MAP_DESIGN.md section 6), pure rules scored on the SERVER. The client only
	sends moves; every result, deck order and answer is decided here. Losing costs nothing.

	  dice      Roll one die at a time (up to 3) trying to get as close to 7 as you can without going over.
	            Hold at any time; the house then rolls until it has 5 or more. Higher score wins, ties lose.
	  cardflip  Memory match: 6 cards (3 pairs) face down, 8 flips (two flips = one try). Match all 3 pairs.
	  lockpick  A needle sweeps a dial with a green arc; stop it inside the arc 3 times in at most 5 tries.
	  trivia    3 kid-safe tavern-lore questions (patrons, poker hands), 3 answers each, 15 seconds apiece.

	A game is a plain table: Minigames.new(game, rng, now) -> game state, Minigames.act(g, action, arg, now) ->
	ok, info. `rng(n)` returns 1..n (never the run's rng, see Minigames.newRng); `now` is a clock in seconds
	passed in so tests control time. g.done / g.won say how it ended.

	A win may give a map token (max MAX_TOKENS per run, never on ranked boards) and, half the time, a compass
	charge; Minigames.reward applies that to a run state and a profile.
]]

local Patrons = require(script.Parent.Patrons)
local HandEvaluator = require(script.Parent.HandEvaluator)
local PlayerProfile = require(script.Parent.PlayerProfile)

local Minigames = {}

Minigames.MAX_TOKENS = 3
Minigames.Games = { dice = true, cardflip = true, lockpick = true, trivia = true }
Minigames.DICE_TARGET = 7
Minigames.FLIP_LIMIT = 8
Minigames.LOCK_HITS, Minigames.LOCK_TRIES = 3, 5
Minigames.ARC_WIDTH = 50 -- degrees of the green arc
Minigames.QUESTION_SECONDS = 15
Minigames.QUESTIONS = 3

-- A small independent generator (LCG) so a minigame never touches the run's rng and stays repeatable from a
-- seed. Plain arithmetic only: every product stays below 2^53.
function Minigames.newRng(seed)
	local h = (math.floor(tonumber(seed) or 1) % 4294967296)
	return function(n)
		h = (h * 69069 + 1) % 4294967296
		return (math.floor(h / 65536) % n) + 1
	end
end

local function shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- ===== dice =====
local function diceHouse(g, rng)
	g.house = { total = 0, dice = {} }
	while g.house.total < 5 and #g.house.dice < 3 do
		local d = rng(6)
		g.house.dice[#g.house.dice + 1] = d
		g.house.total = g.house.total + d
	end
	local houseScore = g.house.total <= Minigames.DICE_TARGET and g.house.total or 0
	g.houseScore = houseScore
	g.score = g.total <= Minigames.DICE_TARGET and g.total or 0
	g.done = true
	g.won = g.score > houseScore
end

local function diceAct(g, action)
	if g.done then return false, "finished" end
	if action == "roll" then
		if #g.dice >= 3 then return false, "no_rolls_left" end
		local d = g.rng(6)
		g.dice[#g.dice + 1] = d
		g.total = g.total + d
		if g.total > Minigames.DICE_TARGET then
			g.score, g.houseScore, g.done, g.won = 0, 0, true, false -- bust
			return true, { die = d, bust = true }
		end
		if #g.dice == 3 then
			diceHouse(g, g.rng)
		end
		return true, { die = d }
	elseif action == "hold" then
		if #g.dice == 0 then return false, "roll_first" end
		diceHouse(g, g.rng)
		return true, {}
	end
	return false, "bad_action"
end

-- ===== card flip =====
local function flipAct(g, action, index)
	if g.done then return false, "finished" end
	if action ~= "flip" then return false, "bad_action" end
	if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > 6 then return false, "bad_index" end
	if g.matched[index] then return false, "already_matched" end
	if g.pending == index then return false, "already_flipped" end
	g.flips = g.flips + 1
	local face = g.faces[index]
	local info = { face = face }
	if not g.pending then
		g.pending = index
	else
		if g.faces[g.pending] == face then
			g.matched[g.pending], g.matched[index] = true, true
			g.pairs = g.pairs + 1
			info.match = true
		else
			info.match = false
			info.hide = { g.pending, index }
			g.lastMiss = { g.pending, g.faces[g.pending], index, face } -- shown for a moment, then hidden again
		end
		g.pending = nil
	end
	if g.pairs == 3 then
		g.done, g.won = true, true
	elseif g.flips >= Minigames.FLIP_LIMIT and not g.pending then
		g.done, g.won = true, false
	elseif g.flips >= Minigames.FLIP_LIMIT + 0 and g.pending then
		-- out of flips with one card hanging: the game is over
		g.done, g.won = true, false
	end
	return true, info
end

-- ===== lockpick =====
-- The needle's angle in degrees at `t` seconds: back and forth over 0..360 at `speed` degrees per second.
function Minigames.needleAt(t, speed)
	local span = 360
	local p = (t * speed) % (2 * span)
	return p <= span and p or (2 * span - p)
end

local function arcHit(angle, center, width)
	local d = math.abs(angle - center) % 360
	if d > 180 then d = 360 - d end
	return d <= width / 2
end

local function lockAct(g, action, _arg, now)
	if g.done then return false, "finished" end
	if action ~= "stop" then return false, "bad_action" end
	-- The server reads the needle itself from its own clock; the client's reported angle is ignored.
	local angle = Minigames.needleAt(math.max(0, now - g.startedAt), g.speed)
	g.tries = g.tries + 1
	local hit = arcHit(angle, g.center, Minigames.ARC_WIDTH)
	if hit then
		g.hits = g.hits + 1
		g.center = g.rng(360) - 1 -- the arc moves after each pick
	end
	if g.hits >= Minigames.LOCK_HITS then
		g.done, g.won = true, true
	elseif g.tries >= Minigames.LOCK_TRIES then
		g.done, g.won = true, false
	end
	return true, { hit = hit, angle = angle, center = g.center }
end

-- ===== trivia =====
local function buildQuestions(rng)
	local questions = {}
	-- Which patron does this? (the description of a random patron, plus two other descriptions)
	local patrons = {}
	for _, p in ipairs(Patrons.Definitions) do
		if type(p.description) == "string" and p.description ~= "" then patrons[#patrons + 1] = p end
	end
	local function patronQuestion()
		local pool = shuffle({ table.unpack(patrons) }, rng)
		local right = pool[1]
		local answers = { { text = right.description, ok = true }, { text = pool[2].description }, { text = pool[3].description } }
		shuffle(answers, rng)
		return { text = "What does " .. right.name .. " do?", answers = answers }
	end
	-- Which poker hand is stronger?
	local function handQuestion()
		local order = HandEvaluator.HandOrder
		local indices = {}
		for i = 1, #order do indices[i] = i end
		shuffle(indices, rng)
		local picks = { indices[1], indices[2], indices[3] }
		local strongest = math.max(picks[1], picks[2], picks[3])
		local answers = {}
		for i, idx in ipairs(picks) do
			answers[i] = { text = order[idx], ok = (idx == strongest) or nil }
		end
		return { text = "Which poker hand is the strongest?", answers = answers }
	end
	for i = 1, Minigames.QUESTIONS do
		questions[i] = (i % 2 == 1) and patronQuestion() or handQuestion()
	end
	return questions
end

local function triviaAct(g, action, index, now)
	if g.done then return false, "finished" end
	if action ~= "answer" then return false, "bad_action" end
	local q = g.questions[g.current]
	if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > #q.answers then return false, "bad_index" end
	local late = now - g.askedAt > Minigames.QUESTION_SECONDS + 1 -- 1s of grace for latency
	local right = (not late) and q.answers[index].ok == true
	if right then g.correct = g.correct + 1 end
	g.current = g.current + 1
	g.askedAt = now
	if g.current > #g.questions then
		g.done, g.won = true, g.correct >= 2 -- 2 of 3
	end
	return true, { right = right, late = late }
end

-- ===== public =====
function Minigames.new(game, rng, now)
	if not Minigames.Games[game] then return nil end
	now = now or 0
	local g = { game = game, rng = rng, done = false, won = false, startedAt = now }
	if game == "dice" then
		g.dice, g.total = {}, 0
	elseif game == "cardflip" then
		g.faces = shuffle({ 1, 1, 2, 2, 3, 3 }, rng)
		g.matched, g.flips, g.pairs = {}, 0, 0
	elseif game == "lockpick" then
		g.speed = 150 + rng(100) -- degrees per second, 151 to 250
		g.center = rng(360) - 1
		g.hits, g.tries = 0, 0
	elseif game == "trivia" then
		g.questions = buildQuestions(rng)
		g.current, g.correct, g.askedAt = 1, 0, now
	end
	return g
end

function Minigames.act(g, action, arg, now)
	if type(g) ~= "table" or g.done == nil then return false, "no_game" end
	now = now or 0
	if g.game == "dice" then return diceAct(g, action)
	elseif g.game == "cardflip" then return flipAct(g, action, arg)
	elseif g.game == "lockpick" then return lockAct(g, action, arg, now)
	elseif g.game == "trivia" then return triviaAct(g, action, arg, now)
	end
	return false, "bad_game"
end

-- What the client may see: never the answers, never the unflipped faces.
function Minigames.view(g, now)
	if not g then return nil end
	local v = { game = g.game, done = g.done, won = g.won }
	if g.game == "dice" then
		v.dice, v.total, v.house = g.dice, g.total, g.done and g.house or nil
		v.score, v.houseScore = g.score, g.houseScore
	elseif g.game == "cardflip" then
		v.flips, v.pairs, v.matched, v.pending = g.flips, g.pairs, g.matched, g.pending
		v.pendingFace = g.pending and g.faces[g.pending] or nil
		v.flipLimit = Minigames.FLIP_LIMIT
		v.matchedFaces = {}
		for i in pairs(g.matched) do v.matchedFaces[i] = g.faces[i] end -- matched cards are face up anyway
		v.lastMiss = g.lastMiss
	elseif g.game == "lockpick" then
		v.speed, v.center, v.hits, v.tries, v.startedAt = g.speed, g.center, g.hits, g.tries, g.startedAt
		v.width, v.maxTries, v.needHits = Minigames.ARC_WIDTH, Minigames.LOCK_TRIES, Minigames.LOCK_HITS
	elseif g.game == "trivia" then
		v.current, v.correct, v.total = g.current, g.correct, #g.questions
		local q = g.questions[g.current]
		if q then
			v.question = { text = q.text, answers = {} }
			for i, a in ipairs(q.answers) do v.question.answers[i] = a.text end
			v.secondsLeft = math.max(0, Minigames.QUESTION_SECONDS - ((now or g.askedAt) - g.askedAt))
		end
	end
	return v
end

-- A win: +1 map token (max MAX_TOKENS per run; none on ranked boards, i.e. when the run has a fixed route),
-- and a 50% chance of a compass charge. Returns { token = bool, compass = bool }.
function Minigames.reward(state, profile, rng)
	local out = { token = false, compass = false }
	if not state or state.worldPlan then return out end
	if (state.mapTokens or 0) < Minigames.MAX_TOKENS then
		state.mapTokens = (state.mapTokens or 0) + 1
		out.token = true
	end
	if profile and rng(2) == 1 and PlayerProfile.addCompassCharge(profile) then
		out.compass = true
	end
	return out
end

return Minigames
