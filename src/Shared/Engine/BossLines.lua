--[[
	Shared/Engine/BossLines.lua
	Taunts for Boss Rounds: kid-safe tavern humour, never an insult about the player.
	Events: intro, rule_hit (the rule bites), half (boss at 50%), low_hands (1 hand left),
	defeated (the player wins), victory (the player loses).

	Per-boss lines (ByBoss) cover intro and defeated for every boss in BossRounds; every other
	event, and any boss without an entry, falls back to the category pool (Fallback), then to
	Fallback.default. BossLines.pick is deterministic from a seed (the run seed), so Daily and
	Seed runs repeat the same lines.
]]

local BossLines = {}

BossLines.Events = { "intro", "rule_hit", "half", "low_hands", "defeated", "victory" }

BossLines.Fallback = {
	default = {
		intro = { "Welcome to my table!", "Let us see what you have got.", "Take a seat, friend." },
		rule_hit = { "House rules, I'm afraid.", "That one is on the menu!", "Rules are rules!" },
		half = { "Halfway there. Not bad!", "You are warming up nicely.", "Hmm, my table is wobbling." },
		low_hands = { "One hand left, hm?", "Make it count!", "The last hand is the best one." },
		defeated = { "Well played! Take your prize.", "You win this round!", "The table is yours." },
		victory = { "Better luck next time!", "Come back soon, friend.", "That was a close one!" },
	},
	debuff = {
		intro = { "Some cards are not welcome tonight.", "I have my favourites, and they are not yours.", "Certain cards sit this one out." },
		rule_hit = { "Those cards are not scoring!", "Not tonight, little cards.", "Sit down, you lot." },
		half = { "You found a way around me!", "Clever, with the cards I allow." },
		low_hands = { "Running out of friendly cards?", "One hand to find a good one." },
		defeated = { "You beat my rule fair and square!", "Every card welcome now." },
		victory = { "My rule won the day!", "Better luck with other cards." },
	},
	restriction = {
		intro = { "There is a rule, and I like it.", "Play by my rules tonight.", "Follow the rule and we will get along." },
		rule_hit = { "Mind the rule!", "Not that way, friend.", "The rule says no." },
		half = { "You are working around my rule!", "Halfway done, and still within the rules." },
		low_hands = { "Hands are running thin.", "One more hand, within the rules." },
		defeated = { "You bent without breaking. Bravo!", "Rules beaten, fair and square." },
		victory = { "The rule held strong!", "Rules are rules. See you again." },
	},
	weaken = {
		intro = { "Your scores will be a little softer tonight.", "I turned the dial down a notch.", "Everything is a bit weaker here." },
		rule_hit = { "A little less sparkle there!", "Turned down, as promised.", "Shaved a bit off that." },
		half = { "Still climbing, even with less!", "Impressive, with that handicap." },
		low_hands = { "Every point counts now.", "One hand to make it big." },
		defeated = { "You beat the weak table!", "Full power is yours again." },
		victory = { "A softer table won tonight.", "Turn it up next time!" },
	},
	squeeze = {
		intro = { "Pockets are a little lighter tonight.", "Fewer cards, bigger thinking.", "I tidied your hand for you." },
		rule_hit = { "Oops, some cards went missing!", "Whoosh, there go a few!", "Tidying up!" },
		half = { "Doing well with less!", "Halfway, with a thin hand." },
		low_hands = { "Only one hand left. Think it through!", "Short on hands and cards." },
		defeated = { "You made do with less. Wonderful!", "A full hand awaits you." },
		victory = { "A tight squeeze won it!", "Bigger hands next time!" },
	},
	tips = {
		intro = { "My table runs on tips, you know.", "Every card has a little price tonight.", "Mind your coin purse." },
		rule_hit = { "Tip jar, please!", "Clink, clink!", "That will cost you a coin." },
		half = { "Halfway, and still jingling!", "Your purse is holding up." },
		low_hands = { "One hand left, and a lighter purse.", "Spend wisely now." },
		defeated = { "You beat my tab! Well done.", "The tab is settled." },
		victory = { "The tab wins this time!", "Save a few coins for next time." },
	},
	target = {
		intro = { "The bar is set a little higher tonight.", "Aim high, friend.", "A taller target for a taller night." },
		rule_hit = { "The goal keeps its height!", "Higher still!", "No shortcuts here." },
		half = { "Halfway up the mountain!", "That is a big climb, and you are on it." },
		low_hands = { "One hand left for the summit.", "A big finish needed!" },
		defeated = { "You reached the top!", "What a climb!" },
		victory = { "The mountain stands today.", "Climb again soon!" },
	},
}

