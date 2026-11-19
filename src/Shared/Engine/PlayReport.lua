--[[
	Engine/PlayReport.lua
	Client side of the server's play report (RunState state.lastPlay, built by buildPlayReport). Pure, tested.

	The score reveal used to play the client's own hand preview. That preview is a second calculation: for anything
	random (a Lucky Garnish hit, a Brittle card shattering) it rolled its own dice, so the reveal could show a bonus the
	server never paid. Now the server reports what the hand really scored and the reveal plays that. These helpers turn
	the report (cards named by position) back into the shape Client/ScorePopup already plays (cards named by table).

	PlayReport.split(hand, indices) -> played, held
	    the hand's cards the way the server splits them: the played cards in hand order, then the cards kept in hand order
	PlayReport.isNew(report, seqBefore) -> bool
	    true when the report is a newer hand than the one the client had when Play was pressed
	PlayReport.apply(preview, report, played, held, patronById) -> preview-shaped table
	    the preview's own fields (target, round score, tavern notes) with the server's hand name, chips, mult, score,
	    breakdown, shattered cards and wildcard choice in place of the client's
	PlayReport.isLegendary(score, targetScore, breakdown) -> bool
	    the "legendary hand" rule: 2.2 times the round target, or one x4 (or more) Mult entry
	PlayReport.baseOf(breakdown) -> chips, mult, count
	    the hand's own Chips and Mult (the leading entries whose source is the hand itself) and how many entries that
	    was. The reveal shows these with the hand name and counts up from there, instead of ticking up from 0 x 0.
	PlayReport.wildcardLabel(resolution) -> "8 of Hearts", "K of Spades", or nil
	    the True Wildcard banner's wording for { rank, suit }. apply() writes it as wildcardResolution.label, and the
	    hub's preview uses it too, so the banner (Client/ScorePopup) always has a card to name.
	PlayReport.ghostFace(card, isPlayed, wild) -> rank, suit, mystery
	    what a card's ghost shows in the reveal. The run's True Wildcard is a Mystery card in the hand: played, its
	    ghost shows the card it locks in as (wild = the preview's wildcardResolution); kept in hand, or with no known
	    choice, it stays a Mystery card (mystery = true). Every other card is itself.
	PlayReport.TIMEOUT
	    how long the reveal waits for the report before it plays the local preview instead (which never rolls luck)
]]

local M = {}

M.TIMEOUT = 0.7
M.LEGENDARY_SCORE_FACTOR = 2.2
M.LEGENDARY_XMULT = 4

local RANK_LETTERS = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }

function M.wildcardLabel(resolution)
	if type(resolution) ~= "table" or resolution.rank == nil or resolution.suit == nil then
		return nil
	end
	return (RANK_LETTERS[resolution.rank] or tostring(resolution.rank)) .. " of " .. tostring(resolution.suit)
end

-- The ghost of the True Wildcard used to be drawn with the rank and suit the card was dealt with. The hand never shows
-- those (the card is a Mystery card there), so a Four of a Kind of Eights was revealed with a 4 of Hearts in it.
function M.ghostFace(card, isPlayed, wild)
	if type(card) ~= "table" then
		return nil, nil, false
	end
	if card.isTrueWildcard and not card.wildcardLocked then
		if isPlayed and type(wild) == "table" and wild.rank ~= nil and wild.suit ~= nil then
			return wild.rank, wild.suit, false
		end
		return card.rank, card.suit, true
	end
	return card.rank, card.suit, false
end

function M.split(hand, indices)
	local chosen = {}
	for _, i in ipairs(indices or {}) do
		chosen[i] = true
	end
	local played, held = {}, {}
	for i, card in ipairs(hand or {}) do
		if chosen[i] then
			played[#played + 1] = card
		else
			held[#held + 1] = card
		end
	end
	return played, held
end

function M.isNew(report, seqBefore)
	return type(report) == "table" and type(report.seq) == "number" and report.seq ~= seqBefore
end

function M.isLegendary(score, targetScore, breakdown)
	if targetScore and targetScore > 0 and (score or 0) >= targetScore * M.LEGENDARY_SCORE_FACTOR then
		return true
	end
	for _, entry in ipairs(breakdown or {}) do
		if entry.kind == "xmult" and entry.amount >= M.LEGENDARY_XMULT then
			return true
		end
	end
	return false
end

function M.baseOf(breakdown)
	local chips, mult, count = 0, 0, 0
	for i, entry in ipairs(breakdown or {}) do
		local source = entry.source
		if not (source and source.type == "hand") or i > 2 then
			break
		end
		if entry.kind == "chips" then
			chips = chips + entry.amount
		elseif entry.kind == "mult" then
			mult = mult + entry.amount
		else
			break
		end
		count = i
	end
	return chips, mult, count
end

function M.apply(preview, report, played, held, patronById)
	local out = {}
	for key, value in pairs(preview or {}) do
		out[key] = value
	end
	local breakdown = {}
	for _, entry in ipairs(report.entries or {}) do
		local from = entry.source or {}
		local source = { type = from.type, patronId = from.patronId, bond = from.bond, set = from.set }
		if from.played then
			source.card = played and played[from.played] or nil
		elseif from.held then
			source.card = held and held[from.held] or nil
		end
		if from.patronId and patronById then
			source.patron = patronById(from.patronId)
		end
		breakdown[#breakdown + 1] = { kind = entry.kind, amount = entry.amount, label = entry.label, source = source }
	end
	local broken = {}
	for _, position in ipairs(report.broken or {}) do
		if played and played[position] then
			broken[#broken + 1] = played[position]
		end
	end
	out.name = report.handName or out.name
	out.chips, out.mult, out.score = report.chips, report.mult, report.score
	out.breakdown = breakdown
	out.brokenCards = broken
	-- The server names the True Wildcard's new rank and suit only, and the banner reads .label. The bare table used to
	-- take the place of the preview's labelled one, and the whole reveal stopped on "attempt to concatenate nil".
	local wild = report.wildcard
	if type(wild) == "table" then
		out.wildcardResolution = { rank = wild.rank, suit = wild.suit, label = M.wildcardLabel(wild) }
	end
	out.fromServer = true
	return out
end

return M
