--[[
	Shared/Engine/ShareVariants.lua
	The plain text share lines of the Run Over and Victory screens, three kind variants for each of four kinds, chosen by a seed so one
	run always shows the same line while different runs read differently. Pure Lua, no Roblox APIs, no links, no dashes.

	kinds: "win", "loss", "daily", "endless"
	ShareVariants.line(kind, ctx, seed) -> text of 80 characters or less
	  ctx = { night, name (the Daily's seed name), twist (the Daily's twist, added only when it still fits), hand (best hand name, win only), won (Daily) }
	ShareVariants.seedFor(state)        -> a whole number that is the same every time for the same run
	ShareVariants.count(kind, ctx)      -> how many variants are usable for that context (3 for every kind; a win without a best hand swaps its hand variant)

	A seeded run keeps ShareResult.challengeLine (it must carry the code); this module never prints a code.
]]

local GameName = require(script.Parent.GameName)

local ShareVariants = {}

ShareVariants.MAX_LENGTH = 80
ShareVariants.KINDS = { "win", "loss", "daily", "endless" }

-- {game} {n} {hand} {name} {reached}. A template with needs = "hand" is only used when a best hand is known; its stand in is `alt`.
local TEMPLATES = {
	win = {
		{ "I won {game} and reached Night {n}! Can you?" },
		{ "Won with a {hand} at Night {n} in {game}!", needs = "hand", alt = "Night {n} cleared and the run is won in {game}!" },
		{ "A win at Night {n} in {game}. Your turn!" },
	},
	loss = {
		{ "I reached Night {n} in {game}. Can you beat me?" },
		{ "Made it to Night {n} in {game}. Can you go further?" },
		{ "Night {n} in {game} this time. Want to try?" },
	},
	daily = {
		{ "Daily {name}: I {reached} Night {n} in {game}. Beat me?" },
		{ "My Daily {name} run {reached} Night {n} in {game}!" },
		{ "{game}, Daily {name}: I {reached} Night {n}. Try it!" },
	},
	endless = {
		{ "I reached Endless Night {n} in {game}. Can you beat me?" },
		{ "Endless Night {n} and still going in {game}!" },
		{ "Endless Night {n} in {game}. Can you top it?" },
	},
}

local function whole(v, fallback)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then return fallback end
	return math.floor(v)
end

local function fill(template, ctx)
	local night = math.max(1, math.min(999, whole(ctx.night, 1)))
	local values = {
		game = GameName.NAME,
		n = tostring(night),
		hand = tostring(ctx.hand or ""),
		name = tostring(ctx.name or "Run"),
		reached = ctx.won and "won and reached" or "reached",
	}
	return (template:gsub("{(%w+)}", function(key) return values[key] or "" end))
end

local function pick(kind, ctx)
	local list = TEMPLATES[kind] or TEMPLATES.loss
	local hasHand = type(ctx.hand) == "string" and ctx.hand ~= "" and #ctx.hand <= 18
	local out = {}
	for _, t in ipairs(list) do
		if t.needs == "hand" and not hasHand then out[#out + 1] = t.alt or t[1] else out[#out + 1] = t[1] end
	end
	return out
end

function ShareVariants.count(kind, ctx)
	return #pick(kind, ctx or {})
end

-- Same seed, same line. Strings are summed, anything else is floored; junk becomes 0.
local function index(seed, n)
	local s = 0
	if type(seed) == "string" then
		for i = 1, #seed do s = s + seed:byte(i) * i end
	else
		s = math.abs(whole(seed, 0))
	end
	return s % n + 1
end

function ShareVariants.line(kind, ctx, seed)
	ctx = type(ctx) == "table" and ctx or {}
	local list = pick(kind, ctx)
	local text = fill(list[index(seed, #list)], ctx)
	if kind == "daily" and type(ctx.twist) == "string" and ctx.twist ~= "" then
		local withTwist = text:gsub("^(Daily [^:,]-)([:,])", "%1 (" .. ctx.twist:gsub("%%", "") .. ")%2", 1)
		if withTwist ~= text and #withTwist <= ShareVariants.MAX_LENGTH then text = withTwist end
	end
	if #text > ShareVariants.MAX_LENGTH then text = text:sub(1, ShareVariants.MAX_LENGTH - 3) .. "..." end -- never reached by the shipped data (tested)
	return text
end

-- One whole number per run: the Night, the hands played and the score reached never change once the run is over.
function ShareVariants.seedFor(state)
	state = type(state) == "table" and state or {}
	return math.abs(whole(state.night, 0)) * 7 + math.abs(whole(state.handsPlayedTotal, 0)) * 3 + math.abs(whole(state.roundScore, 0))
end

return ShareVariants
