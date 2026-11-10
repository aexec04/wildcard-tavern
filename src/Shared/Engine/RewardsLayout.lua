--[[
	Engine/RewardsLayout.lua
	Pure layout for the Collection Rewards rows (Client/CollectionRewardsPanel). A row holds the category emblem on the left
	(with its percent on a brass plate under it and a progress ring of dots around it), the group name, and the four milestone
	tiles. The tiles are spread evenly across the rest of the row (no dead space on the right); on a narrow row they drop
	under the emblem instead of overflowing. Rects are { x, y, w, h } in row pixels.

	  RewardsLayout.row(rowW)          { rowH, emblem, plate, name, count, chips = { rect x4 }, stacked }
	  RewardsLayout.ringDots(n, cx, cy, r)   n dot centres around the emblem
	  RewardsLayout.litDots(percent, n)      how many of the n ring dots are lit
	  RewardsLayout.emblemKey(groupId)       art key in RewardsEmblemArt for a group (nil when it has none)
	  RewardsLayout.pouchKey(reward)         "rewards_pouch_small" | "rewards_pouch_full" for a Tips reward, else nil
]]

local RewardsLayout = {}

RewardsLayout.PAD = 12
RewardsLayout.EMBLEM = 84
RewardsLayout.NAME_W = 150
RewardsLayout.CHIP_W, RewardsLayout.CHIP_H = 118, 104
RewardsLayout.MIN_CHIP, RewardsLayout.MIN_GAP = 80, 8
RewardsLayout.ROW_H = 124

local EMBLEMS = {
	patrons = "rewards_emblem_patrons", recipes = "rewards_emblem_recipes", bosses = "rewards_emblem_bosses",
	sets = "rewards_emblem_cardsets", titles = "rewards_emblem_titles", bonds = "rewards_emblem_bonds", passes = "rewards_emblem_passes",
}

function RewardsLayout.emblemKey(groupId)
	return EMBLEMS[groupId]
end

function RewardsLayout.pouchKey(reward)
	if type(reward) ~= "table" or reward.kind ~= "tips" then return nil end
	return (reward.amount or 0) >= 3 and "rewards_pouch_full" or "rewards_pouch_small"
end

-- n evenly spaced rects in [x0, x0 + avail] with equal gaps, chips at most CHIP_W wide
local function spread(x0, avail, n, y, h)
	local P = RewardsLayout
	local w = P.CHIP_W
	local gap = n > 1 and (avail - n * w) / (n - 1) or 0
	if gap < P.MIN_GAP then
		w = math.max(P.MIN_CHIP, math.floor((avail - (n - 1) * P.MIN_GAP) / n))
		gap = n > 1 and (avail - n * w) / (n - 1) or 0
	end
	local out = {}
	for i = 1, n do
		out[i] = { x = math.floor(x0 + (i - 1) * (w + gap) + 0.5), y = y, w = w, h = h }
	end
	return out
end

function RewardsLayout.row(rowW, n)
	local P = RewardsLayout
	n = n or 4
	local emblem = { x = P.PAD, y = 6, w = P.EMBLEM, h = P.EMBLEM }
	local plate = { x = P.PAD + math.floor((P.EMBLEM - 58) / 2), y = 6 + P.EMBLEM + 2, w = 58, h = 22 }
	local name = { x = P.PAD + P.EMBLEM + P.PAD, y = 8, w = P.NAME_W, h = 20 }
	local count = { x = name.x, y = 30, w = P.NAME_W, h = 20 }
	local x0 = name.x + P.NAME_W + P.PAD
	local avail = rowW - P.PAD - x0
	local need = n * P.MIN_CHIP + (n - 1) * P.MIN_GAP
	if avail >= need then
		return { rowH = P.ROW_H, emblem = emblem, plate = plate, name = name, count = count, stacked = false,
			chips = spread(x0, avail, n, 8, P.CHIP_H) }
	end
	local top = plate.y + plate.h + 8 -- narrow: the tiles drop under the emblem, the full width of the row
	local fullW = rowW - 2 * P.PAD
	local perRow = fullW >= need and n or math.max(1, math.floor((fullW + P.MIN_GAP) / (P.MIN_CHIP + P.MIN_GAP)))
	local chips, rows = {}, math.ceil(n / perRow)
	for r = 1, rows do
		local count = math.min(perRow, n - (r - 1) * perRow)
		for _, rect in ipairs(spread(P.PAD, fullW, count, top + (r - 1) * (P.CHIP_H + 8), P.CHIP_H)) do
			chips[#chips + 1] = rect
		end
	end
	return { rowH = top + rows * (P.CHIP_H + 8), emblem = emblem, plate = plate, name = name, count = count, stacked = true, chips = chips }
end

function RewardsLayout.ringDots(n, cx, cy, r)
	local out = {}
	for i = 0, n - 1 do
		local a = -math.pi / 2 + i * 2 * math.pi / n -- starts at the top, runs clockwise
		out[#out + 1] = { x = cx + math.cos(a) * r, y = cy + math.sin(a) * r }
	end
	return out
end

function RewardsLayout.litDots(percent, n)
	return math.max(0, math.min(n, math.floor((percent or 0) / 100 * n + 0.5)))
end

return RewardsLayout
