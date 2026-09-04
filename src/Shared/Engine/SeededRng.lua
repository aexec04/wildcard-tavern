--[[
	SeededRng.lua
	DAILY CHALLENGE (Phase 11): a small, deterministic random-number source,
	independent of `math.random`, so two different players (or the same
	player replaying) get the EXACT same sequence of random draws given the
	same starting seed. `RunState.new(options, rng)` already accepted a
	custom `rng` function from day one (it's how the engine test suite
	forces specific outcomes -- see EngineTests.lua's `scriptedRng`/
	`alwaysHitRng`) -- this file is just the first "real" (non-test) rng
	source plugged into that same seam.

	What "same seed -> same run" actually means here, worth being explicit
	about: it means the same seed produces the same sequence of ANSWERS to
	"what's the next random draw" -- the shop offers, pack reveals, Boss
	Round pick, etc. you'll see are identical to another player's UP UNTIL
	either of you makes a different choice than the other (a different
	card played, a different item bought) -- because a different choice
	consumes a different NUMBER of random draws before the next one, which
	shifts everything downstream out of sync. This is normal, expected
	seeded-run behavior (the same idea Balatro's own "Seeds" feature uses)
	-- it is NOT a bug, and it's exactly what makes a Daily Challenge
	leaderboard meaningful: everyone starts from the identical first shop/
	Boss/deck order, and how far they get from there is genuinely about
	their own choices, not luck.

	Deliberately pure Lua -- no Roblox APIs, no bitwise operators (Lua 5.3
	added native bitwise operators as an infix syntax, but Luau -- what
	Roblox actually runs -- does NOT support that syntax at all, and
	doesn't ship Lua 5.2's `bit32` library either; using either would pass
	this project's local `lua5.3` syntax check while silently failing to
	even PARSE in real Roblox. Every operation below is plain +, -, *, %,
	which both interpreters agree on) -- testable with plain `lua5.3` like
	every other Shared/Engine module.
]]

local SeededRng = {}

-- A textbook Linear Congruential Generator (Numerical Recipes' constants).
-- Not cryptographically random and not perfectly uniform once folded down
-- to a small range (see the `% n` note in .new below) -- neither matters
-- here; this only needs to be FAST, DETERMINISTIC, and PORTABLE across
-- lua5.3 (this sandbox) and Luau (real Roblox), which a plain arithmetic
-- LCG is, and a "real" RNG (Roblox's Random.new, os.clock-seeded
-- math.random, etc.) generally isn't guaranteed to be bit-for-bit across
-- engine versions.
local MODULUS = 4294967296 -- 2^32
local MULTIPLIER = 1664525
local INCREMENT = 1013904223

-- Returns an `rng(n)` function -- draws an integer in [1, n], matching the
-- exact contract every existing rng call site in RunState.lua/Packs-related
-- code already expects (same as `math.random(n)`'s single-argument form).
-- Calling `SeededRng.new(seed)` twice with the same seed and then calling
-- the results the same number of times produces IDENTICAL sequences.
function SeededRng.new(seed)
	seed = math.floor(tonumber(seed) or 0) % MODULUS
	if seed < 0 then
		seed = seed + MODULUS
	end
	local state = seed

	return function(n)
		assert(type(n) == "number" and n >= 1, "SeededRng: n must be >= 1")
		state = (MULTIPLIER * state + INCREMENT) % MODULUS
		return (state % math.floor(n)) + 1
	end
end

-- Derives a deterministic seed from a UTC calendar date -- every player
-- who starts a Daily Challenge on the same UTC day gets the same seed,
-- regardless of their own timezone or local clock. Accepts an optional
-- Unix timestamp (os.time()-shaped) so this stays testable without
-- depending on the actual current date -- defaults to "right now".
function SeededRng.dailySeed(timestamp)
	local dateString = os.date("!%Y%m%d", timestamp) -- e.g. "20260831"
	return tonumber(dateString)
end

-- Same idea as dailySeed, but the actual UTC "YYYY-MM-DD" string -- used
-- as the DataStore/leaderboard key for the day (Server/init.server.lua),
-- kept here so the seed and the key it's associated with can never drift
-- out of sync with each other (both derived from the same os.date call
-- shape, in one place).
function SeededRng.dailyDateKey(timestamp)
	return os.date("!%Y-%m-%d", timestamp)
end

-- PHASE 16 (Weekly Challenge): same idea as dailySeed, but bucketed into
-- 7-day windows instead of calendar days. Deliberately NOT calendar-week
-- aligned (no Monday/Sunday reasoning, no "%V" strftime specifier, which
-- isn't guaranteed portable across platforms/locales) -- just
-- `floor(unixTime / secondsPerWeek)`, an integer that ticks up by exactly
-- 1 every 7 days, forever, starting from the Unix epoch. Every player's
-- server clock is UTC-based (os.time()), so this lands on the same
-- 7-day window for everyone regardless of their own timezone, same
-- guarantee dailySeed makes for calendar days.
local SECONDS_PER_WEEK = 604800 -- 60 * 60 * 24 * 7

function SeededRng.weeklySeed(timestamp)
	timestamp = timestamp or os.time()
	return math.floor(timestamp / SECONDS_PER_WEEK)
end

-- Same idea as dailyDateKey -- the DataStore/leaderboard key for the
-- week, derived from the exact same window math as weeklySeed above so
-- the two can never drift out of sync with each other. "W" prefix just
-- keeps it visually distinct from a Daily dateKey at a glance (and from
-- looking like a plain number that could be mistaken for something
-- else) -- it's not trying to be a real calendar week label.
function SeededRng.weeklyDateKey(timestamp)
	return "W" .. tostring(SeededRng.weeklySeed(timestamp))
end

-- PHASE 16 (Shareable Seed Codes): turns an arbitrary short string a
-- player typed in (or got from a friend) into a deterministic seed
-- number, so "type the same code -> get the same run" without needing
-- any server round-trip or DataStore lookup at all -- the code itself
-- IS the seed, just human-shareable. A djb2-style rolling hash: pure
-- +, *, % (see this file's header on why bitwise ops are off-limits),
-- case-insensitive (upper-cased first) so "storm7" and "STORM7" hash
-- identically -- codes are meant to be read aloud/typed casually, not
-- treated as case-sensitive passwords.
function SeededRng.codeToSeed(code)
	code = string.upper(tostring(code or ""))
	local hash = 5381
	for i = 1, #code do
		hash = (hash * 33 + string.byte(code, i)) % MODULUS
	end
	return hash
end

-- Suggests a random shareable code for a player who doesn't already have
-- one in mind from a friend -- NOT part of the deterministic-replay seam
-- itself (this is a one-time "here's a code you could use" convenience,
-- so plain math.random is fine here, unlike everywhere else in this
-- file). Charset deliberately excludes 0/O and 1/I/L -- easy to
-- mis-read or mis-type out loud/over chat, exactly the failure mode
-- that would silently desync two friends' "identical" runs.
local CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

function SeededRng.randomCode(length)
	length = length or 6
	local parts = {}
	for i = 1, length do
		local idx = math.random(1, #CODE_CHARS)
		parts[i] = string.sub(CODE_CHARS, idx, idx)
	end
	return table.concat(parts)
end

return SeededRng
