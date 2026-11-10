--[[
	Shared/Engine/FlairRoomLayout.lua
	Pure data mapping and layout maths for the Flair dressing room (Client/FlairDressingRoom.lua). No Roblox calls, so
	it is unit tested. Rects are { x, y, w, h } in the panel's local pixels.

	Data (from Flair.view, never a hardcoded list):
	  drawers(view)          one drawer per Flair slot: id, name, icon, ownedCount, total, items
	                         item.state = "equipped" | "owned" | "locked"; locked items carry tag (brass tag text) and ratio
	  equippedSlots(view)    one entry per slot: the equipped option (or the slot default)
	  detail(item)           what the detail card says and which of Equip / Preview / Buy it offers
	Layout:
	  rects(W, H)            title, bundle, stage, mirror, curtains, detail card, equipped slots, cabinet, close
	  drawerRects(cab, n, openIndex)   closed drawer fronts plus the open tray (a drawer's tray sits under its own front)
	  cell(compact), grid(trayW, count, cell)   medallion cells inside a tray
	  placeTooltip(anchor, size, screen, avoid)   one tooltip, clamped on screen and clear of the live preview
]]

local FlairRoomLayout = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

FlairRoomLayout.TAG_LABEL = {
	rank = "Rank", stake = "Stake", quests = "Quests", legend = "Legend", achievement = "Achievement", store = "Store",
}

-- ===== data mapping =====

local function tagText(option)
	if option.store then return "Tavern Store" end
	local label = FlairRoomLayout.TAG_LABEL[option.unlockKind or ""]
	if option.goal and label then
		return string.format("%s %d of %d", label, math.floor(option.progress or 0), math.floor(option.goal))
	end
	return label or "Locked"
end
FlairRoomLayout.tagText = tagText

function FlairRoomLayout.drawers(view)
	local out = {}
	if not view or not view.slots then return out end
	for _, slot in ipairs(view.slots) do
		local items, owned = {}, 0
		for _, option in ipairs(slot.options) do
			local state = option.equipped and "equipped" or (option.owned and "owned" or "locked")
			if option.owned then owned = owned + 1 end
			local ratio = nil
			if state == "locked" and option.goal and option.goal > 0 and not option.store then
				ratio = clamp((option.progress or 0) / option.goal, 0, 1)
			end
			items[#items + 1] = {
				id = option.id, slotId = slot.id, name = option.name, icon = option.icon, rarity = option.rarity or "common",
				state = state, hint = option.hint or "", store = option.store == true,
				tag = state == "locked" and tagText(option) or nil, ratio = ratio, option = option,
			}
		end
		out[#out + 1] = { id = slot.id, name = slot.name, icon = slot.icon, ownedCount = owned, total = #items, items = items }
	end
	return out
end

function FlairRoomLayout.equippedSlots(view)
	local out = {}
	if not view or not view.slots then return out end
	for _, slot in ipairs(view.slots) do
		local pick = nil
		for _, option in ipairs(slot.options) do
			if option.equipped then pick = option break end
		end
		out[#out + 1] = {
			slotId = slot.id, slotName = slot.name, slotIcon = slot.icon,
			optionId = pick and pick.id or nil, optionName = pick and pick.name or "Nothing", optionIcon = pick and pick.icon or slot.icon,
			option = pick,
		}
	end
	return out
end

function FlairRoomLayout.detail(item)
	if not item then
		return { title = "Pick a piece", how = "Open a drawer and tap a piece to see how to get it.", canEquip = false, canPreview = false, canBuy = false }
	end
	local how
	if item.state == "equipped" then how = "Equipped right now."
	elseif item.state == "owned" then how = "Unlocked. Tap Equip to wear it."
	elseif item.store then how = "Sold in the Tavern Store."
	else how = item.hint ~= "" and item.hint or "Keep playing to unlock it." end
	return {
		title = item.name, how = how,
		canEquip = item.state == "owned", canPreview = item.state ~= "locked", canBuy = item.state == "locked" and item.store,
	}
end

-- ===== layout =====

function FlairRoomLayout.isCompact(W, H)
	return W < 1100 or H < 640
end

function FlairRoomLayout.rects(W, H)
	local compact = FlairRoomLayout.isCompact(W, H)
	local m = compact and 10 or 16
	local gap = compact and 8 or 12
	local topH = compact and 58 or 68
	local bottomH = compact and 46 or 54
	local cy, ch, cw = topH, H - topH - bottomH, W - 2 * m
	local stageW = math.floor((cw - gap) * 0.58)
	local slotsH = compact and 60 or 72
	local stage = { x = m, y = cy, w = stageW, h = ch - slotsH - gap }
	local slots = { x = m, y = cy + stage.h + gap, w = stageW, h = slotsH }
	local cabinet = { x = m + stageW + gap, y = cy, w = cw - gap - stageW, h = ch }
	local pad = compact and 6 or 10
	local detailH = compact and (H < 480 and 96 or 112) or 132
	local detail = { x = stage.x + pad, y = stage.y + stage.h - detailH - pad, w = stage.w - 2 * pad, h = detailH }
	local curtainW = math.floor(stage.w * 0.07)
	local mirrorTop = stage.y + pad
	local mirror = {
		x = stage.x + curtainW + pad, y = mirrorTop,
		w = stage.w - 2 * (curtainW + pad), h = detail.y - pad - mirrorTop,
	}
	local btnW, btnH = 190, 30
	return {
		compact = compact, margin = m, gap = gap, pad = pad,
		title = { x = m, y = 4, w = W - 2 * m - btnW - 10, h = topH - 6 },
		bundle = { x = W - m - btnW, y = math.floor((topH - btnH) / 2), w = btnW, h = btnH },
		stage = stage, mirror = mirror, detail = detail, slots = slots, cabinet = cabinet,
		curtainL = { x = stage.x, y = stage.y, w = curtainW, h = stage.h },
		curtainR = { x = stage.x + stage.w - curtainW, y = stage.y, w = curtainW, h = stage.h },
		close = { x = math.floor((W - 110) / 2), y = H - bottomH + math.floor((bottomH - 34) / 2), w = 110, h = 34 },
	}
end

-- Inner layout of the detail card: name, how-to line and one row of buttons.
function FlairRoomLayout.detailParts(card)
	local pad, btnH = 10, 34
	local btnW, bgap = 100, 8
	local by = card.h - btnH - 8
	return {
		name = { x = pad, y = 6, w = card.w - 2 * pad, h = 24 },
		how = { x = pad, y = 32, w = card.w - 2 * pad, h = by - 32 - 4 },
		buttons = {
			{ x = pad, y = by, w = btnW, h = btnH },
			{ x = pad + btnW + bgap, y = by, w = btnW, h = btnH },
			{ x = pad + 2 * (btnW + bgap), y = by, w = btnW, h = btnH },
		},
	}
end

function FlairRoomLayout.splitRow(row, n, gap)
	local out = {}
	if n < 1 then return out end
	local w = math.floor((row.w - (n - 1) * gap) / n)
	for i = 1, n do
		out[i] = { x = row.x + (i - 1) * (w + gap), y = row.y, w = w, h = row.h }
	end
	return out
end

-- Cabinet: n drawer fronts stacked; the open drawer's tray sits right under its front, the fronts after it move down.
-- Closed drawers get a tray of height 0 so the client can tween the 0.2 s slide.
function FlairRoomLayout.drawerRects(cab, n, openIndex)
	local compact = cab.w < 420
	local p = compact and 6 or 10
	local frontH = compact and 40 or 48
	local dg = 6
	local inner = { x = cab.x + p, y = cab.y + p, w = cab.w - 2 * p, h = cab.h - 2 * p }
	local trayH = math.max(0, inner.h - (n * frontH + (n - 1) * dg) - (openIndex and dg or 0))
	local fronts, trays = {}, {}
	local y = inner.y
	for i = 1, n do
		fronts[i] = { x = inner.x, y = y, w = inner.w, h = frontH }
		y = y + frontH + dg
		if i == openIndex then
			trays[i] = { x = inner.x, y = y, w = inner.w, h = trayH }
			y = y + trayH + dg
		else
			trays[i] = { x = inner.x, y = y, w = inner.w, h = 0 }
		end
	end
	return { fronts = fronts, trays = trays, inner = inner, frontH = frontH }
end

-- Medallion cell: round medallion, name (two lines) and a brass tag line plus progress rail.
function FlairRoomLayout.cell(compact)
	local med = compact and 64 or 84
	return { med = med, w = med + 40, h = med + 4 + 34 + 4 + 22 + 4 + 6, nameH = 34, tagH = 22, railH = 6 }
end

function FlairRoomLayout.grid(trayW, count, cell)
	local gap = 8
	local usable = trayW - 12
	local cols = math.max(1, math.floor((usable + gap) / (cell.w + gap)))
	local used = cols * cell.w + (cols - 1) * gap
	local x0 = math.floor((trayW - used) / 2)
	local out = {}
	for i = 1, count do
		local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
		out[i] = { x = x0 + c * (cell.w + gap), y = 8 + r * (cell.h + gap), w = cell.w, h = cell.h }
	end
	local rows = math.ceil(count / cols)
	return { cells = out, cols = cols, canvasH = 8 + rows * (cell.h + gap) }
end

local function hit(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
FlairRoomLayout.intersects = hit

-- The single tooltip: try above, below, right and left of the anchor; the first spot fully on screen and clear of
-- `avoid` (the live preview) wins; otherwise clamp the best candidate on screen.
function FlairRoomLayout.placeTooltip(anchor, size, screen, avoid)
	local mg = 8
	local function fit(x, y)
		return clamp(x, mg, math.max(mg, screen.w - size.w - mg)), clamp(y, mg, math.max(mg, screen.h - size.h - mg))
	end
	local cx = anchor.x + anchor.w / 2 - size.w / 2
	local cy = anchor.y + anchor.h / 2 - size.h / 2
	local ys = { anchor.y - size.h - 6, anchor.y + anchor.h + 6 }
	local xs = { cx, anchor.x, anchor.x + anchor.w - size.w }
	local candidates = {}
	for _, y in ipairs(ys) do
		for _, x in ipairs(xs) do candidates[#candidates + 1] = { x, y } end
	end
	candidates[#candidates + 1] = { anchor.x + anchor.w + 6, cy }
	candidates[#candidates + 1] = { anchor.x - size.w - 6, cy }
	if avoid then -- last resorts: just right of the preview, then just below it
		candidates[#candidates + 1] = { avoid.x + avoid.w + mg, anchor.y - size.h - 6 }
		candidates[#candidates + 1] = { avoid.x + avoid.w + mg, anchor.y + anchor.h + 6 }
		candidates[#candidates + 1] = { anchor.x, avoid.y + avoid.h + mg }
	end
	local first = nil
	for _, cand in ipairs(candidates) do
		local x, y = fit(cand[1], cand[2])
		local rect = { x = x, y = y, w = size.w, h = size.h }
		first = first or rect
		if not (avoid and hit(rect, avoid)) and not hit(rect, anchor) then
			return x, y
		end
	end
	return first.x, first.y
end

return FlairRoomLayout