-- id -> { intro = {...}, defeated = {...} }. Other events use the category pool.
BossLines.ByBoss = {
	bouncer = { intro = { "Name's on the list? Let me check.", "One fewer card, one fewer worry." }, defeated = { "Fine, fine, you may come in.", "You got past me. Impressive!" } },
	short_notice = { intro = { "Surprise inspection! No time for extras.", "I told you at the last minute." }, defeated = { "You kept your cool. Bravo!", "Inspection passed!" } },
	house_rules = { intro = { "House rules: the target is a bit higher.", "Read the board on the wall, friend." }, defeated = { "You beat the house fair and square.", "The house salutes you." } },
	the_tab = { intro = { "Everything has a price, even a card.", "I keep a careful tab." }, defeated = { "Tab cleared. You are free to go!", "Paid in full, with style." } },
	thin_soup = { intro = { "Today's soup is a little thin.", "Not much flavour in your chips tonight." }, defeated = { "You made a feast from thin soup!", "Seconds, anyone?" } },
	slow_simmer = { intro = { "Good things simmer slowly.", "Your mult is on a low flame." }, defeated = { "Turn up the heat, you earned it!", "Cooked to perfection." } },
	rowdy_crowd = { intro = { "The crowd gets a little rowdy at this hour.", "Hold on to your hand!" }, defeated = { "You calmed the whole room!", "Cheers all around!" } },
	no_repeats = { intro = { "Same trick twice? Not at my table.", "Surprise me every time." }, defeated = { "Every hand a new one. Splendid!", "You kept it fresh." } },
	hearts_are_out = { intro = { "Hearts are taking the evening off.", "No hearts at my table." }, defeated = { "Hearts are welcome again!", "You won without a single heart." } },
	spades_are_out = { intro = { "Spades are away tonight.", "No digging in my garden." }, defeated = { "Spades are back in the game!", "You dug your way through!" } },
	no_vips = { intro = { "No royalty at my table.", "Jacks, Queens and Kings wait outside." }, defeated = { "Even without the royals, you shone!", "The court may enter." } },
	empty_pockets = { intro = { "Your favourite hand costs a lot tonight.", "Mind what you play too often." }, defeated = { "You kept your coins and the day!", "Pockets full again." } },
	full_table = { intro = { "Five cards, every time, please.", "A full table is a happy table." }, defeated = { "Full hands, full marks!", "Five stars to you." } },
	last_chance = { intro = { "You only get one discard. Choose well.", "One swap, that is all." }, defeated = { "One discard was enough!", "What a clever swap." } },
	short_staffed = { intro = { "We are short staffed: fewer cards, fewer swaps.", "Everyone is on a break." }, defeated = { "You managed beautifully with less!", "The staff is back." } },
	diamonds_are_out = { intro = { "Diamonds are not sparkling tonight.", "No shiny stones allowed." }, defeated = { "The diamonds sparkle again!", "You shone without them." } },
	clubs_are_out = { intro = { "Clubs are off the guest list.", "No clubs this evening." }, defeated = { "Clubs are welcome back!", "You did it without a club." } },
	steep_tab = { intro = { "The tab is steep tonight.", "Two coins a card, please." }, defeated = { "You settled a steep tab!", "What a bargain you made." } },
	thin_chips = { intro = { "The chips are running thin.", "A lighter bag of chips tonight." }, defeated = { "You stacked them high anyway!", "A big pile of chips for you." } },
	flat_mult = { intro = { "The mult fell a little flat.", "Not much bounce tonight." }, defeated = { "Bounce restored!", "You lifted it right up." } },
	double_tab = { intro = { "A tab and a taller goal. Double trouble!", "Everything costs a bit more." }, defeated = { "Double tab, double victory!", "That was a great run." } },
	lights_out = { intro = { "One hand. Make it a good one.", "The lamps go out after your first hand." }, defeated = { "One hand, one big win!", "The lights come back on." } },
	quick_service = { intro = { "Quick service: two hands only.", "We close the kitchen early." }, defeated = { "Fast and fabulous!", "Order up, and well done." } },
	stale_bread = { intro = { "The bread is a little stale tonight.", "Everything is a bit crunchy." }, defeated = { "Fresh loaves are on the way!", "You made toast out of it." } },
	one_at_a_time = { intro = { "One card at a time, friend.", "Slow and steady." }, defeated = { "One card, many wins!", "Take a bow." } },
	big_tab = { intro = { "Today's goal is double the size.", "A big tab for a big night." }, defeated = { "You paid the big tab!", "That was enormous." } },
	wild_crowd = { intro = { "The crowd is wild tonight!", "Hold on, cards may fly." }, defeated = { "You tamed the wild crowd!", "What a party." } },
	empty_handed = { intro = { "Three hands, one swap. Go!", "Bare hands tonight." }, defeated = { "Empty hands, full victory!", "A perfect finish." } },
	everythings_out = { intro = { "Everything is a little smaller tonight.", "The whole table is dialled down." }, defeated = { "You made it big in a small night!", "Everything is back." } },
	four_top = { intro = { "Four cards a hand, please.", "A table for four." }, defeated = { "A perfect party of four!", "Four stars." } },
	slow_night = { intro = { "A slow night, one card gone each hand.", "Easy does it." }, defeated = { "Slow and steady wins!", "A fine night's work." } },
	house_minimum = { intro = { "The house minimum is a little higher.", "A tiny step up tonight." }, defeated = { "You cleared the minimum with room to spare!", "The house nods." } },
	picked_over = { intro = { "The hearts are picked over and the deal is short.", "Slim pickings tonight." }, defeated = { "You found treasure in slim pickings!", "A feast, after all." } },
	rushed_order = { intro = { "Rush order: three hands only.", "No time to waste." }, defeated = { "Right on time!", "Order delivered." } },
	bare_bones = { intro = { "Bare bones tonight: less of everything.", "Just the basics." }, defeated = { "You built a feast from bare bones!", "Full pantry again." } },
}

-- The final Night boss and Endless milestone bosses get the biggest treatment.
-- milestones: array of { night = n } (JourneyMap.EndlessMilestones).
function BossLines.isGrand(night, nightCap, milestones)
	if night == (nightCap or 8) then
		return true
	end
	for _, m in ipairs(milestones or {}) do
		if m.night == night then
			return true
		end
	end
	return false
end

-- Plain string hash (31-multiplier), stable across runs and platforms.
local function hash(text)
	local h = 7
	for i = 1, #text do
		h = (h * 31 + text:byte(i)) % 2147483647
	end
	return h
end

-- The candidate lines for a boss and event: its own, else the category pool, else the default.
function BossLines.linesFor(bossId, category, event)
	local own = BossLines.ByBoss[bossId]
	if own and own[event] and #own[event] > 0 then
		return own[event]
	end
	local pool = BossLines.Fallback[category]
	if pool and pool[event] and #pool[event] > 0 then
		return pool[event]
	end
	return BossLines.Fallback.default[event] or {}
end

-- Deterministic pick: the same seed, boss and event always give the same line.
function BossLines.pick(bossId, category, event, seed)
	local lines = BossLines.linesFor(bossId, category, event)
	if #lines == 0 then
		return nil
	end
	local index = (hash(tostring(seed or 0) .. "|" .. tostring(bossId) .. "|" .. tostring(event)) % #lines) + 1
	return lines[index]
end

return BossLines
